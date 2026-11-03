"""테스트·체험용 샘플 폴더 만들기(사진·영상·한글·엑셀·워드·PDF·깨진 파일 등).

실제 하드디스크가 없어도 전체 흐름을 확인할 수 있게 한다. 지정한 새 폴더 안에만 파일을 만든다.
"""

from __future__ import annotations

import datetime as dt
import io
import math
import os
import shutil
import struct
import subprocess
import wave
import zipfile
import zlib
from pathlib import Path

# ---- 사진 -------------------------------------------------------------

def _jpeg(path: Path, color, taken: str | None, gps: tuple[float, float] | None = None, size=(640, 480)):
    from PIL import Image, ImageDraw

    im = Image.new("RGB", size, color)
    d = ImageDraw.Draw(im)
    for i in range(0, size[0], 40):
        d.line([(i, 0), (size[0] - i, size[1])], fill=(255, 255, 255), width=2)
    exif = Image.Exif()
    if taken:
        exif[306] = taken
        exif.get_ifd(0x8769)[36867] = taken
    if gps:
        lat, lon = gps

        def dms(v):
            v = abs(v)
            d_ = int(v)
            m = int((v - d_) * 60)
            s = round(((v - d_) * 60 - m) * 60, 2)
            return (float(d_), float(m), float(s))

        g = exif.get_ifd(0x8825)
        g[1] = "N" if lat >= 0 else "S"
        g[2] = dms(lat)
        g[3] = "E" if lon >= 0 else "W"
        g[4] = dms(lon)
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, "JPEG", exif=exif.tobytes(), quality=85)


# ---- 영상 -------------------------------------------------------------

def _box(t: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", 8 + len(payload)) + t + payload


def synthetic_mp4(path: Path, taken: dt.datetime, seconds: float) -> None:
    """ffmpeg 없이 만드는 최소 mp4 머리(촬영 시각·길이만 들어 있음)."""
    ctime = int((taken - dt.datetime(1904, 1, 1)).total_seconds())
    mvhd = bytes([0, 0, 0, 0]) + struct.pack(">IIII", ctime, ctime, 1000, int(seconds * 1000)) + b"\x00" * 80
    data = _box(b"ftyp", b"isom\x00\x00\x02\x00isomiso2mp41") + _box(b"moov", _box(b"mvhd", mvhd))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def real_mp4(path: Path, taken: str, seconds: int = 4, pattern: str = "testsrc") -> bool:
    ff = shutil.which("ffmpeg")
    if not ff:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(
        [ff, "-y", "-v", "quiet", "-f", "lavfi", "-i", f"{pattern}=duration={seconds}:size=320x240:rate=10",
         "-f", "lavfi", "-i", f"sine=frequency=300:duration={seconds}",
         "-shortest", "-pix_fmt", "yuv420p", "-metadata", f"creation_time={taken}", str(path)],
        capture_output=True, timeout=120, check=False,
    )
    return r.returncode == 0 and path.exists()


def speech_like_wav(path: Path, seconds: int = 6) -> None:
    """말소리처럼 켜졌다 꺼지는 소리(목소리 구간 찾기 시험용)."""
    rate = 16000
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        frames = bytearray()
        for i in range(rate * seconds):
            t = i / rate
            on = int(t) % 2 == 0
            v = int(8000 * math.sin(2 * math.pi * 220 * t) * (1 if on else 0.01))
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))


# ---- 문서 -------------------------------------------------------------

def _docx(path: Path, paragraphs: list[str]) -> None:
    import docx

    d = docx.Document()
    for p in paragraphs:
        d.add_paragraph(p)
    path.parent.mkdir(parents=True, exist_ok=True)
    d.save(path)


def _xlsx(path: Path, rows: list[list]) -> None:
    import openpyxl

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "정산"
    for r in rows:
        ws.append(r)
    path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(path)


def _hwpx(path: Path, paragraphs: list[str]) -> None:
    ns = 'xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section"'
    body = "".join(f"<hp:p><hp:run><hp:t>{p}</hp:t></hp:run></hp:p>" for p in paragraphs)
    xml = f'<?xml version="1.0" encoding="UTF-8"?><hs:sec {ns}>{body}</hs:sec>'
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("mimetype", "application/hwp+zip")
        z.writestr("Contents/section0.xml", xml)


def _hwp_record(tag: int, payload: bytes, level: int = 0) -> bytes:
    size = len(payload)
    if size >= 0xFFF:
        return struct.pack("<II", tag | (level << 10) | (0xFFF << 20), size) + payload
    return struct.pack("<I", tag | (level << 10) | (size << 20)) + payload


def _cfb(streams: dict[str, bytes]) -> bytes:
    """아주 작은 OLE(복합 문서) 파일 작성기 — 한글(HWP) 시험 파일용.

    streams 키는 "이름" 또는 "저장소/이름". 모든 스트림을 4096바이트 이상으로 채워
    미니 스트림 없이 일반 섹터만 쓴다.
    """
    sec = 512
    end, free, fatsect = 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFD
    data = {k: (v + b"\x00" * max(0, 4096 - len(v))) for k, v in streams.items()}
    # 디렉터리 항목 구성
    entries = [{"name": "Root Entry", "type": 5, "child": -1, "right": -1, "start": end, "size": 0}]
    storages: dict[str, int] = {}
    top: list[int] = []
    children: dict[int, list[int]] = {}
    for key in data:
        parts = key.split("/")
        if len(parts) == 2 and parts[0] not in storages:
            entries.append({"name": parts[0], "type": 1, "child": -1, "right": -1, "start": 0, "size": 0})
            storages[parts[0]] = len(entries) - 1
            top.append(len(entries) - 1)
        entries.append({"name": parts[-1], "type": 2, "child": -1, "right": -1, "key": key})
        idx = len(entries) - 1
        if len(parts) == 2:
            children.setdefault(storages[parts[0]], []).append(idx)
        else:
            top.append(idx)

    def chain(ids: list[int]) -> int:
        for a, b in zip(ids, ids[1:], strict=False):
            entries[a]["right"] = b
        return ids[0] if ids else -1

    entries[0]["child"] = chain(top)
    for s_idx, kids in children.items():
        entries[s_idx]["child"] = chain(kids)

    dir_sectors = math.ceil(len(entries) * 128 / sec)
    next_sector = 1 + dir_sectors  # 0번 = FAT
    fat = [fatsect] + [i + 2 if i + 1 < dir_sectors else end for i in range(dir_sectors)]
    # 디렉터리 체인 보정(1..dir_sectors)
    for i in range(dir_sectors):
        fat[1 + i] = 2 + i if i + 1 < dir_sectors else end
    body = b""
    for e in entries:
        if e["type"] != 2:
            continue
        blob = data[e["key"]]
        n = math.ceil(len(blob) / sec)
        e["start"], e["size"] = next_sector, len(blob)
        for i in range(n):
            fat.append(next_sector + i + 1 if i + 1 < n else end)
        next_sector += n
        body += blob + b"\x00" * (n * sec - len(blob))
    fat += [free] * (128 - len(fat) % 128 if len(fat) % 128 else 0)
    assert len(fat) == 128, "시험용 작성기는 FAT 섹터 1개까지만 지원"

    def dirent(e) -> bytes:
        name = e["name"].encode("utf-16-le") + b"\x00\x00"
        ent = name.ljust(64, b"\x00") + struct.pack("<HBB", len(name), e["type"], 1)
        ent += struct.pack("<iii", -1, e["right"], e["child"]) + b"\x00" * 16 + b"\x00" * 4 + b"\x00" * 16
        ent += struct.pack("<II", e.get("start", 0) if e["type"] != 1 else 0, e.get("size", 0)) + b"\x00" * 4
        return ent

    dir_bytes = b"".join(dirent(e) for e in entries).ljust(dir_sectors * sec, b"\x00")
    # 빈 디렉터리 칸은 '없음' 항목으로
    header = b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1" + b"\x00" * 16
    header += struct.pack("<HHHHH", 0x3E, 3, 0xFFFE, 9, 6) + b"\x00" * 6
    header += struct.pack("<IIIIIIIII", 0, 1, 1, 0, 4096, end, 0, end, 0)
    header += struct.pack("<I", 0) + struct.pack("<I", free) * 108
    assert len(header) == 512
    fat_bytes = struct.pack(f"<{len(fat)}I", *fat)
    return header + fat_bytes + dir_bytes + body


def make_hwp(path: Path, paragraphs: list[str], compressed: bool = True) -> None:
    file_header = b"HWP Document File".ljust(32, b"\x00") + struct.pack("<II", 0x05000300, 1 if compressed else 0)
    file_header = file_header.ljust(256, b"\x00")
    records = b""
    for p in paragraphs:
        records += _hwp_record(66, b"\x00" * 22)  # PARA_HEADER
        records += _hwp_record(67, (p + "\r").encode("utf-16-le"), 1)
    section = records
    if compressed:
        c = zlib.compressobj(9, zlib.DEFLATED, -15)
        section = c.compress(records) + c.flush()
    prv = ("\r\n".join(paragraphs))[:500].encode("utf-16-le")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(_cfb({"FileHeader": file_header, "BodyText/Section0": section, "PrvText": prv}))


def make_pdf(path: Path, lines: list[str]) -> None:
    """한국어 글자가 들어간 PDF(글꼴 없이 ToUnicode로 글자 정보만 담음)."""
    content = "BT /F1 18 Tf 50 750 Td 24 TL\n"
    for line in lines:
        hexs = "".join(f"{ord(ch):04X}" for ch in line)
        content += f"<{hexs}> Tj T*\n"
    content += "ET"
    cmap = (
        "/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CIDSystemInfo << /Registry (Adobe) "
        "/Ordering (UCS) /Supplement 0 >> def /CMapName /Adobe-Identity-UCS def /CMapType 2 def "
        "1 begincodespacerange <0000> <FFFF> endcodespacerange 1 beginbfrange <0000> <FFFF> <0000> endbfrange "
        "endcmap CMapName currentdict /CMap defineresource pop end end"
    )
    objs = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        f"<< /Length {len(content.encode())} >>\nstream\n{content}\nendstream",
        "<< /Type /Font /Subtype /Type0 /BaseFont /Malgun /Encoding /Identity-H /DescendantFonts [6 0 R] /ToUnicode 7 0 R >>",
        "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Malgun /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor 8 0 R >>",
        f"<< /Length {len(cmap)} >>\nstream\n{cmap}\nendstream",
        "<< /Type /FontDescriptor /FontName /Malgun /Flags 4 /FontBBox [0 0 1000 1000] /ItalicAngle 0 /Ascent 1000 /Descent 0 /CapHeight 1000 /StemV 80 >>",
    ]
    out = io.BytesIO()
    out.write(b"%PDF-1.4\n")
    offsets = []
    for i, o in enumerate(objs, 1):
        offsets.append(out.tell())
        out.write(f"{i} 0 obj\n{o}\nendobj\n".encode())
    xref = out.tell()
    out.write(f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode())
    for off in offsets:
        out.write(f"{off:010d} 00000 n \n".encode())
    out.write(f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode())
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(out.getvalue())


def make_record_files(d: Path) -> None:
    """일정(.ics)·연락처(.vcf)·구글 킵 테이크아웃(.zip) 예제."""
    import json

    d.mkdir(parents=True, exist_ok=True)
    (d / "구글캘린더.ics").write_text(
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"
        "BEGIN:VEVENT\r\nUID:ev1\r\nSUMMARY:[신제품] 기획 회의\r\nDTSTART:20240305T100000\r\nDTEND:20240305T113000\r\n"
        "LOCATION:본사 3층\r\nDESCRIPTION:김철수\\, 이영희와 출시 일정 논의\r\nEND:VEVENT\r\n"
        "BEGIN:VEVENT\r\nUID:ev2\r\nSUMMARY:할머니 생신\r\nDTSTART;VALUE=DATE:20230505\r\nEND:VEVENT\r\n"
        "BEGIN:VEVENT\r\nUID:ev3\r\nSUMMARY:《가을동화》 촬영\r\nDTSTART:20221010T090000Z\r\n"
        "DESCRIPTION:박감독\\, 이영희 출연\r\n END:VEVENT 아님 이어진 줄\r\nEND:VEVENT\r\n"
        "END:VCALENDAR\r\n", encoding="utf-8", newline="")
    (d / "연락처.vcf").write_text(
        "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:김철수\r\nTEL;TYPE=CELL:010-1234-5678\r\nX-RELATION:삼촌\r\nREV:2020-01-02T03:04:05Z\r\nEND:VCARD\r\n"
        "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:이영희\r\nTEL:010-2222-3333\r\nEMAIL:younghee@example.com\r\nCATEGORIES:회사\r\nEND:VCARD\r\n"
        "BEGIN:VCARD\r\nVERSION:2.1\r\nN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:=EB=B0=95;=EA=B0=90=EB=8F=85\r\nTEL:010-9999-0000\r\nEND:VCARD\r\n",
        encoding="utf-8", newline="")
    with zipfile.ZipFile(d / "takeout-keep.zip", "w") as z:
        z.writestr("Takeout/Keep/장보기.json", json.dumps({"title": "장보기", "listContent": [{"text": "우유", "isChecked": True}, {"text": "계란", "isChecked": False}],
                                                        "userEditedTimestampUsec": 1700000000000000, "labels": [{"name": "집안일"}]}, ensure_ascii=False))
        z.writestr("Takeout/Keep/아이디어.json", json.dumps({"title": "신제품 아이디어", "textContent": "김철수 의견: 색상을 더 밝게",
                                                         "createdTimestampUsec": 1709000000000000, "labels": [{"name": "신제품"}]}, ensure_ascii=False))
        z.writestr("Takeout/Keep/지운메모.json", json.dumps({"title": "지운 것", "textContent": "x", "isTrashed": True}))


# ---- 전체 샘플 ------------------------------------------------------------

def make_samples(dest: Path, with_real_video: bool = True) -> dict:
    dest = Path(dest)
    dest.mkdir(parents=True, exist_ok=True)
    today = dt.date.today()
    made: dict = {}
    photos = dest / "사진"
    _jpeg(photos / "2005" / "바닷가_아이들.jpg", (30, 120, 200), "2005:08:15 14:30:00", (38.2070, 128.5918))
    _jpeg(photos / "2005" / "생일잔치.jpg", (220, 120, 60), "2005:05:05 18:00:00", (37.5665, 126.9780))
    _jpeg(photos / "2018" / "IMG_0001.jpg", (60, 160, 90), "2018:10:03 11:00:00", (33.4996, 126.5312))
    years_ago = today.replace(year=today.year - 3)
    _jpeg(photos / "추억" / "3년전오늘.jpg", (200, 60, 120), years_ago.strftime("%Y:%m:%d 10:00:00"))
    _jpeg(photos / "추억" / "날짜없음.jpg", (90, 90, 90), None)
    from PIL import Image
    Image.new("RGB", (300, 200), (250, 230, 120)).save(photos / "스캔그림.png")
    # 같은 사진 두 장(중복)
    shutil.copy2(photos / "2005" / "바닷가_아이들.jpg", photos / "추억" / "바닷가_아이들(복사본).jpg")
    made["photos"] = 7

    videos = dest / "영상"
    real = with_real_video and real_mp4(videos / "2005_가족여행.mp4", "2005-08-16T09:00:00Z")
    if not real:
        synthetic_mp4(videos / "2005_가족여행.mp4", dt.datetime(2005, 8, 16, 9, 0), 4)
    synthetic_mp4(videos / "운동회.mp4", dt.datetime(2010, 10, 2, 10, 0), 95)
    speech_like_wav(dest / "소리" / "할머니_목소리.wav")
    made["real_video"] = real

    docs = dest / "회사서류"
    _hwpx(docs / "계약서_2023.hwpx", ["부동산 매매 계약서", "계약금은 금 오천만 원으로 한다.", "잔금은 2023년 12월 말일에 지급한다."])
    make_hwp(docs / "옛날_계약서.hwp", ["옛날 한글 문서입니다", "계약금 삼백만 원 영수함"])
    _docx(docs / "회의록.docx", ["2024년 3월 회의록", "참석자: 김철수, 이영희", "신제품 출시 일정을 논의했다."])
    _xlsx(docs / "정산표.xlsx", [["항목", "금액"], ["계약금", 3000000], ["중도금", 5000000]])
    make_pdf(docs / "안내문.pdf", ["건강검진 안내문", "검진 날짜는 4월 10일입니다"])
    (docs / "메모.txt").write_bytes("은행 비밀번호 바꾸기\n계약금 입금 확인".encode("cp949"))
    diary = dest / "일기장"
    _docx(diary / "2005-08-15 일기.docx", ["오늘은 속초 바닷가에 갔다.", "아이들이 모래성을 쌓으며 즐거워했다. 김철수 삼촌도 함께 왔다."])

    make_record_files(dest / "내기록")

    broken = dest / "깨진파일"
    broken.mkdir(parents=True, exist_ok=True)
    (broken / "망가진문서.docx").write_bytes(b"PK\x03\x04 this is not a real docx")
    (broken / "망가진사진.jpg").write_bytes(b"\xff\xd8\xff\xe0 broken jpeg")
    (broken / "망가진한글.hwp").write_bytes(b"not an ole file at all")
    (broken / "빈엑셀.xlsx").write_bytes(b"")
    special = dest / "특수문자 #폴더 (1) [사본]"
    special.mkdir(parents=True, exist_ok=True)
    (special / "이름에 & % ' 기호.txt").write_text("특수문자 파일 이름 시험", encoding="utf-8")
    deep = dest
    for i in range(12):
        deep = deep / f"아주긴폴더이름_{i:02d}_가나다라마바사"
    deep.mkdir(parents=True, exist_ok=True)
    (deep / "깊은곳의파일.txt").write_text("아주 깊은 폴더에 있는 파일", encoding="utf-8")
    excl = dest / "제외할폴더"
    excl.mkdir(parents=True, exist_ok=True)
    (excl / "보이면안됨.txt").write_text("제외 폴더 안의 파일", encoding="utf-8")
    made["dest"] = str(dest)
    return made


if __name__ == "__main__":
    import sys

    target = Path(sys.argv[1] if len(sys.argv) > 1 else "샘플폴더")
    if target.exists() and any(target.iterdir()):
        print("빈 폴더를 지정해 주세요:", target)
        raise SystemExit(1)
    print(make_samples(target))
    print("만든 위치:", os.path.abspath(target))
