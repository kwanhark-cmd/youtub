"""업데이트 확인·설치. 사용자가 '업데이트 확인'을 누를 때만 GitHub Releases에 접속한다(보내는 자료 없음).

- 분석(색인) 중이면 설치를 막는다.
- 설치 전 자동 백업: 설정·사용자 목록·인물(얼굴 이름)·연락처·메모·인맥 (색인 자체는 제외 — 설치가 색인을 건드리지 않음)
- 윈도우: 설치 파일을 내려받아 실행(덮어쓰기 설치, 자료 폴더는 그대로). 맥·안드로이드: 내려받기 주소 안내
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.request
import zipfile
from pathlib import Path

from . import VERSION
from . import settings as st

REPO = os.environ.get("HDBISEO_UPDATE_REPO", "kwanhark-cmd/3333")
PATTERNS = {"windows": r"HDBiseo-Setup-.*\.exe$", "mac": r"\.dmg$", "android": r"\.apk$"}


class UpdateError(Exception):
    pass


def _ver(v: str) -> tuple:
    return tuple(int(x) for x in re.findall(r"\d+", v or "0")[:3]) or (0,)


def check(opener=None) -> dict:
    opener = opener or urllib.request.urlopen
    req = urllib.request.Request(f"https://api.github.com/repos/{REPO}/releases/latest",
                                 headers={"User-Agent": "HDBiseo-Updater", "Accept": "application/vnd.github+json"})
    try:
        with opener(req, timeout=20) as r:
            rel = json.loads(r.read())
    except Exception as e:
        raise UpdateError("업데이트 정보를 가져오지 못했어요. 인터넷 연결을 확인해 주세요.") from e
    latest = (rel.get("tag_name") or "").lstrip("v")
    assets = {}
    for a in rel.get("assets") or []:
        for plat, pat in PATTERNS.items():
            if re.search(pat, a.get("name", "")):
                assets[plat] = {"name": a["name"], "url": a.get("browser_download_url"), "size": a.get("size"),
                                "sha256": (a.get("digest") or "").removeprefix("sha256:") or None}
    return {"current": VERSION, "latest": latest, "newer": _ver(latest) > _ver(VERSION),
            "notes": rel.get("body") or "", "assets": assets, "page": rel.get("html_url")}


def backup_before_update(engines: list) -> Path:
    """설정·인물 정보만 묶어 둔다(색인 제외)."""
    home = st.app_home()
    dest = home / "backups" / f"before_update_{VERSION}_{time.strftime('%Y%m%d_%H%M%S')}.zip"
    dest.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
        for f in ("users.json", "app.json", "location.json"):
            if (home / f).exists():
                z.write(home / f, f)
        for s in home.glob("users/*/settings.json"):
            z.write(s, str(s.relative_to(home)))
        for e in engines:
            c = e.connect()
            try:
                dump = {t: [dict(r) for r in c.execute(f"SELECT * FROM {t}")] for t in
                        ("persons", "contacts", "notes", "record_people", "projects", "project_people", "project_records",
                         "scene_collections", "scene_collection_items")}
            finally:
                c.close()
            z.writestr(f"users/{e.user_id}/people.json", json.dumps(dump, ensure_ascii=False, default=str))
    return dest


def download(asset: dict, opener=None, progress: dict | None = None) -> Path:
    opener = opener or urllib.request.urlopen
    folder = st.app_home() / "updates"
    folder.mkdir(parents=True, exist_ok=True)
    dest = folder / os.path.basename(asset["name"])
    part = dest.with_suffix(dest.suffix + ".part")
    h = hashlib.sha256()
    req = urllib.request.Request(asset["url"], headers={"User-Agent": "HDBiseo-Updater"})
    try:
        with opener(req, timeout=60) as r, open(part, "wb") as out:  # 앱 폴더(updates)에 새 파일 저장
            done = 0
            while True:
                b = r.read(1024 * 256)
                if not b:
                    break
                out.write(b)
                h.update(b)
                done += len(b)
                if progress is not None:
                    progress["done"] = done
    except Exception as e:
        raise UpdateError("새 버전을 내려받지 못했어요. 인터넷 연결을 확인해 주세요.") from e
    if asset.get("sha256") and h.hexdigest() != asset["sha256"]:
        raise UpdateError("내려받은 파일이 손상되었어요. 다시 해 주세요.")
    os.replace(part, dest)
    return dest


def run_installer(path: Path) -> None:
    """윈도우 설치 파일 실행 후 엔진을 끈다(설치 프로그램이 같은 위치에 덮어씀)."""
    if not sys.platform.startswith("win"):
        raise UpdateError("자동 설치는 윈도우 PC에서만 돼요.")
    subprocess.Popen([str(path), "/SILENT", "/SP-", "/NOCANCEL", "/CLOSEAPPLICATIONS"], close_fds=True)  # noqa: S603
    threading.Timer(1.0, lambda: os._exit(0)).start()
