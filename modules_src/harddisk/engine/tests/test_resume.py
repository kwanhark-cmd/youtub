import datetime as dt
import shutil
import threading
import time

from hdbiseo import indexer as ix


def _copy(sample_dir, tmp_path):
    work = tmp_path / "하드1"
    shutil.copytree(sample_dir, work)
    return work


def test_stop_and_resume_continues(engine, sample_dir, tmp_path):
    work = _copy(sample_dir, tmp_path)
    engine.add_root(str(work))
    idx = engine.indexer
    orig = idx._apply_files
    calls = {"n": 0}

    def slow(*a, **k):
        calls["n"] += 1
        orig(*a, **k)
        if calls["n"] == 5:
            idx._stop.set()  # 전원이 꺼진 것처럼 중간에 멈춤

    idx._apply_files = slow
    idx.start()
    idx.join(60)
    assert idx.state["phase"] == "stopped"
    c = engine.conn()
    done_dirs = c.execute("SELECT COUNT(*) FROM scan_dirs").fetchone()[0]
    assert done_dirs == 5
    idx._apply_files = orig
    idx.start()
    idx.join(60)
    assert idx.state["phase"] == "done"
    assert idx.state["dirs_done"] < calls["n"] + 40  # 처음부터가 아니라 이어서
    total = sum(1 for p in work.rglob("*") if p.is_file())
    assert c.execute("SELECT COUNT(*) FROM files").fetchone()[0] == total


def test_drive_disconnect_and_reconnect(engine, sample_dir, tmp_path):
    work = _copy(sample_dir, tmp_path)
    away = tmp_path / "분리됨"
    engine.add_root(str(work))
    idx = engine.indexer
    idx.reconnect_wait = 2
    orig = idx._apply_files
    state = {"n": 0}

    def unplug(*a, **k):
        state["n"] += 1
        if state["n"] == 3:
            work.rename(away)  # 하드를 뽑은 상황
            threading.Timer(1.5, lambda: away.rename(work)).start()  # 다시 꽂음
        return orig(*a, **k)

    idx._apply_files = unplug
    seen = set()
    idx.start()
    t0 = time.time()
    while idx.is_running() and time.time() - t0 < 60:
        seen.add(idx.state["phase"])
        time.sleep(0.05)
    assert "disconnected" in seen
    assert idx.state["phase"] == "done"
    total = sum(1 for p in work.rglob("*") if p.is_file())
    assert engine.conn().execute("SELECT COUNT(*) FROM files").fetchone()[0] == total


def test_disconnected_root_files_not_removed(indexed, sample_dir, tmp_path):
    c = indexed.conn()
    before = c.execute("SELECT COUNT(*) FROM files").fetchone()[0]
    # 하드가 없는 상태에서 다시 색인해도 목록이 지워지지 않아야 한다
    c.execute("UPDATE roots SET path=?", (str(tmp_path / "없는하드"),))
    c.commit()
    indexed.indexer.reconnect_wait = 0.5
    indexed.indexer.start()
    time.sleep(1.5)
    indexed.indexer.stop()
    assert c.execute("SELECT COUNT(*) FROM files").fetchone()[0] == before
    assert indexed.roots()[0]["status"] == "disconnected"


def test_night_window():
    at = lambda h, m=0: dt.datetime(2026, 1, 1, h, m)  # noqa: E731
    assert ix.in_night_window(at(23, 30), "23:00", "06:00")
    assert ix.in_night_window(at(3), "23:00", "06:00")
    assert not ix.in_night_window(at(12), "23:00", "06:00")
    assert ix.in_night_window(at(2), "01:00", "05:00")
    assert not ix.in_night_window(at(6), "01:00", "05:00")


def test_night_only_waits(engine, sample_dir, monkeypatch, tmp_path):
    from hdbiseo import settings

    settings.save("default", {"night_only": True, "night_start": "00:00", "night_end": "00:01"})
    monkeypatch.setattr(ix, "in_night_window", lambda *a: False)
    engine.add_root(str(_copy(sample_dir, tmp_path)))
    engine.indexer.sleep = lambda s: time.sleep(0.05)
    engine.indexer.start()
    time.sleep(0.5)
    assert engine.indexer.state["waiting"] == "night"
    assert engine.conn().execute("SELECT COUNT(*) FROM files").fetchone()[0] == 0
    engine.indexer.stop()


def test_permission_denied_dir_is_skipped(engine, sample_dir, tmp_path, monkeypatch):
    work = _copy(sample_dir, tmp_path)
    locked = work / "잠긴폴더"
    locked.mkdir()
    (locked / "a.txt").write_text("x")
    real = ix.os.scandir

    def fake(p):
        if str(p).endswith("잠긴폴더"):
            raise PermissionError("denied")
        return real(p)

    monkeypatch.setattr(ix.os, "scandir", fake)
    engine.add_root(str(work))
    engine.indexer.start()
    engine.indexer.join(60)
    assert engine.indexer.state["phase"] == "done"
    r = engine.conn().execute("SELECT reason FROM unreadable WHERE path=?", (str(locked),)).fetchone()
    assert r and "권한" in r[0]
