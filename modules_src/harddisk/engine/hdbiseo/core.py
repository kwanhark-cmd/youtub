"""사용자(가족 구성원)별 엔진 묶음: 색인 DB, 색인 작업, 설정."""

from __future__ import annotations

import json
import os
import threading
from pathlib import Path

from . import db as dbm
from . import settings as st
from .indexer import Indexer, norm


class UserEngine:
    def __init__(self, user_id: str):
        self.user_id = user_id
        self.dir = st.user_dir(user_id)
        self.db_path = self.dir / "index.db"
        self.thumbs = self.dir / "thumbs"
        conn = self.connect()
        dbm.init(conn)
        conn.close()
        from . import recognize  # 순환 참조 방지

        self.recognizer = recognize.Recognizer(self)
        self.indexer = Indexer(self.db_path, self.settings, extra_phases=self.recognizer.phases())
        self._local = threading.local()
        self._all_conns: list = []
        self._conn_lock = threading.Lock()

    def settings(self) -> dict:
        return st.load(self.user_id)

    def connect(self):
        return dbm.connect(self.db_path)

    def conn(self):
        """요청을 처리하는 스레드마다 연결 하나씩."""
        c = getattr(self._local, "conn", None)
        if c is None:
            c = self.connect()
            self._local.conn = c
            with self._conn_lock:
                self._all_conns.append(c)
        return c

    def close_all(self) -> None:
        """복원·초기화 전에 모든 연결을 닫는다."""
        self.indexer.stop()
        with self._conn_lock:
            for c in self._all_conns:
                try:
                    c.close()
                except Exception:  # 이미 닫힘
                    pass
            self._all_conns.clear()
        self._local = threading.local()

    # ---- 분석할 하드·폴더 ------------------------------------------------
    def add_root(self, path: str, label: str | None = None, excluded: list[str] | None = None) -> dict:
        p = os.path.abspath(path)
        if not os.path.isdir(p):
            raise ValueError("폴더를 찾을 수 없어요. 하드디스크가 연결되어 있는지 확인해 주세요.")
        c = self.conn()
        for r in c.execute("SELECT id, path FROM roots"):
            a, b = norm(r["path"]), norm(p)
            if a == b:
                raise ValueError("이미 추가된 폴더예요.")
            if b.startswith(a.rstrip(os.sep) + os.sep):
                raise ValueError("이미 추가된 폴더 안에 있는 폴더예요.")
        sample = norm(str(sample_dir()))
        if norm(p) != sample:  # 실제 폴더를 고르면 체험용 예제 폴더는 자동으로 숨김(목록에서만 뺌)
            for r in c.execute("SELECT id, path FROM roots").fetchall():
                if norm(r["path"]) == sample:
                    self.remove_root(r["id"])
        ex = [os.path.abspath(x) for x in (excluded or [])]
        cur = c.execute(
            "INSERT INTO roots(path,label,excluded) VALUES(?,?,?)",
            (p, label or os.path.basename(p.rstrip(os.sep)) or p, json.dumps(ex, ensure_ascii=False)),
        )
        c.commit()
        return dict(c.execute("SELECT * FROM roots WHERE id=?", (cur.lastrowid,)).fetchone())

    def update_root(self, root_id: int, excluded: list[str] | None = None, enabled: bool | None = None,
                    label: str | None = None) -> None:
        c = self.conn()
        if excluded is not None:
            c.execute("UPDATE roots SET excluded=? WHERE id=?",
                      (json.dumps([os.path.abspath(x) for x in excluded], ensure_ascii=False), root_id))
        if enabled is not None:
            c.execute("UPDATE roots SET enabled=? WHERE id=?", (1 if enabled else 0, root_id))
        if label:
            c.execute("UPDATE roots SET label=? WHERE id=?", (label[:40], root_id))
        c.commit()

    def remove_root(self, root_id: int) -> None:
        """분석 목록에서만 뺀다(하드디스크의 파일은 그대로)."""
        c = self.conn()
        ids = [r[0] for r in c.execute("SELECT id FROM files WHERE root_id=?", (root_id,))]
        for i in range(0, len(ids), 500):
            ch = ids[i:i + 500]
            q = ",".join("?" * len(ch))
            c.execute(f"DELETE FROM names_fts WHERE rowid IN ({q})", ch)
            c.execute(f"DELETE FROM content_fts WHERE rowid IN ({q})", ch)
        c.execute("DELETE FROM files WHERE root_id=?", (root_id,))
        c.execute("DELETE FROM roots WHERE id=?", (root_id,))
        c.commit()

    def roots(self) -> list[dict]:
        out = []
        for r in self.conn().execute("SELECT * FROM roots ORDER BY id"):
            d = dict(r)
            d["excluded"] = json.loads(d["excluded"] or "[]")
            d["connected"] = os.path.isdir(d["path"])
            d["sample"] = is_sample(d["path"])
            if not d["connected"]:
                d["status"] = "disconnected"
            out.append(d)
        return out


def sample_dir() -> Path:
    return st.app_home() / "체험용_예제폴더"


def is_sample(path: str) -> bool:
    return norm(path) == norm(str(sample_dir()))


_engines: dict[str, UserEngine] = {}
_lock = threading.Lock()


def get_engine(user_id: str = "default") -> UserEngine:
    with _lock:
        if user_id not in _engines:
            _engines[user_id] = UserEngine(user_id)
        return _engines[user_id]


def reset_engines() -> None:
    with _lock:
        for e in _engines.values():
            e.indexer.stop()
        _engines.clear()
