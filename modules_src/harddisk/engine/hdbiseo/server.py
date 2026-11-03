"""분석 엔진 웹 서버. 보기 화면(web/)과 API를 함께 제공한다.

기본은 이 PC 안에서만 접속(127.0.0.1). 설정에서 '다른 기기에서 보기'를 켜면
같은 와이파이의 맥·안드로이드에서 접속할 수 있고, 처음 한 번 연결 번호가 필요하다.
"""

from __future__ import annotations

import logging
import os
import secrets
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles

from . import APP_NAME, VERSION, applog, dupes, media, search, sysinfo, trash, views
from . import db as dbm
from . import settings as st
from .core import get_engine
from .indexer import os_path

log = logging.getLogger("hdbiseo.server")


def web_dir() -> Path:
    if getattr(sys, "frozen", False):  # 설치 프로그램(PyInstaller)
        return Path(getattr(sys, "_MEIPASS", ".")) / "web"
    return Path(__file__).resolve().parents[2] / "web"


class UserError(Exception):
    """사용자에게 그대로 보여줄 쉬운 한국어 오류."""

    def __init__(self, msg: str, code: int = 400, stage: str = "요청"):
        super().__init__(msg)
        self.code = code
        self.stage = stage


app = FastAPI(title=APP_NAME, version=VERSION, docs_url=None, redoc_url=None)
_dupe_finders: dict[str, dupes.DupeFinder] = {}

# 데스크톱(Electron)·안드로이드(Capacitor) 포장 앱에서 접속 허용
from fastapi.middleware.cors import CORSMiddleware  # noqa: E402

app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"^(capacitor://localhost|https?://localhost(:\d+)?|app://.*|file://.*)$",
    allow_credentials=True, allow_methods=["*"], allow_headers=["*"],
)


def _is_local(request: Request) -> bool:
    host = request.client.host if request.client else ""
    return host in ("127.0.0.1", "::1", "localhost", "testclient")


@app.middleware("http")
async def guard(request: Request, call_next):
    """다른 기기에서 온 요청은 연결 번호로 받은 표가 있어야 한다."""
    path = request.url.path
    if path.startswith("/api/") and not _is_local(request) and path not in ("/api/health", "/api/pair"):
        cfg = st.app_config()
        token = request.cookies.get("hd_token") or request.headers.get("x-hd-token")
        if not cfg.get("lan_enabled"):
            return JSONResponse({"error": "이 PC에서 '다른 기기에서 보기'가 꺼져 있어요."}, status_code=403)
        if not token or token not in cfg.get("tokens", []):
            return JSONResponse({"error": "연결 번호를 먼저 입력해 주세요.", "need_pair": True}, status_code=401)
    try:
        return await call_next(request)
    except Exception:  # 전역 오류 처리: 엔진은 죽지 않고 쉬운 말로 알려준다
        log.exception("요청 처리 중 오류: %s", path)
        return JSONResponse({"error": "잠깐 문제가 생겼어요. 다시 해 보세요. 계속되면 설정 > 문제 신고를 눌러 주세요."},
                            status_code=500)


@app.exception_handler(UserError)
async def _user_error(req, exc: UserError):
    # 사용자에게 실패 창을 보여주는 모든 경우를 단계와 함께 기록(내용·연락처·열쇠는 기록 안 함)
    log.error("[%s] %s %s → %s", exc.stage, req.method, req.url.path, str(exc))
    return JSONResponse({"error": str(exc), "stage": exc.stage}, status_code=exc.code)


@app.exception_handler(HTTPException)
async def _http_error(_req, exc: HTTPException):
    return JSONResponse({"error": exc.detail if isinstance(exc.detail, str) else "요청을 처리할 수 없어요."},
                        status_code=exc.status_code)


def eng(request: Request):
    uid = request.headers.get("x-hd-user") or request.cookies.get("hd_user") or "default"
    if not any(u["id"] == uid for u in st.list_users()):
        uid = "default"
    return get_engine(uid)


async def body(request: Request) -> dict:
    try:
        data = await request.json()
        return data if isinstance(data, dict) else {}
    except (ValueError, UnicodeDecodeError):
        return {}


# ---- 기본 -------------------------------------------------------------

@app.get("/api/health")
def health():
    return {"ok": True, "app": APP_NAME, "version": VERSION, "schema": dbm.SCHEMA_VERSION, "pc": socket.gethostname()}


@app.post("/api/pair")
async def pair(request: Request):
    data = await body(request)
    cfg = st.app_config()
    if not cfg.get("lan_enabled"):
        raise UserError("PC에서 '다른 기기에서 보기'를 먼저 켜 주세요.", 403)
    if not cfg.get("pair_code") or str(data.get("code", "")).strip() != cfg["pair_code"]:
        time.sleep(1)  # 마구 대입 방지
        raise UserError("연결 번호가 맞지 않아요. PC 화면의 번호를 확인해 주세요.", 401)
    token = secrets.token_urlsafe(24)
    st.save_app_config({"tokens": (cfg.get("tokens", []) + [token])[-20:]})
    resp = JSONResponse({"ok": True, "token": token})
    resp.set_cookie("hd_token", token, max_age=3600 * 24 * 365, httponly=True, samesite="lax")
    return resp


@app.get("/api/lan")
def lan_info(request: Request):
    if not _is_local(request):
        raise UserError("이 설정은 PC에서만 바꿀 수 있어요.", 403)
    cfg = st.app_config()
    return {"enabled": cfg["lan_enabled"], "code": cfg["pair_code"], "addresses": local_addresses(), "port": cfg["port"]}


@app.post("/api/lan")
async def lan_set(request: Request):
    if not _is_local(request):
        raise UserError("이 설정은 PC에서만 바꿀 수 있어요.", 403)
    data = await body(request)
    on = bool(data.get("enabled"))
    vals = {"lan_enabled": on}
    if on:
        vals["pair_code"] = f"{secrets.randbelow(1000000):06d}"
    else:
        vals["tokens"] = []
    st.save_app_config(vals)
    return {**lan_info(request), "restart_needed": True}


def local_addresses() -> list[str]:
    out = set()
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))
        out.add(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    try:
        for a in socket.gethostbyname_ex(socket.gethostname())[2]:
            if not a.startswith("127."):
                out.add(a)
    except OSError:
        pass
    return sorted(out)


@app.get("/api/system")
def system(request: Request):
    e = eng(request)
    spec = sysinfo.info()
    used = 0
    for r in e.roots():
        try:
            used += shutil.disk_usage(os_path(r["path"])).used
        except OSError:
            pass
    from . import datahome

    return {"spec": spec, "estimate": sysinfo.estimate(used, spec), "version": VERSION, "data": datahome.info(),
            "recognition": e.recognizer.status(), "ffmpeg": bool(media.ffmpeg_path("ffmpeg"))}


@app.get("/api/estimate")
def estimate(path: str):
    try:
        used = shutil.disk_usage(os_path(path)).used
    except OSError as ex:
        raise UserError("폴더를 찾을 수 없어요.") from ex
    return sysinfo.estimate(used)


# ---- 사용자 ------------------------------------------------------------

@app.get("/api/users")
def users():
    return st.list_users()


@app.post("/api/users")
async def add_user(request: Request):
    data = await body(request)
    if not str(data.get("name", "")).strip():
        raise UserError("이름을 입력해 주세요.")
    return st.add_user(str(data["name"]), str(data.get("emoji", "🙂"))[:4])


# ---- 설정 -------------------------------------------------------------

@app.get("/api/settings")
def get_settings(request: Request):
    e = eng(request)
    s = e.settings()
    if not s.get("first_run_done") and e.roots():
        s = st.save(e.user_id, {"first_run_done": True})  # 이미 설정이 있으면 첫 실행 마법사 건너뛰기
    return st.public_view(s)


@app.post("/api/settings")
async def set_settings(request: Request):
    e = eng(request)
    data = await body(request)
    for k in ("ai_api_key", "google_client_secret"):
        if data.get(k) == "********":
            data.pop(k)
    if "font_scale" in data and data["font_scale"] not in (0, 1, 2):
        raise UserError("글씨 크기는 3단계 중에서 골라 주세요.")
    if "theme" in data and data["theme"] not in ("light", "dark", "contrast"):
        raise UserError("화면 색 모드를 다시 골라 주세요.")
    if "palette" in data and data["palette"] not in ("blue", "green", "purple", "orange", "pink"):
        raise UserError("색 테마를 다시 골라 주세요.")
    if "app_name" in data:
        data["app_name"] = str(data["app_name"]).strip()[:24] or "하드 자료 찾기 비서"
    if "autostart" in data:
        from . import winsys

        winsys.set_autostart(bool(data["autostart"]))
        st.save_app_config({"autostart_set": True})
    for k in ("night_start", "night_end"):
        if k in data:
            try:
                h, m = str(data[k]).split(":")
                assert 0 <= int(h) < 24 and 0 <= int(m) < 60
            except (ValueError, AssertionError) as ex:
                raise UserError("시간은 23:00 처럼 적어 주세요.") from ex
    return st.public_view(st.save(e.user_id, data))


# ---- 폴더 고르기 ---------------------------------------------------------

@app.get("/api/browse")
def browse(path: str = ""):
    if not path:
        if os.name == "nt":
            import string

            drives = []
            for letter in string.ascii_uppercase:
                d = f"{letter}:\\"
                if os.path.exists(d):
                    try:
                        u = shutil.disk_usage(d)
                        drives.append({"path": d, "name": f"{letter} 드라이브", "total": u.total, "used": u.used})
                    except OSError:
                        drives.append({"path": d, "name": f"{letter} 드라이브"})
            return {"path": "", "parent": None, "dirs": drives}
        path = str(Path.home())
    p = os.path.abspath(path)
    if not os.path.isdir(os_path(p)):
        raise UserError("폴더를 찾을 수 없어요.")
    dirs = []
    try:
        with os.scandir(os_path(p)) as it:
            for e in it:
                try:
                    if e.is_dir(follow_symlinks=False) and not e.name.startswith((".", "$")):
                        dirs.append({"path": os.path.join(p, e.name), "name": e.name})
                except OSError:
                    continue
    except PermissionError as ex:
        raise UserError("이 폴더는 열 권한이 없어요.") from ex
    dirs.sort(key=lambda d: d["name"].casefold())
    parent = os.path.dirname(p.rstrip("\\/")) if p.rstrip("\\/") != os.path.dirname(p.rstrip("\\/")) else None
    if os.name == "nt" and len(p) <= 3:
        parent = ""
    return {"path": p, "parent": parent, "dirs": dirs[:2000]}


@app.post("/api/samples")
async def make_samples(request: Request):
    """체험용 예제 폴더 만들기(앱 폴더 안)."""
    from .samples import make_samples as mk

    dest = st.app_home() / "체험용_예제폴더"
    if not dest.exists():
        mk(dest)
    return {"path": str(dest)}


# ---- 분석할 하드 -------------------------------------------------------

@app.get("/api/roots")
def roots(request: Request):
    return eng(request).roots()


@app.post("/api/roots")
async def add_root(request: Request):
    data = await body(request)
    try:
        return eng(request).add_root(str(data.get("path", "")), data.get("label"), data.get("excluded") or [])
    except ValueError as ex:
        raise UserError(str(ex)) from ex


@app.patch("/api/roots/{root_id}")
async def patch_root(root_id: int, request: Request):
    data = await body(request)
    eng(request).update_root(root_id, data.get("excluded"), data.get("enabled"), data.get("label"))
    return {"ok": True}


@app.delete("/api/roots/{root_id}")
def delete_root(root_id: int, request: Request):
    eng(request).remove_root(root_id)
    return {"ok": True, "message": "분석 목록에서 뺐어요. 하드디스크의 파일은 그대로예요."}


# ---- 색인 -------------------------------------------------------------

@app.post("/api/index/{action}")
async def index_action(action: str, request: Request):
    e = eng(request)
    idx = e.indexer
    if action == "start":
        data = await body(request)
        if not e.roots():
            raise UserError("먼저 분석할 하드디스크나 폴더를 골라 주세요.")
        idx.start(data.get("root_ids"))
    elif action == "pause":
        idx.pause()
    elif action == "resume":
        if idx.is_running():
            idx.resume()
        else:
            idx.start()
    elif action == "stop":
        idx.stop(wait=False)
    else:
        raise UserError("알 수 없는 명령이에요.", 404)
    return index_status(request)


@app.get("/api/status")
def status(request: Request):
    """홈·설정의 상태 표시(색인 / 얼굴 모델 / 구글 / 엔진)."""
    e = eng(request)
    st_ = e.indexer.state
    roots_ = e.roots()
    rec = e.recognizer.status()
    s = e.settings()
    total = e.conn().execute("SELECT COUNT(*) FROM files").fetchone()[0]
    return {
        "engine": {"ok": True, "version": VERSION},
        "index": {"running": e.indexer.is_running(), "paused": st_.get("paused"), "percent": st_.get("percent", 0),
                  "phase": st_.get("phase"), "total": total, "roots": len(roots_),
                  "real_roots": sum(1 for r in roots_ if not r["sample"]), "sample_roots": sum(1 for r in roots_ if r["sample"]),
                  "disconnected": sum(1 for r in roots_ if r["status"] == "disconnected"),
                  "done": bool(roots_) and all(r["status"] == "done" for r in roots_)},
        "faces": {"on": rec["faces"], "reason": rec.get("faces_reason"), "model": rec.get("face_model")},
        "google": {"connected": bool(s.get("google_token")), "configured": bool(s.get("google_client_id"))},
        "lan": {"enabled": bool(st.app_config().get("lan_enabled"))},
    }


@app.get("/api/index/status")
def index_status(request: Request):
    e = eng(request)
    c = e.conn()
    return {"state": e.indexer.state, "running": e.indexer.is_running(), "roots": e.roots(), "overview": views.overview(c)}


@app.get("/api/unreadable")
def unreadable(request: Request, page: int = 1):
    c = eng(request).conn()
    total = c.execute("SELECT COUNT(*) FROM unreadable").fetchone()[0]
    rows = c.execute("SELECT * FROM unreadable ORDER BY at DESC LIMIT 50 OFFSET ?", ((max(page, 1) - 1) * 50,)).fetchall()
    return {"total": total, "page": page, "items": [dict(r) for r in rows]}


# ---- 검색 -------------------------------------------------------------

@app.get("/api/search")
def do_search(request: Request, q: str = "", kind: str = "", year: int | None = None, month: int | None = None,
              date_from: str = "", date_to: str = "", min_size: int | None = None, max_size: int | None = None,
              folder: str = "", root_id: int | None = None, ext: str = "", order: str = "new", page: int = 1,
              page_size: int = 50, mode: str = ""):
    e = eng(request)
    extra = {"kind": kind or None, "year": year, "month": month, "date_from": date_from or None,
             "date_to": date_to or None, "min_size": min_size, "max_size": max_size, "folder": folder or None,
             "root_id": root_id, "order": order}
    if ext:
        extra["exts"] = [x.strip().lower() for x in ext.split(",") if x.strip()]
    if mode in ("content", "scene", "name"):
        extra["mode"] = mode if mode != "name" else "all"
    res = search.search_all(e.conn(), q, page, page_size, extra, scene_search=e.recognizer.scene_search)
    res["speech"] = _speech(res)
    return res


def _speech(res: dict) -> str:
    n = 0
    for k in ("files", "content", "scenes"):
        if res.get(k):
            n += res[k].get("total", len(res[k].get("items", [])))
    if not n and not res.get("records"):
        return f"{res['understood']}을 찾지 못했어요."
    first = None
    for k in ("files", "content", "scenes"):
        if res.get(k) and res[k].get("items"):
            first = res[k]["items"][0]
            break
    msg = f"{res['understood']} {n}개를 찾았어요."
    if first and first.get("dir"):
        msg += f" 첫 번째는 {os.path.basename(first['dir'])} 폴더에 있어요."
    return msg


# ---- 파일 -------------------------------------------------------------

def _file(e, file_id: int):
    r = e.conn().execute("SELECT * FROM files WHERE id=?", (file_id,)).fetchone()
    if r is None:
        raise UserError("목록에 없는 파일이에요.", 404)
    return r


@app.get("/api/files/{file_id}")
def file_info(file_id: int, request: Request):
    e = eng(request)
    r = dict(_file(e, file_id))
    c = e.conn()
    r["notes"] = [dict(n) for n in c.execute("SELECT * FROM notes WHERE file_id=? ORDER BY id", (file_id,))]
    r["connected"] = os.path.exists(os_path(r["path"]))
    r["can_open_folder"] = _is_local(request)
    r.update(e.recognizer.file_extra(c, file_id))
    if r["kind"] == "doc" and r.get("content_status") == "ok":
        row = c.execute("SELECT substr(body,1,3000) FROM content_fts WHERE rowid=?", (file_id,)).fetchone()
        r["preview"] = row[0] if row else ""
    return r


@app.get("/api/files/{file_id}/thumb")
def thumb(file_id: int, request: Request, t: float = 0.0):
    e = eng(request)
    r = _file(e, file_id)
    if r["kind"] not in ("image", "video"):
        raise UserError("썸네일이 없는 종류예요.", 404)
    key = media.thumb_key(file_id, r["mtime"], t)
    dest = e.thumbs / key[:2] / f"{key}.jpg"
    if not dest.exists():
        try:
            media.make_thumbnail(os_path(r["path"]), r["kind"], dest, t or 1.0)
        except (media.MediaError, OSError) as ex:
            raise UserError("썸네일을 만들 수 없어요.", 404) from ex
        if secrets.randbelow(50) == 0:
            media.enforce_cache_limit(e.thumbs, int(e.settings().get("thumb_cache_mb", 2048)))
    return FileResponse(dest, media_type="image/jpeg", headers={"Cache-Control": "max-age=86400"})


@app.get("/api/files/{file_id}/raw")
def raw(file_id: int, request: Request):
    """원본 보기(읽기 전용 전송). 영상은 원하는 부분부터 재생할 수 있다."""
    e = eng(request)
    r = _file(e, file_id)
    p = os_path(r["path"])
    if not os.path.exists(p):
        raise UserError("파일을 찾을 수 없어요. 하드디스크 연결을 확인해 주세요.", 404)
    return FileResponse(p, filename=r["name"], content_disposition_type="inline")


@app.post("/api/files/{file_id}/open-folder")
def open_folder(file_id: int, request: Request):
    if not _is_local(request):
        raise UserError("폴더 열기는 PC에서만 할 수 있어요. 위치: " + _file(eng(request), file_id)["dir"], 403)
    r = _file(eng(request), file_id)
    try:
        if os.name == "nt":
            subprocess.Popen(["explorer", "/select,", r["path"]])  # noqa: S603 - 탐색기로 위치만 보여줌
        elif sys.platform == "darwin":
            subprocess.Popen(["open", "-R", r["path"]])
        else:
            subprocess.Popen(["xdg-open", r["dir"]])
    except OSError as ex:
        raise UserError("폴더를 열지 못했어요. 위치: " + r["dir"]) from ex
    return {"ok": True}


@app.post("/api/files/{file_id}/trash")
async def to_trash(file_id: int, request: Request):
    data = await body(request)
    try:
        return trash.move_to_trash(eng(request).conn(), file_id, data.get("confirm") is True)
    except trash.TrashError as ex:
        raise UserError(str(ex)) from ex


@app.post("/api/files/{file_id}/notes")
async def add_note(file_id: int, request: Request):
    e = eng(request)
    _file(e, file_id)
    data = await body(request)
    text = str(data.get("text", "")).strip()
    if not text:
        raise UserError("메모 내용이 비어 있어요.")
    c = e.conn()
    c.execute("INSERT INTO notes(file_id,text,source,created_at) VALUES(?,?,?,?)",
              (file_id, text[:5000], "voice" if data.get("voice") else "text", dbm.now_iso()))
    c.commit()
    return {"ok": True, "message": "메모를 붙였어요."}


@app.delete("/api/notes/{note_id}")
def del_note(note_id: int, request: Request):
    c = eng(request).conn()
    c.execute("DELETE FROM notes WHERE id=?", (note_id,))
    c.commit()
    return {"ok": True}


# ---- 사진·영상 보기 ------------------------------------------------------

@app.get("/api/timeline/years")
def t_years(request: Request, kind: str = ""):
    return views.years(eng(request).conn(), kind or None)


@app.get("/api/timeline/months")
def t_months(request: Request, year: int, kind: str = ""):
    return views.months(eng(request).conn(), year, kind or None)


@app.get("/api/timeline/items")
def t_items(request: Request, year: int | None = None, month: int | None = None, kind: str = "", page: int = 1,
            page_size: int = 60, place: str = ""):
    return views.items(eng(request).conn(), year, month, kind or None, page, page_size, place or None)


@app.get("/api/memories")
def memories(request: Request):
    return views.memories(eng(request).conn())


@app.get("/api/places")
def places(request: Request):
    return views.places(eng(request).conn())


@app.get("/api/today")
def today_card(request: Request):
    """홈 맨 위 '오늘 할 일' 카드."""
    e = eng(request)
    c = e.conn()
    roots_ = e.roots()
    if not roots_:
        return {"type": "start", "title": "분석할 하드디스크를 골라 주세요", "action": "#/wizard"}
    st_ = e.indexer.state
    if e.indexer.is_running():
        return {"type": "indexing", "title": "색인하는 중이에요", "percent": st_.get("percent", 0), "action": "#/index"}
    unfinished = [r for r in roots_ if r["status"] not in ("done",)]
    if unfinished:
        return {"type": "resume", "title": "색인을 이어서 할까요?", "action": "#/index"}
    mem = views.memories(c)
    if mem:
        m = mem[0]
        return {"type": "memory", "title": m["title"], "speech": m["speech"], "item": m["items"][0], "action": "#/memories"}
    return {"type": "search", "title": "무엇이든 찾아보세요", "action": "#/search"}


@app.get("/api/home")
def home(request: Request):
    """홈 화면 한 번에: 오늘 할 일, 종류별 개수, 사람 얼굴 줄."""
    e = eng(request)
    c = e.conn()
    ov = views.overview(c)
    try:
        records = c.execute("SELECT COUNT(*) FROM records").fetchone()[0]
        contacts = c.execute("SELECT COUNT(*) FROM contacts").fetchone()[0]
        people = [dict(r) for r in c.execute(
            "SELECT p.id, p.name, p.cover_face_id, COUNT(DISTINCT f.file_id) AS n FROM persons p JOIN faces f ON f.person_id=p.id"
            " WHERE p.hidden=0 AND f.confirmed>=0 GROUP BY p.id ORDER BY (p.name<>'') DESC, n DESC LIMIT 12")]
        dupes = c.execute("SELECT COUNT(*) FROM (SELECT 1 FROM files WHERE hash IS NOT NULL GROUP BY hash HAVING COUNT(*)>1)").fetchone()[0]
    except Exception:
        records = contacts = dupes = 0
        people = []
    return {"today": today_card(request), "overview": ov, "records": records, "contacts": contacts, "people": people, "dupes": dupes}


# ---- 중복 -------------------------------------------------------------

@app.post("/api/duplicates/scan")
def dup_scan(request: Request):
    e = eng(request)
    f = _dupe_finders.setdefault(e.user_id, dupes.DupeFinder(e))
    f.start()
    return f.state


@app.get("/api/duplicates")
def dup_list(request: Request, page: int = 1):
    e = eng(request)
    f = _dupe_finders.get(e.user_id)
    res = dupes.groups(e.conn(), page)
    res["state"] = f.state if f else {"running": False}
    return res


# ---- 백업·복원·초기화 ---------------------------------------------------

@app.post("/api/backup")
def backup(request: Request):
    e = eng(request)
    dest = e.dir / "backups" / f"backup_{time.strftime('%Y%m%d_%H%M%S')}.db"
    dbm.backup(e.conn(), dest)
    return {"ok": True, "file": dest.name, "message": "색인을 백업했어요."}


@app.get("/api/backups")
def backups(request: Request):
    d = eng(request).dir / "backups"
    files = sorted(d.glob("*.db"), reverse=True) if d.exists() else []
    return [{"file": p.name, "size": p.stat().st_size, "at": time.strftime("%Y-%m-%d %H:%M", time.localtime(p.stat().st_mtime))}
            for p in files]


@app.post("/api/restore")
async def restore(request: Request):
    e = eng(request)
    data = await body(request)
    name = os.path.basename(str(data.get("file", "")))
    src = e.dir / "backups" / name
    if not name or not src.exists():
        raise UserError("백업 파일을 찾을 수 없어요.")
    from . import core

    with core._lock:
        core._engines.pop(e.user_id, None)
    e.close_all()
    try:
        dbm.restore(e.db_path, src)
    except ValueError as ex:
        raise UserError(str(ex)) from ex
    finally:
        get_engine(e.user_id)
    return {"ok": True, "message": "백업에서 되살렸어요."}


@app.post("/api/reset")
async def reset(request: Request):
    """색인 초기화(앱이 만든 목록만 지움, 하드의 원본 파일은 그대로). 두 번 확인 필요."""
    e = eng(request)
    data = await body(request)
    if not (data.get("confirm1") is True and data.get("confirm2") == "초기화"):
        raise UserError("초기화하려면 두 번 확인해야 해요.")
    dbm.backup(e.conn(), e.dir / "backups" / f"before_reset_{int(time.time())}.db")
    e.indexer.stop()
    c = e.conn()
    for t in ("files", "names_fts", "content_fts", "unreadable", "scan_dirs", "notes", "faces", "persons", "scenes",
              "scenes_fts", "scene_collections", "scene_collection_items", "voice_segments", "records", "records_fts",
              "contacts", "record_people", "projects", "project_people", "project_records"):
        c.execute(f"DELETE FROM {t}")
    c.execute("UPDATE roots SET generation=0, scanning_generation=0, status='idle', files_count=0")
    c.commit()
    c.execute("VACUUM")
    return {"ok": True, "message": "색인을 초기화했어요. 하드디스크의 파일은 그대로예요. (초기화 전 자동 백업함)"}


# ---- 문제 신고 ---------------------------------------------------------

@app.get("/api/report")
def report(request: Request):
    e = eng(request)
    extra = {"version": VERSION, "schema": dbm.SCHEMA_VERSION, "system": sysinfo.info(),
             "index": {k: v for k, v in e.indexer.state.items() if k != "folder"}, "overview": views.overview(e.conn()),
             "roots": [{"status": r["status"], "files": r["files_count"]} for r in e.roots()]}
    data = applog.export_bundle(extra)
    return Response(data, media_type="application/zip",
                    headers={"Content-Disposition": f"attachment; filename=hdbiseo_report_{time.strftime('%Y%m%d')}.zip"})


@app.post("/api/shutdown")
def shutdown(request: Request):
    """설정 > 프로그램 끄기 (PC에서만)."""
    if not _is_local(request):
        raise UserError("프로그램 끄기는 PC에서만 할 수 있어요.", 403)
    import threading

    for e in list(__import__("hdbiseo.core", fromlist=["_engines"])._engines.values()):
        e.indexer.stop(wait=False)
    threading.Timer(0.8, lambda: os._exit(0)).start()
    return {"ok": True, "message": "프로그램을 껐어요. 다시 켜려면 바탕화면 아이콘을 누르세요."}


@app.post("/api/client-error")
async def client_error(request: Request):
    data = await body(request)
    log.error("[%s] 화면 오류: %s", str(data.get("stage", "화면"))[:20], str(data.get("message", ""))[:300])
    return {"ok": True}


@app.get("/api/branding/icon.{fmt}")
def branding_icon(fmt: str, request: Request, user: str = ""):
    from . import branding

    uid = user or request.cookies.get("hd_user") or "default"
    choice = st.load(uid if any(u["id"] == uid for u in st.list_users()) else "default").get("app_icon", "mascot")
    if fmt not in ("png", "ico"):
        raise UserError("알 수 없는 그림 형식이에요.", 404)
    return Response(branding.icon_bytes(choice, "ICO" if fmt == "ico" else "PNG"),
                    media_type="image/x-icon" if fmt == "ico" else "image/png", headers={"Cache-Control": "no-cache"})


@app.post("/api/branding/icon")
async def branding_upload(request: Request):
    from fastapi import UploadFile

    from . import branding

    form = await request.form()
    f = form.get("file")
    if not isinstance(f, UploadFile) and not hasattr(f, "read"):
        raise UserError("사진 파일을 골라 주세요.")
    try:
        branding.save_custom(await f.read())
    except ValueError as ex:
        raise UserError(str(ex)) from ex
    st.save(eng(request).user_id, {"app_icon": "custom"})
    return {"ok": True, "message": "내 사진으로 아이콘을 바꿨어요."}


@app.get("/manifest.webmanifest")
def manifest():
    from . import branding

    return Response(branding.manifest(st.load("default")), media_type="application/manifest+json", headers={"Cache-Control": "no-cache"})


def mount_web() -> None:
    wd = web_dir()
    if wd.exists() and not any(getattr(r, "name", "") == "web" for r in app.routes):
        app.mount("/", StaticFiles(directory=str(wd), html=True), name="web")


_extras_done = False


def register_extras() -> None:
    global _extras_done
    if _extras_done:
        return
    _extras_done = True
    from . import routes_more, routes_setup, routes_update  # 3·5단계 기능, 업데이트, 설정 도우미

    routes_more.register(app)
    routes_update.register(app)
    routes_setup.register(app)


def _already_running(port: int) -> bool:
    import json
    import urllib.request

    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/health", timeout=1.5) as r:  # 이 PC 안의 엔진 확인
            return json.loads(r.read()).get("app") == APP_NAME
    except Exception:
        return False


def run(host: str | None = None, port: int | None = None, open_browser: bool = True) -> None:
    import threading
    import webbrowser

    import uvicorn

    from . import datahome, discovery

    applog.setup()
    datahome.migrate_legacy()
    cfg = st.app_config()
    port = port or int(os.environ.get("HDBISEO_PORT") or cfg.get("port", 47810))
    if _already_running(port):  # 이미 켜져 있으면 화면만 열고 끝냄(두 번 실행 방지)
        if open_browser:
            webbrowser.open(f"http://127.0.0.1:{port}/")
        return
    host = host or ("0.0.0.0" if cfg.get("lan_enabled") else "127.0.0.1")
    register_extras()
    mount_web()
    if cfg.get("lan_enabled"):
        discovery.start_responder(port)
    from . import tray, winsys

    tray.start(port)
    if st.load("default").get("autostart", True) and winsys.autostart_enabled() is False and not st.app_config().get("autostart_set"):
        winsys.set_autostart(True)  # 기본 켜짐(처음 한 번만 — 사용자가 끄면 그대로)
        st.save_app_config({"autostart_set": True})
    if open_browser:
        threading.Timer(1.5, lambda: webbrowser.open(f"http://127.0.0.1:{port}/")).start()
    log.info("엔진 시작 %s (포트 %s)", VERSION, port)
    try:
        # 창 없는 실행 파일에는 콘솔이 없으므로 uvicorn 자체 로그 설정을 끈다(우리 로그 파일만 사용)
        uvicorn.run(app, host=host, port=port, log_config=None, log_level="warning", access_log=False)
    except Exception:
        log.exception("엔진을 시작하지 못했어요")
        raise


if __name__ == "__main__":
    run(open_browser="--no-browser" not in sys.argv)
