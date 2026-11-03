"""윈도우 전용: PC 시작 시 자동 실행(레지스트리 Run 'HDBiseo' — 설치 프로그램과 같은 이름)."""

from __future__ import annotations

import sys

RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
NAME = "HDBiseo"


def set_autostart(on: bool) -> bool:
    if not sys.platform.startswith("win") or not getattr(sys, "frozen", False):
        return False
    import winreg

    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, winreg.KEY_SET_VALUE) as k:
        if on:
            winreg.SetValueEx(k, NAME, 0, winreg.REG_SZ, f'"{sys.executable}" --no-browser')
        else:
            try:
                winreg.DeleteValue(k, NAME)
            except FileNotFoundError:
                pass
    return True


def autostart_enabled() -> bool | None:
    if not sys.platform.startswith("win"):
        return None
    import winreg

    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as k:
            winreg.QueryValueEx(k, NAME)
            return True
    except OSError:
        return False
