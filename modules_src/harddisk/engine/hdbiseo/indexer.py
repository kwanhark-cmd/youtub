"""색인 작업(목록 만들기). 원본 파일은 읽기만 한다.

1) 목록 단계: 폴더를 순서대로 훑어 이름·크기·날짜를 저장 (이름 검색이 바로 가능)
2) 자세히 단계: 사진·영상 촬영 정보, 문서 안의 글자
3) 추가 단계: 얼굴·장면(모델이 있을 때만)

- 폴더 하나를 마칠 때마다 저장 → 중간에 꺼져도 이어서
- 크기·수정 시각이 같으면 다시 분석하지 않음(증분)
- 하드가 분리되면 '연결 끊김'으로 표시하고 다시 연결되면 이어서
- 읽을 수 없는 파일·폴더는 목록에 남기고 계속
"""

from __future__ import annotations

import datetime as dt
import json
import logging
import os
import shutil
import sqlite3
import threading
import time
from pathlib import Path
from typing import Callable

from . import db as dbm
from . import extract, media
from .kinds import kind_of

log = logging.getLogger("hdbiseo.indexer")

SKIP_DIR_NAMES = {"$recycle.bin", "system volume information", ".trashes", ".trash", "$windows.~bt", "$windows.~ws"}


class Disconnected(Exception):
    pass


def os_path(p: str) -> str:
    """윈도우의 아주 긴 경로(260자 이상)도 읽을 수 있게 바꾼다."""
    if os.name == "nt" and len(p) >= 240 and not p.startswith("\\\\?\\"):
        return "\\\\?\\" + os.path.abspath(p)
    return p


def norm(p: str) -> str:
    p = os.path.normpath(p)
    return p.casefold() if os.name == "nt" else p


def in_night_window(now: dt.datetime, start: str, end: str) -> bool:
    def mins(s: str) -> int:
        h, m = s.split(":")
        return int(h) * 60 + int(m)

    cur = now.hour * 60 + now.minute
    a, b = mins(start), mins(end)
    if a == b:
        return True
    if a < b:
        return a <= cur < b
    return cur >= a or cur < b


def safe_text(s: str) -> str:
    """파일 이름에 깨진 글자(인코딩 오류)가 있어도 저장할 수 있게."""
    return s.encode("utf-8", "surrogateescape").decode("utf-8", "replace")


class Indexer:
    def __init__(self, db_path: Path, get_settings: Callable[[], dict], extra_phases: list | None = None):
        self.db_path = db_path
        self.get_settings = get_settings
        self.extra_phases = extra_phases or []
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()
        self._pause = threading.Event()
        self._lock = threading.Lock()
        self.state: dict = self._idle_state()
        self.sleep = time.sleep  # 테스트에서 바꿀 수 있게
        self.reconnect_wait = 15.0

    @staticmethod
    def _idle_state() -> dict:
        return {
            "running": False, "paused": False, "phase": "idle", "message": "쉬는 중",
            "root_id": None, "folder": "", "files_seen": 0, "dirs_done": 0,
            "bytes_seen": 0, "percent": 0, "detail_total": 0, "detail_done": 0,
            "started_at": None, "errors": 0, "waiting": None,
        }

    # ---- 제어 ---------------------------------------------------------
    def start(self, root_ids: list[int] | None = None) -> bool:
        with self._lock:
            if self._thread and self._thread.is_alive():
                self._pause.clear()
                return False
            self._stop.clear()
            self._pause.clear()
            self.state = self._idle_state()
            self.state.update(running=True, phase="start", message="준비 중", started_at=dbm.now_iso())
            self._thread = threading.Thread(target=self._run_safe, args=(root_ids,), daemon=True, name="indexer")
            self._thread.start()
            return True

    def pause(self) -> None:
        self._pause.set()
        self.state["paused"] = True
        self.state["message"] = "잠시 멈춤"

    def resume(self) -> None:
        self._pause.clear()
        self.state["paused"] = False

    def stop(self, wait: bool = True) -> None:
        self._stop.set()
        self._pause.clear()
        if wait and self._thread:
            self._thread.join(timeout=30)

    def is_running(self) -> bool:
        return bool(self._thread and self._thread.is_alive())

    def join(self, timeout: float | None = None) -> None:
        if self._thread:
            self._thread.join(timeout)

    # ---- 내부 ---------------------------------------------------------
    def _checkpoint(self) -> None:
        """멈춤·중단·밤 시간 조건을 확인한다."""
        while True:
            if self._stop.is_set():
                raise _Stopped()
            if self._pause.is_set():
                self.state["waiting"] = "paused"
                self.sleep(0.5)
                continue
            s = self.get_settings()
            if s.get("night_only") and not in_night_window(dt.datetime.now(), s["night_start"], s["night_end"]):
                self.state["waiting"] = "night"
                self.state["message"] = f"밤 시간({s['night_start']}~{s['night_end']})을 기다리는 중"
                self.sleep(5)
                continue
            self.state["waiting"] = None
            return

    def _run_safe(self, root_ids):
        conn = dbm.connect(self.db_path)
        try:
            self._run(conn, root_ids)
            self.state.update(phase="done", message="색인을 모두 마쳤어요", percent=100)
        except _Stopped:
            self.state.update(phase="stopped", message="멈췄어요. 다음에 이어서 할 수 있어요")
        except Exception:  # 엔진 전체가 죽지 않도록
            log.exception("색인 중 예상 못 한 오류")
            self.state.update(phase="error", message="문제가 생겨 멈췄어요. 다시 시작하면 이어서 해요")
        finally:
            self.state["running"] = False
            conn.close()

    def _roots(self, conn, root_ids):
        rows = conn.execute("SELECT * FROM roots WHERE enabled=1 ORDER BY id").fetchall()
        return [r for r in rows if root_ids is None or r["id"] in root_ids]

    def _run(self, conn: sqlite3.Connection, root_ids):
        pending = [r["id"] for r in self._roots(conn, root_ids)]
        while pending:
            disconnected = []
            for rid in pending:
                root = conn.execute("SELECT * FROM roots WHERE id=?", (rid,)).fetchone()
                if root is None:
                    continue
                try:
                    self._scan_root(conn, root)
                    self._details(conn, rid)
                    for phase in self.extra_phases:
                        self._checkpoint()
                        phase(conn, rid, self)
                except Disconnected:
                    conn.commit()
                    conn.execute("UPDATE roots SET status='disconnected' WHERE id=?", (rid,))
                    conn.commit()
                    disconnected.append(rid)
            pending = disconnected
            if pending:
                self.state.update(phase="disconnected", message="하드디스크 연결이 끊겼어요. 다시 연결하면 이어서 해요")
                waited = 0.0
                while waited < self.reconnect_wait:
                    self._checkpoint()
                    self.sleep(1)
                    waited += 1

    # ---- 1) 목록 단계 -------------------------------------------------
    def _scan_root(self, conn: sqlite3.Connection, root) -> None:
        rid, rpath = root["id"], root["path"]
        if not os.path.isdir(os_path(rpath)):
            raise Disconnected()
        gen = root["scanning_generation"]
        if gen <= root["generation"]:
            gen = root["generation"] + 1
            conn.execute("DELETE FROM scan_dirs WHERE root_id=?", (rid,))
            conn.execute(
                "UPDATE roots SET scanning_generation=?, last_scan_started=? WHERE id=?",
                (gen, dbm.now_iso(), rid),
            )
        conn.execute("UPDATE roots SET status='scanning' WHERE id=?", (rid,))
        conn.commit()
        excluded = [norm(x) for x in json.loads(root["excluded"] or "[]")]
        done_dirs = {r[0] for r in conn.execute("SELECT path FROM scan_dirs WHERE root_id=? AND generation=?", (rid, gen))}
        try:
            used = shutil.disk_usage(os_path(rpath)).used or 1
        except OSError:
            used = 1
        self.state.update(phase="list", root_id=rid, message="파일 목록을 만드는 중")

        stack = [rpath]
        while stack:
            d = stack.pop()
            self._checkpoint()
            self.state["folder"] = os.path.basename(d) or d
            subdirs, files = self._list_dir(conn, rid, rpath, d)
            for sd in sorted(subdirs, reverse=True):
                nd = norm(sd)
                if any(nd == e or nd.startswith(e.rstrip(os.sep) + os.sep) for e in excluded):
                    continue
                if os.path.basename(sd).casefold() in SKIP_DIR_NAMES:
                    continue
                stack.append(sd)
            if d in done_dirs:
                continue
            self._apply_files(conn, rid, d, files, gen)
            conn.execute("INSERT OR REPLACE INTO scan_dirs(root_id,path,generation) VALUES(?,?,?)", (rid, d, gen))
            conn.commit()
            self.state["dirs_done"] += 1
            self.state["bytes_seen"] += sum(f[1] for f in files)
            self.state["percent"] = min(99, int(self.state["bytes_seen"] * 100 / used))

        # 이번에 보이지 않은 파일 = 하드에서 지워진 파일 → 색인에서만 뺀다
        if not os.path.isdir(os_path(rpath)):
            raise Disconnected()
        stale = [r[0] for r in conn.execute("SELECT id FROM files WHERE root_id=? AND generation<?", (rid, gen))]
        for i in range(0, len(stale), 500):
            chunk = stale[i:i + 500]
            q = ",".join("?" * len(chunk))
            conn.execute(f"DELETE FROM names_fts WHERE rowid IN ({q})", chunk)
            conn.execute(f"DELETE FROM content_fts WHERE rowid IN ({q})", chunk)
            conn.execute(f"DELETE FROM files WHERE id IN ({q})", chunk)
        count = conn.execute("SELECT COUNT(*) FROM files WHERE root_id=?", (rid,)).fetchone()[0]
        conn.execute(
            "UPDATE roots SET generation=?, status='listed', files_count=?, last_scan_done=? WHERE id=?",
            (gen, count, dbm.now_iso(), rid),
        )
        conn.execute("DELETE FROM scan_dirs WHERE root_id=?", (rid,))
        conn.commit()

    def _list_dir(self, conn, rid, rpath, d):
        subdirs: list[str] = []
        files: list[tuple[str, int, float]] = []
        try:
            with os.scandir(os_path(d)) as it:
                for e in it:
                    name = e.name
                    full = os.path.join(d, name)
                    try:
                        if e.is_symlink():
                            continue  # 바로가기는 따라가지 않음(무한 반복 방지)
                        if e.is_dir(follow_symlinks=False):
                            subdirs.append(full)
                        elif e.is_file(follow_symlinks=False):
                            st = e.stat(follow_symlinks=False)
                            files.append((full, st.st_size, st.st_mtime))
                    except OSError as ex:
                        self._unreadable(conn, full, _reason(ex), "scan")
        except FileNotFoundError:
            if not os.path.isdir(os_path(rpath)):
                raise Disconnected() from None
            self._unreadable(conn, d, "폴더가 사라졌어요", "scan")
        except PermissionError:
            self._unreadable(conn, d, "폴더를 열 권한이 없어요", "scan")
        except OSError as ex:
            if not os.path.isdir(os_path(rpath)):
                raise Disconnected() from None
            self._unreadable(conn, d, _reason(ex), "scan")
        return subdirs, files

    def _apply_files(self, conn, rid, d, files, gen):
        sd = safe_text(d)
        existing = {r["path"]: r for r in conn.execute("SELECT id,path,size,mtime FROM files WHERE dir=?", (sd,))}
        now = dbm.now_iso()
        for full, size, mtime in files:
            path = safe_text(full)
            name = os.path.basename(path)
            ext = os.path.splitext(name)[1][1:].lower()
            kind = kind_of(ext)
            old = existing.get(path)
            if old is not None:
                if old["size"] == size and abs((old["mtime"] or 0) - mtime) < 1:
                    conn.execute("UPDATE files SET generation=? WHERE id=?", (gen, old["id"]))
                else:
                    conn.execute(
                        "UPDATE files SET size=?, mtime=?, generation=?, detail_status='pending', hash=NULL,"
                        " face_status='pending', scene_status='pending', indexed_at=? WHERE id=?",
                        (size, mtime, gen, now, old["id"]),
                    )
                    conn.execute("DELETE FROM voice_segments WHERE file_id=?", (old["id"],))
            else:
                cur = conn.execute(
                    "INSERT OR IGNORE INTO files(root_id,path,dir,name,ext,kind,size,mtime,generation,"
                    "detail_status,indexed_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                    (rid, path, sd, name, ext, kind, size, mtime, gen,
                     "pending" if kind in ("image", "video", "doc") else "done", now),
                )
                if cur.rowcount:
                    conn.execute("INSERT INTO names_fts(rowid,name,dir) VALUES(?,?,?)", (cur.lastrowid, name, sd))
                    if kind not in ("image", "video", "doc"):
                        self._set_date_from_mtime(conn, cur.lastrowid, mtime)
            self.state["files_seen"] += 1

    @staticmethod
    def _set_date_from_mtime(conn, fid, mtime):
        try:
            t = dt.datetime.fromtimestamp(mtime)
        except (OverflowError, OSError, ValueError):
            return
        conn.execute(
            "UPDATE files SET taken_at=?, taken_year=?, taken_month=?, taken_day=? WHERE id=?",
            (t.strftime("%Y-%m-%dT%H:%M:%S"), t.year, t.month, t.day, fid),
        )

    def _unreadable(self, conn, path, reason, stage):
        self.state["errors"] += 1
        conn.execute(
            "INSERT INTO unreadable(path,reason,stage,at) VALUES(?,?,?,?) "
            "ON CONFLICT(path) DO UPDATE SET reason=excluded.reason, stage=excluded.stage, at=excluded.at",
            (safe_text(path), reason, stage, dbm.now_iso()),
        )

    # ---- 2) 자세히 단계 -----------------------------------------------
    def _details(self, conn: sqlite3.Connection, rid: int) -> None:
        total = conn.execute(
            "SELECT COUNT(*) FROM files WHERE root_id=? AND detail_status='pending'", (rid,)
        ).fetchone()[0]
        self.state.update(phase="detail", detail_total=total, detail_done=0, message="사진 정보와 문서 내용을 읽는 중")
        root_path = conn.execute("SELECT path FROM roots WHERE id=?", (rid,)).fetchone()[0]
        while True:
            rows = conn.execute(
                "SELECT id,path,name,ext,kind,mtime FROM files WHERE root_id=? AND detail_status='pending' LIMIT 100",
                (rid,),
            ).fetchall()
            if not rows:
                break
            for r in rows:
                self._checkpoint()
                self.state["folder"] = r["name"]
                try:
                    self._detail_one(conn, r)
                except OSError:
                    if not os.path.isdir(os_path(root_path)):
                        raise Disconnected() from None
                    self._unreadable(conn, r["path"], "파일을 읽을 수 없어요", "detail")
                    conn.execute("UPDATE files SET detail_status='fail' WHERE id=?", (r["id"],))
                self.state["detail_done"] += 1
                if total:
                    self.state["percent"] = min(99, int(self.state["detail_done"] * 100 / total))
            conn.commit()
        conn.execute("UPDATE roots SET status='done' WHERE id=?", (rid,))
        conn.commit()

    def _detail_one(self, conn, r) -> None:
        fid, path, kind, ext = r["id"], r["path"], r["kind"], r["ext"]
        p = os_path(path)
        info: dict = {}
        status = "done"
        content_status = "none"
        if kind == "image":
            try:
                info = media.image_info(p)
            except media.MediaError as e:
                self._unreadable(conn, path, str(e), "detail")
                status = "fail"
        elif kind == "video":
            info = media.video_info(p)
        elif kind == "doc":
            try:
                text = extract.extract_text(p, ext)
                conn.execute("DELETE FROM content_fts WHERE rowid=?", (fid,))
                if text:
                    conn.execute("INSERT INTO content_fts(rowid, body) VALUES(?,?)", (fid, text))
                content_status = "ok" if text else "empty"
                conn.execute("DELETE FROM unreadable WHERE path=? AND stage='content'", (path,))
            except extract.ExtractError as e:
                self._unreadable(conn, path, str(e), "content")
                content_status = "fail"
        taken = info.get("taken_at")
        if taken:
            t = dt.datetime.fromisoformat(taken)
        else:
            try:
                t = dt.datetime.fromtimestamp(r["mtime"])
            except (OverflowError, OSError, ValueError, TypeError):
                t = None
        place = media.nearest_place(info["lat"], info["lon"]) if "lat" in info else None
        conn.execute(
            "UPDATE files SET taken_at=?, taken_year=?, taken_month=?, taken_day=?, lat=?, lon=?, place=?,"
            " width=?, height=?, duration=?, detail_status=?, content_status=? WHERE id=?",
            (
                t.strftime("%Y-%m-%dT%H:%M:%S") if t else None,
                t.year if t else None, t.month if t else None, t.day if t else None,
                info.get("lat"), info.get("lon"), place,
                info.get("width"), info.get("height"), info.get("duration"),
                status, content_status, fid,
            ),
        )


class _Stopped(Exception):
    pass


def _reason(ex: OSError) -> str:
    if isinstance(ex, PermissionError):
        return "읽을 권한이 없어요"
    if isinstance(ex, FileNotFoundError):
        return "파일이 사라졌어요"
    if getattr(ex, "winerror", None) == 206 or "name too long" in str(ex).lower():
        return "경로가 너무 길어요"
    return "읽을 수 없어요"
