"""윈도우 설치 프로그램(PyInstaller)의 시작 파일.

창 없는 프로그램은 시작 중 오류가 보이지 않으므로, 실패하면 자료 폴더의 logs/crash.log 에 남긴다.
"""

import os
import sys
import time
import traceback


def _crash_log() -> str:
    base = os.environ.get("HDBISEO_HOME") or os.path.join(os.environ.get("LOCALAPPDATA", os.path.expanduser("~")), "HDBiseo")
    d = os.path.join(base, "logs")
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, "crash.log")


if __name__ == "__main__":
    if os.environ.get("HDBISEO_DIAG") == "1":  # 시험용 진단: 시작 표시 + 40초 넘게 걸리면 어디서 멈췄는지 기록
        import faulthandler

        with open(_crash_log(), "a", encoding="utf-8") as f:  # 앱 자료 폴더의 기록 파일
            f.write(time.strftime("%H:%M:%S") + " 부트 시작\n")
        _diag = open(_crash_log(), "a", encoding="utf-8")  # noqa: SIM115 - 진단 동안 열어 둠
        faulthandler.dump_traceback_later(40, repeat=False, file=_diag)
    try:
        from hdbiseo.server import run

        run(open_browser="--no-browser" not in sys.argv)
    except SystemExit:
        raise
    except BaseException:
        with open(_crash_log(), "a", encoding="utf-8") as f:  # 앱 자료 폴더의 기록 파일
            f.write(time.strftime("%Y-%m-%d %H:%M:%S") + " 시작 실패\n" + traceback.format_exc() + "\n")
        raise
