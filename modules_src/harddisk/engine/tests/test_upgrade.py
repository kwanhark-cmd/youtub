"""업그레이드 시험: v1.0.0으로 만든 색인·설정 위에 새 버전을 올려도 모두 남아 있는가."""

import json
import shutil
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

FIX = Path(__file__).parent / "fixtures" / "v1.0.0"


@pytest.fixture()
def old_home(tmp_path, monkeypatch):
    home = tmp_path / "apphome"
    shutil.copytree(FIX, home)
    monkeypatch.setenv("HDBISEO_HOME", str(home))
    from hdbiseo import core, server

    core.reset_engines()
    server.register_extras()
    yield home
    core.reset_engines()


def test_old_index_and_settings_survive_upgrade(old_home):
    from hdbiseo import VERSION, server
    from hdbiseo import db as dbm

    before = dbm.connect(old_home / "users/default/index.db")
    old_ver = dbm.get_version(before)
    old_files = before.execute("SELECT COUNT(*), SUM(detail_status='done'), MAX(indexed_at) FROM files").fetchone()
    old_gen = before.execute("SELECT generation FROM roots").fetchone()[0]
    before.close()
    assert old_ver == 5 and VERSION != "1.0.0"

    c = TestClient(server.app)
    # 자동 변환 + 변환 전 자동 백업, 다시 분석하지 않음
    con = dbm.connect(old_home / "users/default/index.db")
    assert dbm.get_version(con) == 5  # 아직 열지 않음
    s = c.get("/api/settings").json()
    assert dbm.get_version(con) == dbm.SCHEMA_VERSION
    assert list((old_home / "users/default/backups").glob("before_v*.db"))
    now = con.execute("SELECT COUNT(*), SUM(detail_status='done'), MAX(indexed_at) FROM files").fetchone()
    assert tuple(now) == tuple(old_files)
    assert con.execute("SELECT generation FROM roots").fetchone()[0] == old_gen
    st = c.get("/api/index/status").json()
    assert not st["running"]  # 업데이트 뒤 저절로 다시 분석하지 않음

    # 설정 그대로(글씨·화면·키·구글·다른 기기), 마법사 건너뜀
    assert s["first_run_done"] is True and s["font_scale"] == 2 and s["theme"] == "dark" and s["night_only"] is True
    assert s["ai_api_key"] == "********" and s["google_client_id"].startswith("fixture-id")
    assert json.loads((old_home / "app.json").read_text())["pair_code"] == "123456"

    # 검색·얼굴 이름·메모·연락처·인맥 그대로
    assert c.get("/api/search", params={"q": "계약서"}).json()["files"]["total"] >= 2
    assert c.get("/api/search", params={"q": "계약금 들어간 문서"}).json()["content"]["total"] >= 4
    r = c.get("/api/search", params={"q": "민수 사진"}).json()
    assert any(i["name"] == "바닷가_아이들.jpg" for i in r["files"]["items"])
    assert any(p["name"] == "민수" for p in c.get("/api/persons").json())
    r = c.get("/api/search", params={"q": "케이크를"}).json()
    assert any(i["name"] == "생일잔치.jpg" for i in r["files"]["items"])
    contacts = {x["name"]: x for x in c.get("/api/contacts").json()["items"]}
    assert contacts["이영희"]["relation"] == "회사 동료"
    net = c.get("/api/network").json()
    assert any(lk["status"] == "confirmed" for lk in net["links"])


def test_update_check_and_install_guard(old_home, monkeypatch):
    import io

    from hdbiseo import core, server, update

    class R(io.BytesIO):
        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

    rel = {"tag_name": "v9.9.9", "body": "## 바뀐 점\n- 좋아짐", "html_url": "https://github.com/x/y/releases/v9.9.9",
           "assets": [{"name": "HDBiseo-Setup-9.9.9.exe", "browser_download_url": "https://example/setup.exe", "size": 10,
                       "digest": "sha256:" + __import__("hashlib").sha256(b"0123456789").hexdigest()},
                      {"name": "HDBiseo-9.9.9.dmg", "browser_download_url": "https://example/a.dmg"},
                      {"name": "app-debug.apk", "browser_download_url": "https://example/a.apk"}]}
    monkeypatch.setattr(update.urllib.request, "urlopen", lambda req, timeout=0: R(json.dumps(rel).encode()) if "api.github" in req.full_url else R(b"0123456789"))
    c = TestClient(server.app)
    info = c.get("/api/update/check").json()
    assert info["newer"] and info["latest"] == "9.9.9" and set(info["assets"]) == {"windows", "mac", "android"}
    # 분석 중이면 설치를 막음
    eng = core.get_engine("default")
    monkeypatch.setattr(eng.indexer, "is_running", lambda: True)
    r = c.post("/api/update/install")
    assert r.status_code == 409 and "분석이 끝난 뒤" in r.json()["error"]
    monkeypatch.setattr(eng.indexer, "is_running", lambda: False)
    ran = []
    monkeypatch.setattr(update, "run_installer", lambda p: ran.append(p))
    r = c.post("/api/update/install")
    assert r.status_code == 200, r.text
    assert ran and ran[0].read_bytes() == b"0123456789"
    # 설치 전 백업: 설정·인물 정보만(색인 제외)
    import zipfile

    z = zipfile.ZipFile(old_home / "backups" / r.json()["backup"])
    names = z.namelist()
    assert "users/default/settings.json" in names and "users/default/people.json" in names
    assert not any(n.endswith("index.db") for n in names)
    people = json.loads(z.read("users/default/people.json"))
    assert any(p["name"] == "민수" for p in people["persons"])
    # 손상된 내려받기는 거절
    rel["assets"][0]["digest"] = "sha256:00"
    with pytest.raises(update.UpdateError):
        update.download(update.check()["assets"]["windows"])


def test_move_data_location(old_home, tmp_path):
    from hdbiseo import server
    from hdbiseo import settings as st

    c = TestClient(server.app)
    assert c.get("/api/data-location").json()["home"] == str(old_home)
    new = tmp_path / "D드라이브" / "하드비서자료"
    r = c.post("/api/data-location", json={"path": str(new)})
    assert r.status_code == 200, r.text
    assert st.app_home() == new.resolve()
    assert (old_home / "users/default/index.db").exists()  # 원래 자료는 지우지 않음
    assert any(p["name"] == "민수" for p in c.get("/api/persons").json())
    assert c.post("/api/data-location", json={"path": str(new)}).status_code == 400


def test_versions_match():
    from hdbiseo import VERSION

    root = Path(__file__).resolve().parents[2]
    assert f'App.version = "{VERSION}"' in (root / "web/js/core.js").read_text(encoding="utf-8")
    assert f'#define MyAppVersion "{VERSION}"' in (root / "installer.iss").read_text(encoding="utf-8")
    assert json.loads((root / "desktop/package.json").read_text(encoding="utf-8"))["version"] == VERSION
    assert f"## {VERSION}" in (root / "CHANGELOG.md").read_text(encoding="utf-8")
