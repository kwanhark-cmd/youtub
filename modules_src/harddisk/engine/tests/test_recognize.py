import numpy as np
import pytest
from fastapi.testclient import TestClient

from hdbiseo import recognize, samples
from hdbiseo.fakemodels import FakeFace, FakeScene  # noqa: E402


@pytest.fixture()
def rec_client(home, sample_dir, tmp_path):
    import shutil

    from hdbiseo import core, server

    server.register_extras()
    work = tmp_path / "하드"
    shutil.copytree(sample_dir / "사진", work / "사진")
    shutil.copytree(sample_dir / "소리", work / "소리")
    eng = core.get_engine("default")
    eng.recognizer.set_backends(FakeFace(), FakeScene())
    eng.add_root(str(work))
    eng.indexer.start()
    eng.indexer.join(120)
    assert eng.indexer.state["phase"] == "done", eng.indexer.state
    return TestClient(server.app), eng


def test_faces_grouped_named_and_searchable(rec_client):
    client, eng = rec_client
    people = client.get("/api/persons").json()
    biggest = next(p for p in people if any(i["name"] == "바닷가_아이들.jpg" for i in client.get(f"/api/persons/{p['id']}").json()["items"]))
    assert biggest["n"] == 2  # 바닷가 사진과 그 복사본 = 같은 사람
    r = client.post(f"/api/persons/{biggest['id']}", json={"name": "민수"})
    assert r.status_code == 200
    res = client.get("/api/search", params={"q": "민수 사진"}).json()
    assert {i["name"] for i in res["files"]["items"]} >= {"바닷가_아이들.jpg"}
    assert client.get(f"/api/faces/{biggest['cover_face_id']}/thumb").status_code == 200


def test_merge_two_persons(rec_client):
    client, eng = rec_client
    people = client.get("/api/persons").json()
    a, b = people[0], people[1]
    r = client.post("/api/persons/merge", json={"keep": a["id"], "merge": b["id"]})
    assert r.status_code == 200, r.text
    after = client.get("/api/persons").json()
    assert len(after) == len(people) - 1
    assert next(p for p in after if p["id"] == a["id"])["n"] == a["n"] + b["n"]
    assert client.post("/api/persons/merge", json={"keep": a["id"], "merge": a["id"]}).status_code == 400


def test_reject_face(rec_client):
    client, eng = rec_client
    p = client.get("/api/persons").json()[0]
    detail = client.get(f"/api/persons/{p['id']}").json()
    client.post(f"/api/faces/{detail['items'][0]['face_id']}/reject")
    assert client.get(f"/api/persons/{p['id']}").json()["total"] == p["n"] - 1


def test_scene_search_tags_and_collection_export(rec_client):
    client, eng = rec_client
    res = client.get("/api/search", params={"q": "바닷가 장면 찾아줘"}).json()
    names = {i["name"] for i in res["scenes"]["items"]}
    assert "바닷가_아이들.jpg" in names and "생일잔치.jpg" not in names
    sc = res["scenes"]["items"][0]
    info = client.get(f"/api/files/{sc['file_id']}").json()
    assert "바닷가" in info["tags"] or "바다" in info["tags"]
    col = client.post("/api/scene-collections", json={"name": "여름 바다"}).json()
    assert client.post(f"/api/scene-collections/{col['id']}/items", json={"scene_id": sc["id"]}).status_code == 200
    assert len(client.get(f"/api/scene-collections/{col['id']}").json()["items"]) == 1
    out = client.post(f"/api/scene-collections/{col['id']}/export").json()
    from pathlib import Path

    assert (Path(out["folder"]) / "장면목록.json").exists()


def test_voice_segments_found_and_named(rec_client):
    client, eng = rec_client
    v = client.get("/api/voices").json()
    assert v["unnamed"] == 3  # 1초 말하고 1초 쉬는 6초 소리 → 3구간
    vid = v["items"][0]["id"]
    assert client.post(f"/api/voices/{vid}", json={"name": "할머니"}).status_code == 200
    v2 = client.get("/api/voices").json()
    assert v2["groups"][0]["name"] == "할머니" and v2["unnamed"] == 2


def test_no_models_still_works(home, sample_dir):
    from hdbiseo import core, server

    server.register_extras()
    eng = core.get_engine("default")
    eng.recognizer.set_backends(None, None)
    client = TestClient(server.app)
    s = client.get("/api/recognition").json()
    assert s["faces"] is False and s["voices"] is True
    res = client.get("/api/search", params={"q": "비 오는 장면 찾아줘"}).json()
    assert res["scenes"]["notice"] and "꺼져" in res["scenes"]["notice"]


def test_speech_segments_silence():
    assert recognize.speech_segments(np.zeros(16000 * 3), 16000) == []


def test_sample_wav_segments(tmp_path):
    p = tmp_path / "a.wav"
    samples.speech_like_wav(p, 6)
    data, rate = recognize.read_audio(str(p), "audio")
    assert len(recognize.speech_segments(data, rate)) == 3
