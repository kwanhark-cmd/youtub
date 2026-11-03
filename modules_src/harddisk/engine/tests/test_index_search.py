import os
import shutil
import time

from hdbiseo import query, search


def names(res):
    return [i["name"] for i in res["items"]]


def test_index_counts_and_exclusion(indexed):
    c = indexed.conn()
    total = c.execute("SELECT COUNT(*) FROM files").fetchone()[0]
    assert total >= 20
    assert c.execute("SELECT COUNT(*) FROM files WHERE name='보이면안됨.txt'").fetchone()[0] == 0
    root = indexed.roots()[0]
    assert root["status"] == "done" and root["files_count"] == total


def test_name_search_long_and_short(indexed):
    c = indexed.conn()
    r = search.search_names(c, query.parse("계약서"))
    assert set(names(r)) >= {"계약서_2023.hwpx", "옛날_계약서.hwp"}
    r = search.search_names(c, query.parse("회의"))  # 2글자
    assert "회의록.docx" in names(r)
    r = search.search_names(c, {"words": ["기호"]})
    assert any("기호" in n for n in names(r))


def test_filters_kind_year_size_folder(indexed, sample_dir):
    c = indexed.conn()
    r = search.search_names(c, {"kind": "image", "year": 2005})
    assert set(names(r)) >= {"바닷가_아이들.jpg", "생일잔치.jpg"}
    r = search.search_names(c, {"kind": "doc", "exts": ["hwp", "hwpx"]})
    assert all(n.endswith(("hwp", "hwpx")) for n in names(r)) and len(names(r)) >= 3
    r = search.search_names(c, {"min_size": 10_000_000})
    assert r["total"] == 0
    r = search.search_names(c, {"folder": str(sample_dir / "회사서류")})
    assert r["total"] == 6


def test_content_search_with_snippet(indexed):
    c = indexed.conn()
    r = search.search_content(c, query.parse("계약금 들어간 문서 찾아줘"))
    got = set(names(r))
    assert {"계약서_2023.hwpx", "옛날_계약서.hwp", "정산표.xlsx", "메모.txt"} <= got
    item = next(i for i in r["items"] if i["name"] == "계약서_2023.hwpx")
    assert "계약금" in item["snippet"]


def test_voice_style_query(indexed):
    c = indexed.conn()
    res = search.search_all(c, "2005년 아이들 영상 찾아줘")
    assert res["query"]["year"] == 2005 and res["query"]["kind"] == "video"
    assert "2005_가족여행.mp4" in names(res["files"])


def test_unreadable_list(indexed):
    c = indexed.conn()
    rows = {r["path"].split(os.sep)[-1]: r["reason"] for r in c.execute("SELECT * FROM unreadable")}
    assert "망가진문서.docx" in rows and "망가진사진.jpg" in rows and "망가진한글.hwp" in rows
    assert all(any("가" <= ch <= "힣" for ch in v) for v in rows.values())


def test_deep_path_and_special_chars(indexed):
    c = indexed.conn()
    assert c.execute("SELECT COUNT(*) FROM files WHERE name='깊은곳의파일.txt'").fetchone()[0] == 1
    assert c.execute("SELECT COUNT(*) FROM files WHERE name LIKE '이름에 &%'").fetchone()[0] == 1


def test_photo_details(indexed):
    c = indexed.conn()
    r = c.execute("SELECT * FROM files WHERE name='바닷가_아이들.jpg'").fetchone()
    assert r["taken_at"].startswith("2005-08-15") and r["place"] == "속초"


def test_incremental_update(indexed, sample_dir, tmp_path):
    work = tmp_path / "work"
    shutil.copytree(sample_dir / "회사서류", work)
    eng = indexed
    eng.add_root(str(work))
    eng.indexer.start()
    eng.indexer.join(60)
    c = eng.conn()
    before = c.execute("SELECT id, indexed_at FROM files WHERE name='회의록.docx' AND dir=?", (str(work),)).fetchone()
    (work / "새파일.txt").write_text("새로 생긴 파일 내용 증분", encoding="utf-8")
    (work / "메모.txt").unlink()  # 시험용 복사본에서만 삭제
    time.sleep(1.1)
    eng.indexer.start()
    eng.indexer.join(60)
    after = c.execute("SELECT id, indexed_at FROM files WHERE name='회의록.docx' AND dir=?", (str(work),)).fetchone()
    assert before["indexed_at"] == after["indexed_at"]  # 바뀌지 않은 파일은 다시 분석 안 함
    assert c.execute("SELECT COUNT(*) FROM files WHERE dir=? AND name='새파일.txt'", (str(work),)).fetchone()[0] == 1
    assert c.execute("SELECT COUNT(*) FROM files WHERE dir=? AND name='메모.txt'", (str(work),)).fetchone()[0] == 0
    r = search.search_content(c, {"words": ["증분"]})
    assert "새파일.txt" in names(r)


def test_originals_untouched(sample_dir, engine):
    before = {}
    for dp, _dn, fn in os.walk(sample_dir):
        for f in fn:
            p = os.path.join(dp, f)
            st = os.stat(p)
            before[p] = (st.st_size, st.st_mtime)
    engine.add_root(str(sample_dir))
    engine.indexer.start()
    engine.indexer.join(120)
    after = {}
    for dp, _dn, fn in os.walk(sample_dir):
        for f in fn:
            p = os.path.join(dp, f)
            st = os.stat(p)
            after[p] = (st.st_size, st.st_mtime)
    assert before == after


def test_particles():
    assert query.strip_particle("바닷가") == "바닷가"
    assert query.strip_particle("계약금이") == "계약금"
    assert query.strip_particle("사진을") == "사진"
    assert query.strip_particle("아이들") == "아이들"
    p = query.parse("계약금이 들어간 한글 문서 보여줘")
    assert p["mode"] == "content" and p["words"] == ["계약금"] and p["exts"] == ["hwp", "hwpx"]
    p = query.parse("작년 3월 바닷가 사진")
    assert p["kind"] == "image" and p["month"] == 3 and "바닷가" in p["words"]
