"""사진·영상 날짜별 보기, N년 전 오늘, 장소별 보기."""

from __future__ import annotations

import datetime as dt
import sqlite3

from .search import FILE_COLS

MEDIA = "kind IN ('image','video')"


def years(conn: sqlite3.Connection, kind: str | None = None) -> list[dict]:
    cond = "kind=?" if kind else MEDIA
    args = [kind] if kind else []
    rows = conn.execute(
        f"SELECT taken_year AS year, COUNT(*) AS n, SUM(kind='video') AS videos FROM files WHERE {cond}"
        " AND taken_year IS NOT NULL GROUP BY taken_year ORDER BY taken_year DESC", args,
    ).fetchall()
    return [dict(r) for r in rows]


def months(conn: sqlite3.Connection, year: int, kind: str | None = None) -> list[dict]:
    cond = "kind=?" if kind else MEDIA
    args = [kind] if kind else []
    rows = conn.execute(
        f"SELECT taken_month AS month, COUNT(*) AS n FROM files WHERE {cond} AND taken_year=?"
        " GROUP BY taken_month ORDER BY taken_month", [*args, year],
    ).fetchall()
    out = []
    for r in rows:
        d = dict(r)
        cover = conn.execute(
            f"SELECT id FROM files WHERE {cond} AND taken_year=? AND taken_month=? AND kind='image' ORDER BY taken_at LIMIT 1",
            [*args, year, r["month"]],
        ).fetchone()
        d["cover_id"] = cover[0] if cover else None
        out.append(d)
    return out


def items(conn, year: int | None, month: int | None, kind: str | None, page: int = 1, page_size: int = 60,
          place: str | None = None) -> dict:
    where = ["kind=?" if kind else MEDIA]
    args: list = [kind] if kind else []
    if year:
        where.append("taken_year=?")
        args.append(year)
    if month:
        where.append("taken_month=?")
        args.append(month)
    if place:
        where.append("place=?")
        args.append(place)
    page_size = max(1, min(page_size, 200))
    total = conn.execute(f"SELECT COUNT(*) FROM files WHERE {' AND '.join(where)}", args).fetchone()[0]
    rows = conn.execute(
        f"SELECT {FILE_COLS} FROM files WHERE {' AND '.join(where)} ORDER BY taken_at, id LIMIT ? OFFSET ?",
        [*args, page_size, (max(1, page) - 1) * page_size],
    ).fetchall()
    return {"total": total, "page": page, "page_size": page_size, "items": [dict(r) for r in rows]}


def memories(conn, today: dt.date | None = None, window_days: int = 0) -> list[dict]:
    """'N년 전 오늘' — 같은 월·일에 찍은 사진·영상을 해마다 묶는다."""
    today = today or dt.date.today()
    out = []
    days = [today + dt.timedelta(days=d) for d in range(-window_days, window_days + 1)]
    for d in days:
        rows = conn.execute(
            f"SELECT {FILE_COLS} FROM files WHERE {MEDIA} AND taken_month=? AND taken_day=? AND taken_year<?"
            " ORDER BY taken_year DESC, taken_at LIMIT 200",
            (d.month, d.day, today.year),
        ).fetchall()
        by_year: dict[int, list] = {}
        for r in rows:
            by_year.setdefault(r["taken_year"], []).append(dict(r))
        for y, its in by_year.items():
            out.append({"years_ago": today.year - y, "year": y, "items": its,
                        "title": f"{today.year - y}년 전 오늘", "speech": f"{today.year - y}년 전 오늘, {y}년의 추억이 {len(its)}개 있어요."})
    out.sort(key=lambda m: m["years_ago"])
    return out


def places(conn) -> list[dict]:
    rows = conn.execute(
        f"SELECT place, COUNT(*) AS n, AVG(lat) AS lat, AVG(lon) AS lon, MIN(taken_year) AS y1, MAX(taken_year) AS y2,"
        f" (SELECT id FROM files f2 WHERE f2.place=files.place AND f2.kind='image' LIMIT 1) AS cover_id"
        f" FROM files WHERE {MEDIA} AND place IS NOT NULL GROUP BY place ORDER BY n DESC"
    ).fetchall()
    return [dict(r) for r in rows]


def overview(conn) -> dict:
    row = conn.execute(
        "SELECT COUNT(*) AS total, SUM(kind='image') AS images, SUM(kind='video') AS videos, SUM(kind='doc') AS docs,"
        " SUM(kind='audio') AS audios, COALESCE(SUM(size),0) AS bytes FROM files"
    ).fetchone()
    d = dict(row)
    d["unreadable"] = conn.execute("SELECT COUNT(*) FROM unreadable").fetchone()[0]
    d["content_ok"] = conn.execute("SELECT COUNT(*) FROM files WHERE content_status='ok'").fetchone()[0]
    return {k: (v or 0) for k, v in d.items()}
