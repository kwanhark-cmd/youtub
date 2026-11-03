import time

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def client(home):
    from hdbiseo import server

    server.register_extras()
    return TestClient(server.app)


def wait_done(client, timeout=60):
    t0 = time.time()
    while time.time() - t0 < timeout:
        s = client.get("/api/index/status").json()
        if not s["running"] and s["state"]["phase"] in ("done", "error", "stopped"):
            return s
        time.sleep(0.2)
    raise AssertionError("색인이 끝나지 않음")


def test_full_flow(client, sample_dir):
    assert client.get("/api/health").json()["ok"]
    r = client.post("/api/index/start", json={})
    assert r.status_code == 400 and "골라" in r.json()["error"]
    r = client.post("/api/roots", json={"path": str(sample_dir), "excluded": [str(sample_dir / "제외할폴더")]})
    assert r.status_code == 200, r.text
    assert client.post("/api/roots", json={"path": str(sample_dir)}).status_code == 400
    client.post("/api/index/start", json={})
    s = wait_done(client)
    assert s["state"]["phase"] == "done" and s["overview"]["total"] > 20

    r = client.get("/api/search", params={"q": "계약서"}).json()
    assert r["files"]["total"] >= 2
    r = client.get("/api/search", params={"q": "계약금 들어간 문서 찾아줘"}).json()
    assert r["content"]["total"] >= 4 and "찾았어요" in r["speech"]
    r = client.get("/api/search", params={"q": "2005년 아이들 영상 찾아줘"}).json()
    assert any(i["name"] == "2005_가족여행.mp4" for i in r["files"]["items"])

    years = client.get("/api/timeline/years").json()
    assert any(y["year"] == 2005 for y in years)
    months = client.get("/api/timeline/months", params={"year": 2005}).json()
    assert {m["month"] for m in months} >= {5, 8}
    items = client.get("/api/timeline/items", params={"year": 2005, "month": 8}).json()
    fid = next(i["id"] for i in items["items"] if i["kind"] == "image")
    th = client.get(f"/api/files/{fid}/thumb")
    assert th.status_code == 200 and th.headers["content-type"] == "image/jpeg"
    assert client.get(f"/api/files/{fid}/raw").status_code == 200
    mem = client.get("/api/memories").json()
    assert mem and mem[0]["years_ago"] == 3
    assert any(p["place"] == "속초" for p in client.get("/api/places").json())
    assert client.get("/api/today").json()["type"] == "memory"

    # 음성 메모
    assert client.post(f"/api/files/{fid}/notes", json={"text": "속초 여름휴가", "voice": True}).status_code == 200
    r = client.get("/api/search", params={"q": "여름휴가"}).json()
    assert any(i["id"] == fid for i in r["files"]["items"])

    un = client.get("/api/unreadable").json()
    assert un["total"] >= 3


def test_settings_validation_and_secret_masking(client):
    r = client.post("/api/settings", json={"font_scale": 2, "theme": "dark", "ai_api_key": "sk-test-123"})
    assert r.status_code == 200
    d = r.json()
    assert d["font_scale"] == 2 and d["ai_api_key"] == "********"
    assert client.post("/api/settings", json={"font_scale": 9}).status_code == 400
    assert client.post("/api/settings", json={"night_start": "25:00"}).status_code == 400
    # 가려진 값을 그대로 보내도 키가 지워지지 않아야 함
    client.post("/api/settings", json={"ai_api_key": "********"})
    from hdbiseo import settings

    assert settings.load("default")["ai_api_key"] == "sk-test-123"


def test_users_are_separate(client, sample_dir):
    u = client.post("/api/users", json={"name": "엄마"}).json()
    client.post("/api/roots", json={"path": str(sample_dir)})
    assert len(client.get("/api/roots").json()) == 1
    assert client.get("/api/roots", headers={"x-hd-user": u["id"]}).json() == []


def test_backup_restore_reset(client, sample_dir):
    client.post("/api/roots", json={"path": str(sample_dir)})
    client.post("/api/index/start", json={})
    wait_done(client)
    total = client.get("/api/index/status").json()["overview"]["total"]
    b = client.post("/api/backup").json()
    assert b["ok"]
    assert client.post("/api/reset", json={"confirm1": True}).status_code == 400
    r = client.post("/api/reset", json={"confirm1": True, "confirm2": "초기화"})
    assert r.status_code == 200
    assert client.get("/api/index/status").json()["overview"]["total"] == 0
    assert sample_dir.exists() and any(sample_dir.iterdir())  # 원본 그대로
    r = client.post("/api/restore", json={"file": b["file"]})
    assert r.status_code == 200, r.text
    assert client.get("/api/index/status").json()["overview"]["total"] == total


def test_duplicates_and_trash_confirm(client, sample_dir, tmp_path):
    import shutil

    work = tmp_path / "dups"
    shutil.copytree(sample_dir / "사진", work)
    client.post("/api/roots", json={"path": str(work)})
    client.post("/api/index/start", json={})
    wait_done(client)
    client.post("/api/duplicates/scan")
    for _ in range(100):
        d = client.get("/api/duplicates").json()
        if not d["state"]["running"]:
            break
        time.sleep(0.1)
    assert d["total"] == 1 and d["items"][0]["count"] == 2
    victim = d["items"][0]["files"][1]
    r = client.post(f"/api/files/{victim['id']}/trash", json={})
    assert r.status_code == 400 and "확인" in r.json()["error"]
    assert (work / victim["path"].split(str(work))[1].lstrip("/\\")).exists()


def test_trash_moves_to_os_trash(client, tmp_path, monkeypatch):
    from hdbiseo import trash

    moved = []
    monkeypatch.setattr(trash, "send2trash", lambda p: moved.append(p))
    d = tmp_path / "t"
    d.mkdir()
    (d / "a.txt").write_text("x")
    client.post("/api/roots", json={"path": str(d)})
    client.post("/api/index/start", json={})
    wait_done(client)
    fid = client.get("/api/search", params={"q": "a.txt"}).json()["files"]["items"][0]["id"]
    r = client.post(f"/api/files/{fid}/trash", json={"confirm": True})
    assert r.status_code == 200 and moved == [str(d / "a.txt")]
    assert "되살릴" in r.json()["message"]


def test_lan_guard(client, home, monkeypatch):
    from hdbiseo import server, settings

    monkeypatch.setattr(server, "_is_local", lambda req: False)  # 다른 기기에서 온 요청처럼
    remote = client
    assert remote.get("/api/roots").status_code == 403
    settings.save_app_config({"lan_enabled": True, "pair_code": "123456"})
    r = remote.get("/api/roots")
    assert r.status_code == 401 and r.json()["need_pair"]
    assert remote.post("/api/pair", json={"code": "000000"}).status_code == 401
    tok = remote.post("/api/pair", json={"code": "123456"}).json()["token"]
    assert remote.get("/api/roots", headers={"x-hd-token": tok}).status_code == 200
    assert remote.get("/api/lan", headers={"x-hd-token": tok}).status_code == 403


def test_report_has_no_contents(client, sample_dir):
    import io
    import zipfile

    client.post("/api/roots", json={"path": str(sample_dir)})
    client.post("/api/index/start", json={})
    wait_done(client)
    r = client.get("/api/report")
    z = zipfile.ZipFile(io.BytesIO(r.content))
    blob = b"".join(z.read(n) for n in z.namelist()).decode("utf-8", "ignore")
    for secret in ("오천만", "비밀번호", "김철수"):
        assert secret not in blob


def test_browse_and_estimate(client, sample_dir):
    r = client.get("/api/browse", params={"path": str(sample_dir)}).json()
    assert any(d["name"] == "사진" for d in r["dirs"])
    e = client.get("/api/estimate", params={"path": str(sample_dir)}).json()
    assert "total" in e
    s = client.get("/api/system").json()
    assert s["spec"]["cpu_cores"] >= 1


def test_log_masks_keys_and_contacts(tmp_path):
    import logging

    from hdbiseo.applog import PrivacyFilter

    r = logging.LogRecord("x", logging.ERROR, "", 0, "키 sk-ant-api03-abcdefghijklmnop 비밀 GOCSPX-abc123 번호 010-1234-5678 메일 a@b.com", (), None)
    PrivacyFilter().filter(r)
    m = r.getMessage()
    assert "sk-ant" not in m and "GOCSPX" not in m and "010-1234" not in m and "a@b.com" not in m


def test_errors_logged_with_stage(client, caplog):
    import logging

    with caplog.at_level(logging.ERROR, logger="hdbiseo.server"):
        r = client.get("/api/browse", params={"path": "/없는/폴더"})
    assert r.status_code == 400 and r.json()["stage"]
    assert any("[" in rec.getMessage() and "/api/browse" in rec.getMessage() for rec in caplog.records)


def test_sample_root_hidden_when_real_root_added(client, home, sample_dir):
    s = client.post("/api/samples", json={}).json()
    client.post("/api/roots", json={"path": s["path"]})
    st = client.get("/api/status").json()
    assert st["index"]["sample_roots"] == 1 and st["index"]["real_roots"] == 0
    client.post("/api/roots", json={"path": str(sample_dir)})
    roots = client.get("/api/roots").json()
    assert len(roots) == 1 and not roots[0]["sample"]
    st = client.get("/api/status").json()
    assert st["index"]["real_roots"] == 1 and st["faces"]["on"] in (True, False) and "google" in st


def test_branding_name_icon_palette(client):
    import io

    from PIL import Image

    r = client.get("/api/branding/icon.png")
    assert r.status_code == 200 and Image.open(io.BytesIO(r.content)).size == (256, 256)
    assert client.get("/api/branding/icon.ico").headers["content-type"] == "image/x-icon"
    client.post("/api/settings", json={"app_name": "우리집 자료", "palette": "pink", "app_icon": "camera"})
    m = client.get("/manifest.webmanifest").json()
    assert m["name"] == "우리집 자료" and m["theme_color"] == "#be185d"
    assert client.post("/api/settings", json={"palette": "rainbow"}).status_code == 400
    buf = io.BytesIO()
    Image.new("RGB", (400, 300), (10, 200, 30)).save(buf, "JPEG")
    r = client.post("/api/branding/icon", files={"file": ("me.jpg", buf.getvalue())})
    assert r.status_code == 200 and client.get("/api/settings").json()["app_icon"] == "custom"
    px = Image.open(io.BytesIO(client.get("/api/branding/icon.png").content)).convert("RGB").getpixel((128, 128))
    assert px[1] > 150  # 초록 사진이 아이콘이 됨
    assert client.post("/api/branding/icon", files={"file": ("x.txt", b"not image")}).status_code == 400


def test_tray_tooltip(engine):
    from hdbiseo import tray

    assert "쉬는 중" in tray.tooltip([engine])
    engine.indexer.state.update(percent=42)
    engine.indexer.is_running = lambda: True
    assert "42%" in tray.tooltip([engine])
