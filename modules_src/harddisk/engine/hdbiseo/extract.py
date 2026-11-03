"""문서 안의 글자를 꺼낸다. 모든 함수는 파일을 읽기만 한다.

실패하면 ExtractError(쉬운 한국어 이유)를 던지고, 호출한 쪽에서
"읽을 수 없음" 목록에 기록한 뒤 다음 파일로 넘어간다.
"""

from __future__ import annotations

import re
import struct
import zipfile
import zlib
from xml.etree import ElementTree as ET

MAX_CHARS = 2_000_000  # 파일 하나에서 최대 200만 자까지만 색인


class ExtractError(Exception):
    pass


def _clip(text: str) -> str:
    text = re.sub(r"[ \t\r\f\v]+", " ", text)
    text = re.sub(r"\n\s*\n+", "\n", text)
    return text[:MAX_CHARS].strip()


def _open_zip(path: str) -> zipfile.ZipFile:
    try:
        return zipfile.ZipFile(path)
    except (zipfile.BadZipFile, OSError) as e:
        raise ExtractError("파일이 손상되었거나 열 수 없어요") from e


def _xml_texts(data: bytes, tag_suffix: str, para_suffix: str | None = None) -> str:
    try:
        root = ET.fromstring(data)
    except ET.ParseError as e:
        raise ExtractError("문서 구조가 손상되었어요") from e
    out: list[str] = []
    for el in root.iter():
        tag = el.tag.rsplit("}", 1)[-1]
        if tag == tag_suffix and el.text:
            out.append(el.text)
        elif para_suffix and tag == para_suffix:
            out.append("\n")
    return "".join(out)


# ---- 글 파일 ---------------------------------------------------------

def read_text_file(path: str) -> str:
    with open(path, "rb") as f:
        raw = f.read(MAX_CHARS * 2)
    if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
        return _clip(raw.decode("utf-16", errors="replace"))
    for enc in ("utf-8-sig", "cp949"):
        try:
            return _clip(raw.decode(enc))
        except UnicodeDecodeError:
            continue
    return _clip(raw.decode("utf-8", errors="replace"))


# ---- 오피스 새 형식(zip) -----------------------------------------------

def read_docx(path: str) -> str:
    z = _open_zip(path)
    with z:
        parts = [n for n in z.namelist() if re.match(r"word/(document|header\d*|footer\d*|footnotes)\.xml$", n)]
        if "word/document.xml" not in parts:
            raise ExtractError("워드 문서 본문을 찾지 못했어요")
        return _clip("\n".join(_xml_texts(z.read(n), "t", "p") for n in sorted(parts)))


def read_pptx(path: str) -> str:
    z = _open_zip(path)
    with z:
        slides = sorted(n for n in z.namelist() if re.match(r"ppt/slides/slide\d+\.xml$", n))
        return _clip("\n".join(_xml_texts(z.read(n), "t", "p") for n in slides))


def read_xlsx(path: str) -> str:
    import openpyxl

    try:
        wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    except Exception as e:  # openpyxl은 다양한 예외를 던진다
        raise ExtractError("엑셀 파일을 열 수 없어요(손상 또는 암호)") from e
    out: list[str] = []
    total = 0
    try:
        for ws in wb.worksheets:
            out.append(f"[{ws.title}]")
            for row in ws.iter_rows(values_only=True):
                cells = [str(c) for c in row if c is not None and str(c).strip()]
                if cells:
                    line = " ".join(cells)
                    out.append(line)
                    total += len(line)
                    if total > MAX_CHARS:
                        break
    finally:
        wb.close()
    return _clip("\n".join(out))


# ---- 한글 HWPX ---------------------------------------------------------

def read_hwpx(path: str) -> str:
    z = _open_zip(path)
    with z:
        sections = sorted(
            (n for n in z.namelist() if re.match(r"Contents/section\d+\.xml$", n)),
            key=lambda n: int(re.findall(r"\d+", n)[-1]),
        )
        if not sections:
            raise ExtractError("한글(HWPX) 본문을 찾지 못했어요")
        return _clip("\n".join(_xml_texts(z.read(n), "t", "p") for n in sections))


# ---- 한글 HWP 5.0 (OLE) -----------------------------------------------

HWPTAG_PARA_TEXT = 67
_CHAR_CTRL = {0, 10, 13} | set(range(24, 32))


def parse_hwp_records(data: bytes) -> str:
    """HWP 본문 레코드에서 문단 글자(PARA_TEXT)를 꺼낸다."""
    out: list[str] = []
    pos, n = 0, len(data)
    while pos + 4 <= n:
        (header,) = struct.unpack_from("<I", data, pos)
        pos += 4
        tag = header & 0x3FF
        size = (header >> 20) & 0xFFF
        if size == 0xFFF:
            if pos + 4 > n:
                break
            (size,) = struct.unpack_from("<I", data, pos)
            pos += 4
        body = data[pos:pos + size]
        pos += size
        if tag == HWPTAG_PARA_TEXT:
            out.append(_hwp_para_text(body))
    return "\n".join(t for t in out if t)


def _hwp_para_text(body: bytes) -> str:
    chars: list[str] = []
    i, n = 0, len(body) - 1
    while i < n:
        (code,) = struct.unpack_from("<H", body, i)
        if code < 32:
            if code in _CHAR_CTRL:
                if code in (10, 13):
                    chars.append("\n")
                i += 2
            else:
                i += 16  # 인라인·확장 컨트롤은 8글자(16바이트)
            continue
        chars.append(chr(code))
        i += 2
    return "".join(chars).strip()


def read_hwp(path: str) -> str:
    import olefile

    try:
        if not olefile.isOleFile(path):
            raise ExtractError("한글(HWP) 파일 형식이 아니에요(손상 가능)")
        ole = olefile.OleFileIO(path)
    except ExtractError:
        raise
    except Exception as e:
        raise ExtractError("한글(HWP) 파일을 열 수 없어요") from e
    with ole:
        if not ole.exists("FileHeader"):
            raise ExtractError("한글(HWP) 파일 정보가 없어요")
        header = ole.openstream("FileHeader").read(40)
        if not header.startswith(b"HWP Document File"):
            raise ExtractError("한글(HWP) 파일 형식이 아니에요")
        flags = struct.unpack_from("<I", header, 36)[0]
        compressed, password, distribute = bool(flags & 1), bool(flags & 2), bool(flags & 4)
        if password:
            raise ExtractError("암호가 걸린 한글 문서예요")
        texts: list[str] = []
        if not distribute:
            sections = sorted(
                ("/".join(e) for e in ole.listdir() if len(e) == 2 and e[0] == "BodyText"),
                key=lambda s: int(re.findall(r"\d+", s)[-1] or 0),
            )
            for sec in sections:
                raw = ole.openstream(sec).read()
                if compressed:
                    try:
                        raw = zlib.decompressobj(-15).decompress(raw)
                    except zlib.error:
                        continue
                texts.append(parse_hwp_records(raw))
        body = "\n".join(t for t in texts if t)
        if not body and ole.exists("PrvText"):
            # 미리보기 글자(앞부분만) — 배포용 문서 등에서 대신 사용
            body = ole.openstream("PrvText").read().decode("utf-16-le", errors="ignore").rstrip("\x00")
        if not body.strip():
            raise ExtractError("한글 문서에서 글자를 찾지 못했어요(배포용 문서일 수 있음)")
        return _clip(body)


# ---- 옛 오피스(doc/xls/ppt) — 최선 노력 --------------------------------

_HANGUL_RUN = re.compile(r"[\uac00-\ud7a3A-Za-z0-9][\uac00-\ud7a3A-Za-z0-9 .,:;()\-/%~!?'\"]{3,}")


def read_old_office(path: str) -> str:
    import olefile

    try:
        if not olefile.isOleFile(path):
            raise ExtractError("옛 오피스 파일 형식이 아니에요")
        ole = olefile.OleFileIO(path)
    except ExtractError:
        raise
    except Exception as e:
        raise ExtractError("옛 오피스 파일을 열 수 없어요") from e
    with ole:
        found: list[str] = []
        for entry in ole.listdir():
            name = entry[-1]
            if name in ("WordDocument", "Workbook", "Book", "PowerPoint Document", "1Table", "0Table"):
                data = ole.openstream(entry).read(20_000_000)
                found.extend(_HANGUL_RUN.findall(data.decode("utf-16-le", errors="ignore")))
                found.extend(m for m in _HANGUL_RUN.findall(data.decode("latin-1")) if len(m) > 6)
        text = "\n".join(found)
        if not text.strip():
            raise ExtractError("옛 오피스 문서에서 글자를 찾지 못했어요")
        return _clip(text)


# ---- PDF ---------------------------------------------------------------

def read_pdf(path: str, max_pages: int = 500) -> str:
    from pypdf import PdfReader
    from pypdf.errors import PdfReadError

    try:
        reader = PdfReader(path)
        if reader.is_encrypted:
            try:
                reader.decrypt("")
            except Exception as e:
                raise ExtractError("암호가 걸린 PDF예요") from e
        out: list[str] = []
        for i, page in enumerate(reader.pages):
            if i >= max_pages:
                break
            out.append(page.extract_text() or "")
    except ExtractError:
        raise
    except (PdfReadError, OSError, ValueError, KeyError, TypeError) as e:
        raise ExtractError("PDF가 손상되었거나 열 수 없어요") from e
    text = _clip("\n".join(out))
    if not text:
        raise ExtractError("글자가 없는 PDF예요(스캔한 그림일 수 있음)")
    return text


def read_rtf(path: str) -> str:
    raw = read_text_file(path)
    raw = re.sub(r"\\'([0-9a-f]{2})", lambda m: chr(int(m.group(1), 16)), raw)
    raw = re.sub(r"\\u(-?\d+)\??", lambda m: chr(int(m.group(1)) % 65536), raw)
    return _clip(re.sub(r"\\[a-z]+-?\d* ?|[{}]", "", raw))


EXTRACTORS = {
    "txt": read_text_file, "md": read_text_file, "csv": read_text_file, "log": read_text_file,
    "rtf": read_rtf,
    "docx": read_docx, "pptx": read_pptx, "xlsx": read_xlsx, "xlsm": read_xlsx,
    "hwpx": read_hwpx, "hwp": read_hwp,
    "doc": read_old_office, "xls": read_old_office, "ppt": read_old_office,
    "pdf": read_pdf,
}


def extract_text(path: str, ext: str) -> str:
    fn = EXTRACTORS.get(ext.lower())
    if fn is None:
        raise ExtractError("글자를 꺼낼 수 없는 종류예요")
    try:
        return fn(path)
    except ExtractError:
        raise
    except MemoryError as e:
        raise ExtractError("파일이 너무 커요") from e
    except PermissionError as e:
        raise ExtractError("읽을 권한이 없어요") from e
    except OSError as e:
        raise ExtractError("파일을 읽을 수 없어요(연결 끊김 또는 손상)") from e
    except Exception as e:  # 예상 못 한 손상 파일도 전체를 멈추지 않게
        raise ExtractError("파일 형식이 손상되었어요") from e
