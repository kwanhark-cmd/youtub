"""얼굴 모델 설치·불러오기·교체, 구글 JSON 불러오기."""

import hashlib
import io
import json
import os
import zipfile
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from hdbiseo import models

REAL = Path(os.environ.get("HDBISEO_TEST_MODELS", "/nonexistent"))


@pytest.fixture()
def client(home):
    from hdbiseo import server

    server.register_extras()
    return TestClient(server.app)


def test_status_and_license_flags(client):
    s = client.get("/api/models").json()
    assert s["sface"]["commercial"] is True and s["insightface"]["commercial"] is False
    assert "판매" in s["insightface"]["note"] and s["choice"] == "sface"


def test_install_with_fake_download_verifies_checksum(home, monkeypatch):
    fake = {f["url"]: f"model-{f['name']}".encode() for f in models.SFACE_FILES}
    patched = [dict(f, sha256=hashlib.sha256(fake[f["url"]]).hexdigest()) for f in models.SFACE_FILES]
    monkeypatch.setattr(models, "SFACE_FILES", patched)

    class R(io.BytesIO):
        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

    st = models.install(opener=lambda req, timeout=0: R(fake[req.full_url]))
    assert st["sface"]["installed"]
    # 손상 파일은 거절
    with pytest.raises(models.ModelError):
        models.import_file(patched[0]["name"], b"broken")


def test_import_zip_and_wrong_file(home, monkeypatch):
    data = b"onnx-bytes"
    patched = [dict(f, sha256=hashlib.sha256(data).hexdigest()) for f in models.SFACE_FILES]
    monkeypatch.setattr(models, "SFACE_FILES", patched)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for f in patched:
            z.writestr("받은파일/" + f["name"], data)
    assert models.import_file("models.zip", buf.getvalue())["sface"]["installed"]
    with pytest.raises(models.ModelError):
        models.import_file("사진.jpg", b"x")


def test_google_json_import(client):
    good = {"installed": {"client_id": "123-abc.apps.googleusercontent.com", "client_secret": "GOCSPX-xyz", "redirect_uris": ["http://localhost"]}}
    r = client.post("/api/google/client-json", files={"file": ("client_secret.json", json.dumps(good).encode())})
    assert r.status_code == 200
    s = client.get("/api/settings").json()
    assert s["google_client_id"].startswith("123-abc") and s["google_client_secret"] == "********"
    web = {"web": {"client_id": "x", "client_secret": "y"}}
    r = client.post("/api/google/client-json", files={"file": ("c.json", json.dumps(web).encode())})
    assert r.status_code == 400 and "데스크톱 앱" in r.json()["error"]
    assert client.post("/api/google/client-json", files={"file": ("c.json", b"not json")}).status_code == 400


@pytest.mark.skipif(not (REAL / "face_recognition_sface_2021dec.onnx").exists(), reason="실제 얼굴 모델이 있을 때만(GitHub Actions에서 내려받아 시험)")
def test_real_sface_model(home):
    import shutil

    import numpy as np
    from PIL import Image

    from hdbiseo import recognize

    for f in models.SFACE_FILES:
        shutil.copy(REAL / f["name"], models.sface_dir() / f["name"])
    b = recognize.SFaceBackend()
    face = np.asarray(Image.open(os.environ["HDBISEO_TEST_FACE"]).convert("RGB"))
    a = b.detect(face)
    m = b.detect(face[:, ::-1].copy())
    assert len(a) == 1 and len(m) == 1
    assert float(np.dot(a[0][1], m[0][1])) > b.match  # 같은 사람
    assert b.detect(np.zeros((200, 200, 3), dtype=np.uint8)) == []  # 얼굴 없는 그림
