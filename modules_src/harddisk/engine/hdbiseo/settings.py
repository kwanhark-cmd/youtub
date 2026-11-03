"""앱 폴더 위치와 설정 저장.

설정은 JSON 파일 하나에 저장한다. 키(API 키 등)는 사용자 PC의 앱 폴더에만 있고
저장소에는 절대 들어가지 않는다.
"""

from __future__ import annotations

import copy
import json
import os
import sys
import threading
from pathlib import Path

_lock = threading.RLock()

DEFAULT_SETTINGS: dict = {
    "first_run_done": False,
    "font_scale": 1,  # 0=보통, 1=크게, 2=아주 크게
    "theme": "light",  # light | dark | contrast
    "reduce_motion": False,
    "sound": True,
    "vibration": True,
    "tts_enabled": True,
    "tts_rate": 1.0,
    "night_only": False,
    "night_start": "23:00",
    "night_end": "06:00",
    "thumb_cache_mb": 2048,
    "ai_enabled": False,
    "ai_api_key": "",
    "ai_model": "claude-sonnet-5-5",
    "ai_monthly_limit_won": 5000,
    "google_client_id": "",
    "google_client_secret": "",
    "google_token": None,
    "lan_enabled": False,
    "iphone_support": False,
    "voice_engine": "builtin",  # builtin | external
    "tips_seen": [],
    "app_name": "하드 자료 찾기 비서",   # 표시 이름(홈·창 제목·알림)
    "app_icon": "mascot",              # mascot | camera | house | computer-disk | sparkles | family | notebook | custom
    "palette": "blue",                 # 색 테마: blue | green | purple | orange | pink
    "autostart": True,                 # 윈도우: PC 시작 시 자동 실행
    "face_model": "sface",             # sface(상업 사용 가능) | insightface(개인 사용용)
}


def default_home() -> Path:
    """기본 자료 폴더(프로그램 폴더가 아닌 사용자 데이터 폴더). 업데이트로 바뀌지 않는다."""
    env = os.environ.get("HDBISEO_HOME")
    if env:
        return Path(env)
    if sys.platform.startswith("win"):
        return Path(os.environ.get("LOCALAPPDATA", Path.home())) / "HDBiseo"
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "HDBiseo"
    return Path.home() / ".hdbiseo"


def app_home() -> Path:
    """앱 자료 폴더(설정·색인·썸네일·얼굴 이름·메모). 사용자가 다른 위치로 옮겼으면 그곳."""
    base = default_home()
    base.mkdir(parents=True, exist_ok=True)
    pointer = base / "location.json"
    if pointer.exists():
        try:
            target = Path(json.loads(pointer.read_text(encoding="utf-8"))["home"])
            if target.is_dir():
                return target
        except (OSError, ValueError, KeyError):
            pass
    return base


def user_dir(user_id: str) -> Path:
    safe = "".join(ch for ch in user_id if ch.isalnum() or ch in "-_") or "default"
    d = app_home() / "users" / safe
    d.mkdir(parents=True, exist_ok=True)
    return d


def _settings_path(user_id: str) -> Path:
    return user_dir(user_id) / "settings.json"


def load(user_id: str) -> dict:
    with _lock:
        data = copy.deepcopy(DEFAULT_SETTINGS)
        p = _settings_path(user_id)
        if p.exists():
            try:
                saved = json.loads(p.read_text(encoding="utf-8"))
                if isinstance(saved, dict):
                    data.update(saved)
            except (OSError, ValueError):
                # 망가진 설정 파일은 기본값으로 대체하고 계속 동작
                pass
        return data


def save(user_id: str, values: dict) -> dict:
    with _lock:
        data = load(user_id)
        for k, v in values.items():
            if k in DEFAULT_SETTINGS:
                data[k] = v
        p = _settings_path(user_id)
        tmp = p.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(tmp, p)
        return data


def public_view(data: dict) -> dict:
    """화면에 보낼 때는 비밀 값을 가린다."""
    out = dict(data)
    for k in ("ai_api_key", "google_client_secret"):
        out[k] = "********" if out.get(k) else ""
    out["google_connected"] = bool(out.get("google_token"))
    out.pop("google_token", None)
    return out


# ---- 사용자(가족) 목록 -------------------------------------------------

def _users_path() -> Path:
    return app_home() / "users.json"


def list_users() -> list[dict]:
    with _lock:
        p = _users_path()
        if p.exists():
            try:
                users = json.loads(p.read_text(encoding="utf-8"))
                if isinstance(users, list) and users:
                    return users
            except (OSError, ValueError):
                pass
        users = [{"id": "default", "name": "나", "emoji": "🙂"}]
        p.write_text(json.dumps(users, ensure_ascii=False), encoding="utf-8")
        return users


def add_user(name: str, emoji: str = "🙂") -> dict:
    with _lock:
        users = list_users()
        n = 1
        while any(u["id"] == f"user{n}" for u in users):
            n += 1
        u = {"id": f"user{n}", "name": name.strip()[:20] or f"사용자{n}", "emoji": emoji}
        users.append(u)
        _users_path().write_text(json.dumps(users, ensure_ascii=False), encoding="utf-8")
        user_dir(u["id"])
        return u


# ---- PC 전체 설정(다른 기기 접속 등) ------------------------------------

APP_DEFAULTS = {"lan_enabled": False, "port": 47810, "pair_code": "", "tokens": [], "autostart_set": False}


def app_config() -> dict:
    with _lock:
        p = app_home() / "app.json"
        data = dict(APP_DEFAULTS)
        if p.exists():
            try:
                data.update(json.loads(p.read_text(encoding="utf-8")))
            except (OSError, ValueError):
                pass
        return data


def save_app_config(values: dict) -> dict:
    with _lock:
        data = app_config()
        data.update({k: v for k, v in values.items() if k in APP_DEFAULTS})
        p = app_home() / "app.json"
        tmp = p.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(tmp, p)
        return data
