"""윈도우 작업 표시줄 알림 영역(트레이) 아이콘: 색인 진행률 표시, 열기·멈춤·끝내기."""

from __future__ import annotations

import logging
import os
import sys
import threading
import time
import webbrowser

log = logging.getLogger("hdbiseo.tray")


def tooltip(engines: list) -> str:
    running = [e for e in engines if e.indexer.is_running()]
    if not running:
        return "하드 자료 찾기 비서 — 쉬는 중"
    s = running[0].indexer.state
    if s.get("paused"):
        return f"하드 자료 찾기 비서 — 색인 멈춤 ({s.get('percent', 0)}%)"
    return f"하드 자료 찾기 비서 — 색인 중 {s.get('percent', 0)}%"


def start(port: int) -> bool:
    if not sys.platform.startswith("win") and os.environ.get("HDBISEO_TRAY") != "1":
        return False
    try:
        import pystray
    except ImportError:
        return False
    from . import branding, core
    from . import settings as st

    def engines():
        return list(core._engines.values()) or [core.get_engine("default")]

    def open_app(_icon=None, _item=None):
        webbrowser.open(f"http://127.0.0.1:{port}/")

    def toggle(_icon=None, _item=None):
        for e in engines():
            if e.indexer.is_running():
                (e.indexer.resume if e.indexer.state.get("paused") else e.indexer.pause)()

    def quit_app(icon, _item=None):
        for e in engines():
            e.indexer.stop(wait=False)
        icon.stop()
        os._exit(0)

    icon = pystray.Icon("HDBiseo", branding.icon_image(st.load("default").get("app_icon", "mascot")), "하드 자료 찾기 비서",
                        menu=pystray.Menu(pystray.MenuItem("열기", open_app, default=True),
                                          pystray.MenuItem("색인 잠시 멈춤 / 이어서", toggle),
                                          pystray.MenuItem("끝내기", quit_app)))

    def updater():
        while True:
            try:
                icon.title = tooltip(engines())
            except Exception:  # 트레이 문제로 엔진이 멈추지 않게
                pass
            time.sleep(3)

    threading.Thread(target=icon.run, daemon=True, name="tray").start()
    threading.Thread(target=updater, daemon=True, name="tray-update").start()
    return True
