import io
import json

import pytest
from fastapi.testclient import TestClient

from hdbiseo import ai, google, records


@pytest.fixture()
def client(home):
    from hdbiseo import server

    server.register_extras()
    return TestClient(server.app)


def _imp(client, kind, path):
    with open(path, "rb") as f:
        return client.post(f"/api/import/{kind}", files={"file": (path.name, f.read())})


def test_import_all_and_timeline(client, sample_dir):
    d = sample_dir / "내기록"
    r = _imp(client, "vcf", d / "연락처.vcf").json()
    assert r["added"] == 3, r
    r = _imp(client, "ics", d / "구글캘린더.ics").json()
    assert r["added"] == 3, r
    assert _imp(client, "ics", d / "구글캘린더.ics").json()["added"] == 0  # 두 번 가져와도 중복 없음
    r = _imp(client, "keep", d / "takeout-keep.zip").json()
    assert r["added"] == 2  # 휴지통 메모 제외
    r = client.post("/api/import/diary-folder", data={"path": str(sample_dir / "일기장")}).json()
    assert r["added"] == 1, r

    t = client.get("/api/records").json()
    assert t["total"] == 6 and {"event", "keep", "diary"} <= {i["kind"] for i in t["items"]}
    assert t["items"][0]["at"] >= t["items"][-1]["at"]  # 최신순
    diary = client.get("/api/records", params={"kinds": "diary"}).json()["items"][0]
    assert diary["at"].startswith("2005-08-15")  # 파일 이름의 날짜

    contacts = client.get("/api/contacts").json()["items"]
    names = {c["name"] for c in contacts}
    assert names == {"김철수", "이영희", "박감독"}  # 옛 형식(quoted-printable) 이름도
    kim = next(c for c in contacts if c["name"] == "김철수")
    assert kim["relation"] == "삼촌" and "010-1234-5678" in kim["phones"]

    # 기록에 이름이 나오면 연결 후보
    detail = client.get(f"/api/contacts/{kim['id']}").json()
    titles = {r["title"] for r in detail["records"]}
    assert "[신제품] 기획 회의" in titles and "2005-08-15 일기" in titles and "신제품 아이디어" in titles

    # 통합 검색에서 기록·연락처도 나옴
    res = client.get("/api/search", params={"q": "김철수"}).json()
    assert res["records"] and res["contacts"]


def test_link_confirm_reject_and_network(client, sample_dir):
    d = sample_dir / "내기록"
    _imp(client, "vcf", d / "연락처.vcf")
    _imp(client, "ics", d / "구글캘린더.ics")
    _imp(client, "keep", d / "takeout-keep.zip")
    projects = {p["name"]: p for p in client.get("/api/projects").json()}
    assert {"신제품", "가을동화", "집안일"} <= set(projects)
    net = client.get("/api/network").json()
    labels = {n["label"] for n in net["nodes"]}
    assert {"신제품", "김철수", "이영희", "가을동화", "박감독"} <= labels
    link = next(lk for lk in net["links"] if lk["status"] == "suggested")
    # 사용자가 '아니에요' → 지도에서 빠짐, 다시 연결해도 되살아나지 않음
    client.post(f"/api/projects/{link['project_id']}/people", json={"contact_id": link["contact_id"], "status": "rejected"})
    client.post("/api/records/relink")
    net2 = client.get("/api/network").json()
    assert not any(lk["project_id"] == link["project_id"] and lk["contact_id"] == link["contact_id"] for lk in net2["links"])
    # 기록의 사람 연결 확인
    rec = client.get("/api/records", params={"q": "기획 회의"}).json()["items"][0]
    det = client.get(f"/api/records/{rec['id']}").json()
    p = det["people"][0]
    assert p["status"] == "suggested"
    client.post(f"/api/records/{rec['id']}/people", json={"contact_id": p["id"], "status": "confirmed"})
    assert client.get(f"/api/records/{rec['id']}").json()["people"][0]["status"] == "confirmed"
    client.post(f"/api/records/{rec['id']}/people", json={"name": "최부장", "status": "confirmed"})
    assert any(x["name"] == "최부장" for x in client.get(f"/api/records/{rec['id']}").json()["people"])


def test_voice_diary(client):
    r = client.post("/api/records/voice-diary", data={"text": "오늘은 김철수 삼촌과 산책을 했다"}, files={"audio": ("a.webm", b"fake-audio")})
    assert r.status_code == 200
    t = client.get("/api/records", params={"kinds": "voice_diary"}).json()
    assert t["total"] == 1 and "산책" in t["items"][0]["body"]
    assert client.post("/api/records/voice-diary", data={"text": "  "}).status_code == 400


def test_diary_split_by_dates():
    text = "2024.1.1 새해 첫날\n떡국을 먹었다\n2024년 1월 2일\n출근했다"
    parts = records.split_diary(text, None)
    assert [p[0][:10] for p in parts] == ["2024-01-01", "2024-01-02"]


def test_ai_off_by_default_no_network(client, home, monkeypatch):
    called = []
    monkeypatch.setattr(ai.urllib.request, "urlopen", lambda *a, **k: called.append(1))
    r = client.post("/api/ai/summarize/1")
    assert r.status_code == 400 and "꺼져" in r.json()["error"]
    assert not called


def test_ai_summarize_with_fake_api_and_limit(engine, sample_dir):
    engine.add_root(str(sample_dir / "회사서류"))
    engine.indexer.start()
    engine.indexer.join(60)
    c = engine.conn()
    fid = c.execute("SELECT id FROM files WHERE name='계약서_2023.hwpx'").fetchone()[0]
    sent = {}

    class Resp(io.BytesIO):
        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

    def fake_open(req, timeout=0):
        sent["body"] = json.loads(req.data)
        sent["key"] = req.headers.get("X-api-key")
        return Resp(json.dumps({"content": [{"type": "text", "text": "계약금 5천만 원 계약서"}], "usage": {"input_tokens": 300, "output_tokens": 50}}).encode())

    s = {"ai_enabled": True, "ai_api_key": "k-1", "ai_monthly_limit_won": 5000, "ai_model": "m"}
    r = ai.summarize(c, s, fid, opener=fake_open)
    assert "계약금" in r["summary"] and sent["key"] == "k-1" and "오천만" in sent["body"]["messages"][0]["content"]
    with pytest.raises(ai.AIError):
        ai.summarize(c, dict(s, ai_monthly_limit_won=0), fid, opener=fake_open)


def test_google_sync_with_fake_api(engine):
    def fake_open(req, timeout=0):
        url = req.full_url

        class R(io.BytesIO):
            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

        if "calendar" in url:
            return R(json.dumps({"items": [{"id": "g1", "summary": "가족 여행", "start": {"date": "2024-07-01"}, "attendees": [{"displayName": "엄마"}]}]}).encode())
        return R(json.dumps({"connections": [{"resourceName": "people/1", "names": [{"displayName": "엄마"}], "phoneNumbers": [{"value": "010-1"}],
                                              "relations": [{"type": "mother"}]}]}).encode())

    s = {"google_token": {"access_token": "t", "expires_at": 9e18}, "google_client_id": "x", "google_client_secret": "y"}
    res = google.sync(engine.conn(), s, lambda v: None, opener=fake_open)
    assert res == {"events": 1, "contacts": 1}
    c = engine.conn()
    assert c.execute("SELECT COUNT(*) FROM record_people").fetchone()[0] == 1  # '엄마'가 일정 참석자에 나옴
    assert "accounts.google.com" in google.auth_url("cid", "http://127.0.0.1:47810/api/google/callback", "s")
    with pytest.raises(google.GoogleError):
        google.auth_url("", "u", "s")


def test_stray_carriage_returns_tolerated(engine):
    """윈도우에서 줄바꿈이 두 번 바뀐 파일(\\r\\r\\n)도 읽어야 한다."""
    c = engine.conn()
    vcf = "BEGIN:VCARD\r\r\nFN:홍길동\r\r\nTEL:010-0000-0000\r\r\nEND:VCARD\r\r\n"
    assert records.import_vcf(c, vcf)["added"] == 1
    ics = "BEGIN:VCALENDAR\r\r\nBEGIN:VEVENT\r\r\nUID:x1\r\r\nSUMMARY:《작품》 회의\r\r\nDTSTART:20240101T100000\r\r\nEND:VEVENT\r\r\nEND:VCALENDAR\r\r\n"
    assert records.import_ics(c, ics)["added"] == 1
