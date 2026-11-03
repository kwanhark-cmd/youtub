"""중복 파일 찾기: 크기로 먼저 거르고, 같은 크기끼리 앞부분 → 전체 해시를 비교한다.

자동 삭제는 하지 않는다. 사용자가 고른 파일만 '휴지통으로 이동'할 수 있다.
"""

from __future__ import annotations

import hashlib
import sqlite3
import threading

from .indexer import os_path

CHUNK = 1024 * 1024


def _hash(path: str, limit: int | None = None) -> str:
    h = hashlib.blake2b(digest_size=20)
    read = 0
    with open(os_path(path), "rb") as f:
        while True:
            want = CHUNK if limit is None else min(CHUNK, limit - read)
            if want <= 0:
                break
            b = f.read(want)
            if not b:
                break
            h.update(b)
            read += len(b)
    return h.hexdigest()


class DupeFinder:
    def __init__(self, engine):
        self.engine = engine
        self.state = {"running": False, "done": 0, "total": 0, "message": "", "groups": 0}
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()

    def start(self, min_size: int = 1) -> bool:
        if self._thread and self._thread.is_alive():
            return False
        self._stop.clear()
        self._thread = threading.Thread(target=self._run, args=(min_size,), daemon=True)
        self._thread.start()
        return True

    def stop(self):
        self._stop.set()

    def join(self, t=None):
        if self._thread:
            self._thread.join(t)

    def _run(self, min_size: int):
        conn = self.engine.connect()
        self.state.update(running=True, done=0, message="같은 크기의 파일을 고르는 중")
        try:
            cands = conn.execute(
                "SELECT id, path, size FROM files WHERE size>=? AND size IN "
                "(SELECT size FROM files WHERE size>=? GROUP BY size HAVING COUNT(*)>1) AND hash IS NULL ORDER BY size DESC",
                (min_size, min_size),
            ).fetchall()
            self.state["total"] = len(cands)
            self.state["message"] = "파일을 비교하는 중"
            by_size: dict[int, list] = {}
            for r in cands:
                by_size.setdefault(r["size"], []).append(r)
            for size, group in by_size.items():
                # 1차: 앞 64KB만 비교(빠름)
                quick: dict[str, list] = {}
                for r in group:
                    if self._stop.is_set():
                        return
                    try:
                        quick.setdefault(_hash(r["path"], 65536), []).append(r)
                    except OSError:
                        pass
                    self.state["done"] += 1
                for same in quick.values():
                    if len(same) < 2:
                        continue
                    for r in same:
                        try:
                            full = _hash(r["path"]) if size > 65536 else _hash(r["path"], 65536)
                        except OSError:
                            continue
                        conn.execute("UPDATE files SET hash=? WHERE id=?", (full, r["id"]))
                conn.commit()
            self.state["groups"] = len(groups(conn, 1, 1000000)["items"])
            self.state["message"] = "다 찾았어요"
        finally:
            self.state["running"] = False
            conn.close()


def groups(conn: sqlite3.Connection, page: int = 1, page_size: int = 20) -> dict:
    rows = conn.execute(
        "SELECT hash, size, COUNT(*) AS n FROM files WHERE hash IS NOT NULL GROUP BY hash HAVING COUNT(*)>1"
        " ORDER BY size*COUNT(*) DESC LIMIT ? OFFSET ?",
        (page_size, (page - 1) * page_size),
    ).fetchall()
    total = conn.execute(
        "SELECT COUNT(*), COALESCE(SUM(s),0) FROM (SELECT size*(COUNT(*)-1) AS s FROM files WHERE hash IS NOT NULL"
        " GROUP BY hash HAVING COUNT(*)>1)"
    ).fetchone()
    out = []
    for g in rows:
        files = conn.execute(
            "SELECT id, name, path, dir, kind, size, taken_at, mtime FROM files WHERE hash=? ORDER BY mtime", (g["hash"],)
        ).fetchall()
        out.append({"hash": g["hash"], "size": g["size"], "count": g["n"], "files": [dict(f) for f in files]})
    return {"total": total[0], "saving_bytes": total[1], "page": page, "items": out}
