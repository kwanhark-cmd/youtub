"""색인 검색. 원본은 열지 않고 색인만 조회하므로 100만 개 이상에서도 빠르다.

- 3글자 이상 낱말: 전문 검색(FTS5 trigram) 색인 사용
- 1~2글자 낱말: 이름 LIKE 검색(색인 범위 안에서)
- 페이지 나누기(page, page_size), 개수는 1만 개까지만 정확히 셈
"""

from __future__ import annotations

import sqlite3

from . import query as qp

COUNT_CAP = 10000
FILE_COLS = ("id, root_id, path, dir, name, ext, kind, size, mtime, taken_at, taken_year, taken_month,"
             " place, lat, lon, width, height, duration, content_status")


def _phrase(w: str) -> str:
    return '"' + w.replace('"', '""') + '"'


def _like(w: str) -> str:
    return "%" + w.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


def build_filters(p: dict) -> tuple[list[str], list]:
    where: list[str] = []
    args: list = []
    if p.get("kind"):
        where.append("f.kind=?")
        args.append(p["kind"])
    if p.get("exts"):
        where.append("f.ext IN (%s)" % ",".join("?" * len(p["exts"])))
        args.extend(p["exts"])
    if p.get("year"):
        if p.get("year_to"):
            where.append("f.taken_year BETWEEN ? AND ?")
            args.extend([p["year"], p["year_to"]])
        else:
            where.append("f.taken_year=?")
            args.append(p["year"])
    if p.get("month"):
        where.append("f.taken_month=?")
        args.append(p["month"])
    if p.get("day"):
        where.append("f.taken_day=?")
        args.append(p["day"])
    if p.get("date_from"):
        where.append("f.taken_at>=?")
        args.append(p["date_from"])
    if p.get("date_to"):
        where.append("f.taken_at<=?")
        args.append(p["date_to"] + "T23:59:59")
    if p.get("min_size") is not None:
        where.append("f.size>=?")
        args.append(int(p["min_size"]))
    if p.get("max_size") is not None:
        where.append("f.size<=?")
        args.append(int(p["max_size"]))
    if p.get("root_id"):
        where.append("f.root_id=?")
        args.append(int(p["root_id"]))
    if p.get("folder"):
        where.append("(f.dir=? OR f.dir LIKE ? ESCAPE '\\')")
        args.extend([p["folder"], p["folder"].rstrip("/\\").replace("%", "\\%").replace("_", "\\_") + "%"])
    if p.get("person"):
        where.append("f.id IN (SELECT fa.file_id FROM faces fa JOIN persons pe ON fa.person_id=pe.id WHERE pe.name=?)")
        args.append(p["person"])
    return where, args


def _word_clause(w: str) -> tuple[str, list]:
    """파일 이름·폴더·음성 메모에서 낱말 찾기."""
    note = "f.id IN (SELECT file_id FROM notes WHERE text LIKE ? ESCAPE '\\')"
    if len(w) >= 3:
        return (f"(f.id IN (SELECT rowid FROM names_fts WHERE names_fts MATCH ?) OR {note})",
                [_phrase(w), _like(w)])
    return (f"(f.name LIKE ? ESCAPE '\\' OR f.dir LIKE ? ESCAPE '\\' OR {note})", [_like(w), _like(w), _like(w)])


ORDERS = {
    "new": "f.taken_at DESC, f.id DESC",
    "old": "f.taken_at ASC, f.id ASC",
    "name": "f.name COLLATE NOCASE ASC",
    "size": "f.size DESC",
}


def _page(conn, base_sql: str, args: list, order: str, page: int, page_size: int) -> dict:
    page = max(1, int(page))
    page_size = max(1, min(int(page_size), 200))
    total = conn.execute(f"SELECT COUNT(*) FROM (SELECT 1 {base_sql} LIMIT {COUNT_CAP + 1})", args).fetchone()[0]
    rows = conn.execute(
        f"SELECT {FILE_COLS.replace('id,', 'f.id,', 1)} {base_sql} ORDER BY {order} LIMIT ? OFFSET ?",
        [*args, page_size, (page - 1) * page_size],
    ).fetchall()
    return {
        "total": min(total, COUNT_CAP), "more_than": total > COUNT_CAP, "page": page, "page_size": page_size,
        "items": [dict(r) for r in rows],
    }


def search_names(conn: sqlite3.Connection, p: dict, page: int = 1, page_size: int = 50, order: str = "new") -> dict:
    where, args = build_filters(p)
    for w in p.get("words") or []:
        c, a = _word_clause(w)
        where.append(c)
        args.extend(a)
    strict = list(where)
    strict_args = list(args)
    sql = "FROM files f" + (" WHERE " + " AND ".join(strict) if strict else "")
    res = _page(conn, sql, strict_args, ORDERS.get(order, ORDERS["new"]), page, page_size)
    res["notice"] = None
    # 장면 낱말(예: '아이들')이 이름에 없으면, 그 낱말은 빼고 다시 찾는다
    concepts = [w for w in (p.get("words") or []) if w in (p.get("concepts") or [])]
    if res["total"] == 0 and concepts:
        p2 = dict(p, words=[w for w in p["words"] if w not in concepts])
        res = search_names(conn, dict(p2, concepts=[]), page, page_size, order)
        res["notice"] = (f"'{' '.join(concepts)}'(이)라는 이름의 파일은 없어서, 나머지 조건으로 찾았어요. "
                         "설정에서 '장면 인식'을 켜면 사진 속 모습으로도 찾아요.")
    return res


def search_content(conn: sqlite3.Connection, p: dict, page: int = 1, page_size: int = 30) -> dict:
    words = [w for w in (p.get("words") or []) if w]
    if not words:
        return {"total": 0, "more_than": False, "page": 1, "page_size": page_size, "items": []}
    where, args = build_filters(dict(p, kind=p.get("kind") or None))
    long_words = [w for w in words if len(w) >= 3]
    short_words = [w for w in words if len(w) < 3]
    if long_words:
        where.append("f.id IN (SELECT rowid FROM content_fts WHERE content_fts MATCH ?)")
        args.append(" ".join(_phrase(w) for w in long_words))
    for w in short_words:
        where.append("f.id IN (SELECT rowid FROM content_fts WHERE body LIKE ? ESCAPE '\\')")
        args.append(_like(w))
    sql = "FROM files f" + " WHERE " + " AND ".join(where)
    res = _page(conn, sql, args, ORDERS["new"], page, page_size)
    first = words[0]
    for item in res["items"]:
        row = conn.execute(
            "SELECT substr(body, max(instr(body, ?) - 50, 1), 170) AS s, instr(body, ?) AS pos FROM content_fts WHERE rowid=?",
            (first, first, item["id"]),
        ).fetchone()
        if row and row["s"]:
            s = row["s"].replace("\n", " ").strip()
            item["snippet"] = ("…" if row["pos"] > 50 else "") + s + "…"
            item["highlight"] = words
    return res


def search_records(conn: sqlite3.Connection, words: list[str], limit: int = 20) -> list[dict]:
    if not words:
        return []
    where, args = [], []
    for w in words:
        if len(w) >= 3:
            where.append("r.id IN (SELECT rowid FROM records_fts WHERE records_fts MATCH ?)")
            args.append(_phrase(w))
        else:
            where.append("(r.title LIKE ? ESCAPE '\\' OR r.body LIKE ? ESCAPE '\\')")
            args.extend([_like(w), _like(w)])
    rows = conn.execute(
        f"SELECT id, kind, title, substr(body,1,200) AS body, at, source FROM records r WHERE {' AND '.join(where)}"
        " ORDER BY at DESC LIMIT ?", [*args, limit],
    ).fetchall()
    return [dict(r) for r in rows]


def search_contacts(conn: sqlite3.Connection, words: list[str], limit: int = 20) -> list[dict]:
    out = []
    for w in words:
        rows = conn.execute(
            "SELECT id, name, phones, relation, saved_at FROM contacts WHERE name LIKE ? ESCAPE '\\' LIMIT ?",
            (_like(w), limit),
        ).fetchall()
        out.extend(dict(r) for r in rows)
    return out


def search_all(conn: sqlite3.Connection, text: str, page: int = 1, page_size: int = 50, extra: dict | None = None,
               scene_search=None) -> dict:
    persons = [r[0] for r in conn.execute("SELECT name FROM persons WHERE name IS NOT NULL AND name<>''")]
    p = qp.parse(text, person_names=persons)
    if extra:
        p.update({k: v for k, v in extra.items() if v not in (None, "")})
    result: dict = {"query": p, "understood": qp.describe(p), "files": None, "content": None,
                    "records": [], "contacts": [], "scenes": None}
    if p["mode"] == "scene":
        result["scenes"] = scene_search(conn, p) if scene_search else {"items": [], "notice": "장면 인식이 꺼져 있어요"}
        return result
    if p["mode"] == "content":
        result["content"] = search_content(conn, p, page, page_size)
        return result
    result["files"] = search_names(conn, p, page, page_size, extra.get("order", "new") if extra else "new")
    if p.get("words") and p.get("kind") in (None, "doc"):
        result["content"] = search_content(conn, p, 1, 10)
    if p.get("words") and not p.get("kind") or p.get("diary"):
        result["records"] = search_records(conn, p["words"] or ["일기"])
        result["contacts"] = search_contacts(conn, p.get("words") or [])
    return result
