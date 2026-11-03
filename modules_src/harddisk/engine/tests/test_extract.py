import zlib

import pytest

from hdbiseo import extract, samples


def test_all_document_kinds(sample_dir):
    docs = sample_dir / "회사서류"
    expect = {
        "계약서_2023.hwpx": "오천만",
        "옛날_계약서.hwp": "삼백만",
        "회의록.docx": "김철수",
        "정산표.xlsx": "중도금",
        "안내문.pdf": "건강검진",
        "메모.txt": "비밀번호",
    }
    for name, word in expect.items():
        f = docs / name
        assert word in extract.extract_text(str(f), f.suffix[1:]), name


def test_broken_files_raise_korean_error(sample_dir):
    for name in ["망가진문서.docx", "망가진한글.hwp", "빈엑셀.xlsx"]:
        f = sample_dir / "깨진파일" / name
        with pytest.raises(extract.ExtractError) as e:
            extract.extract_text(str(f), f.suffix[1:])
        assert any("가" <= ch <= "힣" for ch in str(e.value))


def test_hwp_uncompressed_and_controls(tmp_path):
    p = tmp_path / "a.hwp"
    samples.make_hwp(p, ["압축 안 한 문서"], compressed=False)
    assert "압축 안 한" in extract.read_hwp(str(p))
    # 확장 컨트롤(8글자)은 건너뛰어야 한다
    body = "앞".encode("utf-16-le") + b"\x0b\x00" + b"\x00" * 14 + "뒤".encode("utf-16-le")
    rec = samples._hwp_record(67, body)
    assert extract.parse_hwp_records(rec) == "앞뒤"


def test_hwp_long_record():
    text = "가" * 3000
    rec = samples._hwp_record(67, text.encode("utf-16-le"))
    assert extract.parse_hwp_records(rec) == text
    assert zlib  # 사용 확인


def test_cp949_text(tmp_path):
    p = tmp_path / "x.txt"
    p.write_bytes("한국어 시험".encode("cp949"))
    assert extract.read_text_file(str(p)) == "한국어 시험"


def test_unknown_kind():
    with pytest.raises(extract.ExtractError):
        extract.extract_text("nothing.xyz", "xyz")
