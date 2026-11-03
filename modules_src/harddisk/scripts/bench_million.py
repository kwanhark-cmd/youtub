"""100만 개 파일 색인에서 검색 속도 측정.

실행: python scripts/bench_million.py [개수]
가짜 파일 목록을 임시 색인에 넣고, 이름·필터·내용 검색과 페이지 넘김 시간을 잰다.
"""

import os
import random
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "engine"))
from hdbiseo import db, query, search  # noqa: E402

N = int(sys.argv[1]) if len(sys.argv) > 1 else 1_000_000
WORDS = ["가족", "여행", "계약서", "회의록", "바닷가", "생일", "졸업식", "IMG", "DSC", "보고서", "견적서", "일기", "사진", "운동회", "결혼식"]
EXTS = [("jpg", "image")] * 6 + [("mp4", "video")] * 2 + [("hwp", "doc"), ("xlsx", "doc"), ("docx", "doc"), ("pdf", "doc"), ("mp3", "audio")]

tmp = Path(tempfile.mkdtemp())
conn = db.connect(tmp / "bench.db")
db.init(conn)
rnd = random.Random(1)
t0 = time.time()
batch_f, batch_n, batch_c = [], [], []
for i in range(1, N + 1):
    ext, kind = rnd.choice(EXTS)
    y = rnd.randint(1998, 2025)
    m = rnd.randint(1, 12)
    d = f"D:\\사진\\{y}\\{rnd.choice(WORDS)}_{rnd.randint(1, 500)}"
    name = f"{rnd.choice(WORDS)}_{i}.{ext}"
    batch_f.append((i, 1, d + "\\" + name, d, name, ext, kind, rnd.randint(1000, 50_000_000), 0.0,
                    f"{y}-{m:02d}-{rnd.randint(1, 28):02d}T12:00:00", y, m, rnd.randint(1, 28), "done"))
    batch_n.append((i, name, d))
    if kind == "doc" and i % 4 == 0:
        batch_c.append((i, " ".join(rnd.choice(WORDS) for _ in range(60)) + (" 계약금 오천만원" if i % 97 == 0 else "")))
    if len(batch_f) >= 50_000:
        conn.executemany("INSERT INTO files(id,root_id,path,dir,name,ext,kind,size,mtime,taken_at,taken_year,taken_month,taken_day,detail_status)"
                         " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)", batch_f)
        conn.executemany("INSERT INTO names_fts(rowid,name,dir) VALUES(?,?,?)", batch_n)
        conn.executemany("INSERT INTO content_fts(rowid,body) VALUES(?,?)", batch_c)
        conn.commit()
        batch_f, batch_n, batch_c = [], [], []
if batch_f:
    conn.executemany("INSERT INTO files(id,root_id,path,dir,name,ext,kind,size,mtime,taken_at,taken_year,taken_month,taken_day,detail_status)"
                     " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)", batch_f)
    conn.executemany("INSERT INTO names_fts(rowid,name,dir) VALUES(?,?,?)", batch_n)
    conn.executemany("INSERT INTO content_fts(rowid,body) VALUES(?,?)", batch_c)
    conn.commit()
build = time.time() - t0
conn.execute("ANALYZE")


def timed(label, fn, repeat=3):
    best = 1e9
    res = None
    for _ in range(repeat):
        t = time.time()
        res = fn()
        best = min(best, time.time() - t)
    total = res["total"] if isinstance(res, dict) else len(res)
    print(f"{label:<40} {best * 1000:8.1f} ms   결과 {total}")
    return best


print(f"색인 {N:,}개 넣기: {build:.1f}초, DB 크기 {os.path.getsize(tmp / 'bench.db') / 1e9:.2f} GB")
times = [
    timed("이름 검색 '계약서'(3글자)", lambda: search.search_names(conn, query.parse("계약서"))),
    timed("이름 검색 '일기'(2글자)", lambda: search.search_names(conn, query.parse("일기"))),
    timed("이름 검색 + 2005년 + 사진", lambda: search.search_names(conn, query.parse("2005년 바닷가 사진"))),
    timed("말 검색 '2005년 아이들 영상 찾아줘'", lambda: search.search_all(conn, "2005년 아이들 영상 찾아줘")["files"]),
    timed("내용 검색 '계약금'", lambda: search.search_content(conn, query.parse("계약금 들어간 문서"))),
    timed("종류·크기 필터(100MB 이상 영상)", lambda: search.search_names(conn, {"kind": "video", "min_size": 40_000_000})),
    timed("100번째 쪽 넘기기", lambda: search.search_names(conn, {"kind": "image"}, page=100)),
]
print(f"가장 느린 검색: {max(times) * 1000:.0f} ms")
