"""PC 사양 확인과 예상 시간 안내."""

from __future__ import annotations

import ctypes
import os
import platform
import shutil
import subprocess
import sys


def ram_gb() -> float:
    try:
        if sys.platform.startswith("win"):
            class MS(ctypes.Structure):
                _fields_ = [("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong),
                            ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
                            ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
                            ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
                            ("sullAvailExtendedVirtual", ctypes.c_ulonglong)]
            m = MS()
            m.dwLength = ctypes.sizeof(MS)
            ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))  # type: ignore[attr-defined]
            return round(m.ullTotalPhys / 1024**3, 1)
        if sys.platform == "darwin":
            out = subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True, timeout=5, check=False)
            return round(int(out.stdout.strip() or 0) / 1024**3, 1)
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemTotal"):
                    return round(int(line.split()[1]) / 1024**2, 1)
    except (OSError, ValueError, AttributeError, subprocess.SubprocessError):
        pass
    return 0.0


def gpu_name() -> str:
    try:
        if shutil.which("nvidia-smi"):
            out = subprocess.run(["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
                                 capture_output=True, text=True, timeout=10, check=False)
            if out.stdout.strip():
                return out.stdout.strip().splitlines()[0]
        if sys.platform.startswith("win"):
            out = subprocess.run(
                ["powershell", "-NoProfile", "-Command", "(Get-CimInstance Win32_VideoController).Name"],
                capture_output=True, text=True, timeout=15, check=False,
            )
            return out.stdout.strip().splitlines()[0] if out.stdout.strip() else ""
    except (OSError, subprocess.SubprocessError, IndexError):
        pass
    return ""


def info() -> dict:
    gpu = gpu_name()
    return {
        "os": f"{platform.system()} {platform.release()}",
        "cpu_cores": os.cpu_count() or 1,
        "ram_gb": ram_gb(),
        "gpu": gpu,
        "gpu_fast": any(k in gpu.lower() for k in ("nvidia", "geforce", "rtx", "gtx", "radeon rx")),
        "python": platform.python_version(),
    }


def human_hours(h: float) -> str:
    if h < 1 / 60:
        return "1분 이내"
    if h < 1:
        return f"약 {max(1, round(h * 60))}분"
    if h < 48:
        return f"약 {round(h, 1)}시간"
    return f"약 {round(h / 24, 1)}일"


def estimate(used_bytes: int, spec: dict | None = None, avg_file_mb: float = 3.0) -> dict:
    """예상 시간(대략). 사진 위주 하드를 기준으로 한다."""
    spec = spec or info()
    files = max(1, int(used_bytes / (avg_file_mb * 1024 * 1024)))
    cores = max(1, spec.get("cpu_cores", 1))
    list_rate = 1500.0  # 초당 파일(목록 단계)
    detail_rate = 40.0 * min(cores, 8) / 4  # 초당 파일(촬영 정보·문서 글자)
    face_rate = 25.0 if spec.get("gpu_fast") else 2.0 * min(cores, 8) / 4
    list_h = files / list_rate / 3600
    detail_h = files / detail_rate / 3600
    face_h = files * 0.8 / face_rate / 3600
    advice = []
    if spec.get("ram_gb", 0) and spec["ram_gb"] < 8:
        advice.append("메모리가 8GB보다 작아 느릴 수 있어요. 16GB를 권해요.")
    if not spec.get("gpu_fast"):
        advice.append("그래픽카드가 없어 얼굴·장면 인식이 오래 걸려요. 밤새 돌리기를 권해요.")
    if list_h + detail_h > 3:
        advice.append("처음 색인은 밤 시간에 돌리면 편해요.")
    return {
        "files_guess": files,
        "list": human_hours(list_h),
        "detail": human_hours(detail_h),
        "faces": human_hours(face_h),
        "total": human_hours(list_h + detail_h),
        "advice": advice,
    }
