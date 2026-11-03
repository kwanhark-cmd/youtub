import sqlite3

import pytest

from hdbiseo import db


def test_migrate_old_version_with_backup(tmp_path):
    p = tmp_path / "index.db"
    c = db.connect(p)
    c.executescript(db.BASE_SCHEMA)
    c.executescript(db.MIGRATIONS[2])
    c.execute("INSERT INTO meta VALUES('schema_version','2')")
    c.execute("INSERT INTO files(root_id,path,dir,name) VALUES(1,'/a/b.jpg','/a','b.jpg')")
    c.commit()
    assert db.init(c) == db.SCHEMA_VERSION
    assert db.get_version(c) == db.SCHEMA_VERSION
    assert c.execute("SELECT COUNT(*) FROM files").fetchone()[0] == 1  # 자료 유지
    c.execute("SELECT * FROM records").fetchall()  # 새 표 생김
    assert list((tmp_path / "backups").glob("before_v*.db"))  # 변환 전 자동 백업


def test_newer_version_refused(tmp_path):
    c = db.connect(tmp_path / "x.db")
    db.init(c)
    c.execute("UPDATE meta SET value='999' WHERE key='schema_version'")
    c.commit()
    with pytest.raises(RuntimeError):
        db.init(c)


def test_restore_rejects_non_backup(tmp_path):
    bad = tmp_path / "bad.db"
    sqlite3.connect(bad).execute("CREATE TABLE x(a)")
    with pytest.raises(ValueError):
        db.restore(tmp_path / "index.db", bad)
