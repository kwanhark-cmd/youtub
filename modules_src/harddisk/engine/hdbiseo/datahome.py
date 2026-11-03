"""자료 위치 관리: 다른 드라이브로 옮기기, 옛 위치(프로그램 폴더)에서 1회 자동 이전.

원칙: 업데이트·이전 중에 색인(며칠 걸려 만든 분석 결과)이 절대 사라지지 않게 '복사 → 확인 → 전환' 순서.
옛 위치의 자료는 지우지 않고 그대로 남긴다(사용자가 확인 후 직접 정리).
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import sys
from pathlib import Path

from . import settings as st

log = logging.getLogger("hdbiseo.datahome")
ITEMS = ("users", "users.json", "app.json", "models", "branding", "내보내기")


def _copy_items(src: Path, dst: Path) -> None:
    dst.mkdir(parents=True, exist_ok=True)
    for name in ITEMS:
        s = src / name
        if not s.exists():
            continue
        if s.is_dir():
            shutil.copytree(s, dst / name, dirs_exist_ok=True)
        else:
            shutil.copy2(s, dst / name)


def move_to(new_home: str) -> Path:
    """자료를 새 위치로 복사하고, 색인이 열리는지 확인한 뒤 새 위치를 쓰게 한다."""
    from . import db as dbm

    target = Path(new_home).resolve()
    cur = st.app_home().resolve()
    if target == cur:
        raise ValueError("지금과 같은 위치예요.")
    if cur in target.parents:
        raise ValueError("지금 자료 폴더 안으로는 옮길 수 없어요.")
    target.mkdir(parents=True, exist_ok=True)
    free = shutil.disk_usage(target).free
    need = sum(p.stat().st_size for p in cur.rglob("*") if p.is_file())
    if free < need * 1.2:
        raise ValueError("새 위치에 빈 공간이 부족해요.")
    _copy_items(cur, target)
    for idx in target.glob("users/*/index.db"):
        c = dbm.connect(idx)
        ok = c.execute("PRAGMA quick_check").fetchone()[0]
        c.close()
        if ok != "ok":
            raise ValueError("복사한 색인 확인에 실패했어요. 원래 위치를 계속 써요.")
    pointer = st.default_home() / "location.json"
    tmp = pointer.with_suffix(".tmp")
    tmp.write_text(json.dumps({"home": str(target)}, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, pointer)
    log.info("자료 위치를 옮겼어요")
    return target


def migrate_legacy() -> bool:
    """혹시 프로그램 폴더에 자료가 있으면(옛 방식) 사용자 자료 폴더로 1회 복사한다."""
    exe_dir = Path(sys.executable).resolve().parent if getattr(sys, "frozen", False) else None
    if exe_dir is None or not (exe_dir / "users").is_dir():
        return False
    home = st.app_home()
    if (home / "users").exists():
        return False
    _copy_items(exe_dir, home)
    log.info("프로그램 폴더의 자료를 사용자 자료 폴더로 옮겼어요")
    return True


def info() -> dict:
    home = st.app_home()
    return {
        "home": str(home), "default": str(st.default_home()), "moved": home.resolve() != st.default_home().resolve(),
        "index_files": [str(p) for p in sorted(home.glob("users/*/index.db"))],
    }
