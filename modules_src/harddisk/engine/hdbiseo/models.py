"""얼굴 모델 설치: '얼굴 인식 켜기' 버튼 한 번으로 내려받기 → 확인(sha256) → 제자리에 넣기.

기본 모델(상업 사용 가능):
- OpenCV YuNet 얼굴 찾기 (MIT 라이선스)
- OpenCV SFace 얼굴 비교 (Apache-2.0 라이선스)
인터넷이 막혀 있으면 같은 파일을 '파일 불러오기'로 넣을 수 있다(수동 설치).
"""

from __future__ import annotations

import hashlib
import io
import os
import urllib.request
import zipfile
from pathlib import Path

from . import settings as st

ZOO = "https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models"
SFACE_FILES = [
    {"name": "face_detection_yunet_2023mar.onnx", "url": f"{ZOO}/face_detection_yunet/face_detection_yunet_2023mar.onnx",
     "sha256": "8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4", "size": 232589, "license": "MIT"},
    {"name": "face_recognition_sface_2021dec.onnx", "url": f"{ZOO}/face_recognition_sface/face_recognition_sface_2021dec.onnx",
     "sha256": "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79", "size": 38696353, "license": "Apache-2.0"},
]
INFO = {
    "sface": {"title": "기본 모델 (OpenCV YuNet + SFace)", "license": "MIT · Apache-2.0", "commercial": True,
              "note": "개인 사용·판매 모두 가능한 공개 라이선스예요."},
    "insightface": {"title": "InsightFace buffalo_l", "license": "비상업 연구용", "commercial": False,
                    "note": "개인 사용용이에요. 판매하는 제품에 넣으려면 상업용 모델(기본 모델)로 바꿔야 해요."},
}


class ModelError(Exception):
    pass


def sface_dir() -> Path:
    d = st.app_home() / "models" / "opencv"
    d.mkdir(parents=True, exist_ok=True)
    return d


def insightface_dir() -> Path:
    return st.app_home() / "models" / "insightface" / "models" / "buffalo_l"


def status() -> dict:
    sf = [{"name": f["name"], "ok": (sface_dir() / f["name"]).exists()} for f in SFACE_FILES]
    try:
        import cv2  # noqa: F401
        cv_ok = True
    except ImportError:
        cv_ok = False
    return {"sface": {"files": sf, "installed": all(x["ok"] for x in sf), "runtime": cv_ok, **INFO["sface"]},
            "insightface": {"installed": insightface_dir().exists(), **INFO["insightface"]},
            "folder": str(st.app_home() / "models")}


def _verify_and_place(name: str, data: bytes) -> None:
    spec = next((f for f in SFACE_FILES if f["name"] == name), None)
    if spec is None:
        raise ModelError(f"모르는 모델 파일이에요: {name}")
    if hashlib.sha256(data).hexdigest() != spec["sha256"]:
        raise ModelError(f"'{name}' 파일이 손상되었거나 다른 파일이에요.")
    dest = sface_dir() / name
    tmp = dest.with_suffix(".part")
    tmp.write_bytes(data)  # 앱 자료 폴더(models)에 저장
    os.replace(tmp, dest)


def install(opener=None, progress: dict | None = None) -> dict:
    """기본 얼굴 모델 내려받기(약 39MB)."""
    opener = opener or urllib.request.urlopen
    for f in SFACE_FILES:
        if (sface_dir() / f["name"]).exists():
            continue
        req = urllib.request.Request(f["url"], headers={"User-Agent": "HDBiseo"})
        try:
            with opener(req, timeout=120) as r:
                buf = io.BytesIO()
                while True:
                    b = r.read(1024 * 256)
                    if not b:
                        break
                    buf.write(b)
                    if progress is not None:
                        progress[f["name"]] = buf.tell()
        except Exception as e:
            raise ModelError("모델을 내려받지 못했어요. 인터넷이 막혀 있으면 아래 '수동 설치'로 파일을 불러와 주세요.") from e
        _verify_and_place(f["name"], buf.getvalue())
    return status()


def import_file(filename: str, data: bytes) -> dict:
    """수동 설치: .onnx 파일 또는 그 파일들이 든 zip, InsightFace buffalo_l zip."""
    low = filename.lower()
    if low.endswith(".onnx"):
        _verify_and_place(os.path.basename(filename), data)
        return status()
    if low.endswith(".zip"):
        try:
            z = zipfile.ZipFile(io.BytesIO(data))
        except zipfile.BadZipFile as e:
            raise ModelError("zip 파일이 손상되었어요.") from e
        names = z.namelist()
        placed = 0
        for n in names:
            base = os.path.basename(n)
            if any(f["name"] == base for f in SFACE_FILES):
                _verify_and_place(base, z.read(n))
                placed += 1
        if not placed and any(n.endswith("w600k_r50.onnx") for n in names):
            d = insightface_dir()
            d.mkdir(parents=True, exist_ok=True)
            for n in names:
                if n.endswith(".onnx"):
                    (d / os.path.basename(n)).write_bytes(z.read(n))  # 앱 자료 폴더(models)에 저장
                    placed += 1
        if not placed:
            raise ModelError("zip 안에서 얼굴 모델 파일을 찾지 못했어요.")
        return status()
    raise ModelError("모델 파일(.onnx) 또는 zip 파일을 골라 주세요.")
