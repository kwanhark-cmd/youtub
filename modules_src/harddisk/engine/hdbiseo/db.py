"""색인 데이터베이스(SQLite). 원본 파일은 건드리지 않고 목록만 저장한다.

- 색인 데이터 버전(SCHEMA_VERSION)과 자동 변환(MIGRATIONS)
- WAL 모드로 수시 저장 → 전원이 꺼져도 처음부터 다시 하지 않음
- 백업·복원·초기화
"""

from __future__ import annotations

import shutil
import sqlite3
import time
from pathlib import Path

SCHEMA_VERSION = 6

BASE_SCHEMA = """
CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);

CREATE TABLE IF NOT EXISTS roots(
  id INTEGER PRIMARY KEY,
  path TEXT UNIQUE NOT NULL,
  label TEXT,
  excluded TEXT DEFAULT '[]',
  enabled INTEGER DEFAULT 1,
  status TEXT DEFAULT 'idle',
  generation INTEGER DEFAULT 0,
  scanning_generation INTEGER DEFAULT 0,
  files_count INTEGER DEFAULT 0,
  last_scan_started TEXT,
  last_scan_done TEXT
);

CREATE TABLE IF NOT EXISTS files(
  id INTEGER PRIMARY KEY,
  root_id INTEGER NOT NULL,
  path TEXT UNIQUE NOT NULL,
  dir TEXT NOT NULL,
  name TEXT NOT NULL,
  ext TEXT,
  kind TEXT,
  size INTEGER,
  mtime REAL,
  taken_at TEXT,
  taken_year INTEGER,
  taken_month INTEGER,
  taken_day INTEGER,
  lat REAL,
  lon REAL,
  place TEXT,
  width INTEGER,
  height INTEGER,
  duration REAL,
  hash TEXT,
  generation INTEGER DEFAULT 0,
  detail_status TEXT DEFAULT 'pending',
  content_status TEXT DEFAULT 'none',
  face_status TEXT DEFAULT 'pending',
  scene_status TEXT DEFAULT 'pending',
  indexed_at TEXT
);
CREATE INDEX IF NOT EXISTS ix_files_root ON files(root_id);
CREATE INDEX IF NOT EXISTS ix_files_kind_taken ON files(kind, taken_at);
CREATE INDEX IF NOT EXISTS ix_files_taken_md ON files(taken_month, taken_day);
CREATE INDEX IF NOT EXISTS ix_files_size ON files(size);
CREATE INDEX IF NOT EXISTS ix_files_mtime ON files(mtime);
CREATE INDEX IF NOT EXISTS ix_files_detail ON files(detail_status);
CREATE INDEX IF NOT EXISTS ix_files_dir ON files(dir);

CREATE VIRTUAL TABLE IF NOT EXISTS names_fts USING fts5(name, dir, tokenize='trigram');
CREATE VIRTUAL TABLE IF NOT EXISTS content_fts USING fts5(body, tokenize='trigram');

CREATE TABLE IF NOT EXISTS unreadable(
  id INTEGER PRIMARY KEY,
  path TEXT UNIQUE,
  reason TEXT,
  stage TEXT,
  at TEXT
);

CREATE TABLE IF NOT EXISTS scan_dirs(
  root_id INTEGER, path TEXT, generation INTEGER,
  PRIMARY KEY(root_id, path)
);

CREATE TABLE IF NOT EXISTS notes(
  id INTEGER PRIMARY KEY,
  file_id INTEGER,
  text TEXT,
  source TEXT,
  created_at TEXT
);
CREATE INDEX IF NOT EXISTS ix_notes_file ON notes(file_id);
"""

# 버전별 자동 변환. 키 = 변환 후 버전
MIGRATIONS: dict[int, str] = {
    2: """
CREATE TABLE IF NOT EXISTS persons(
  id INTEGER PRIMARY KEY, name TEXT, cover_face_id INTEGER,
  hidden INTEGER DEFAULT 0, created_at TEXT
);
CREATE TABLE IF NOT EXISTS faces(
  id INTEGER PRIMARY KEY, file_id INTEGER, t REAL DEFAULT 0,
  bbox TEXT, embedding BLOB, person_id INTEGER, confirmed INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS ix_faces_person ON faces(person_id);
CREATE INDEX IF NOT EXISTS ix_faces_file ON faces(file_id);
CREATE TABLE IF NOT EXISTS scenes(
  id INTEGER PRIMARY KEY, file_id INTEGER, t_start REAL, t_end REAL,
  tags TEXT, embedding BLOB
);
CREATE INDEX IF NOT EXISTS ix_scenes_file ON scenes(file_id);
CREATE VIRTUAL TABLE IF NOT EXISTS scenes_fts USING fts5(tags, tokenize='trigram');
CREATE TABLE IF NOT EXISTS scene_collections(id INTEGER PRIMARY KEY, name TEXT, created_at TEXT);
CREATE TABLE IF NOT EXISTS scene_collection_items(collection_id INTEGER, scene_id INTEGER,
  PRIMARY KEY(collection_id, scene_id));
CREATE TABLE IF NOT EXISTS voice_segments(
  id INTEGER PRIMARY KEY, file_id INTEGER, t_start REAL, t_end REAL,
  person_id INTEGER, embedding BLOB
);
""",
    3: """
CREATE TABLE IF NOT EXISTS records(
  id INTEGER PRIMARY KEY,
  kind TEXT, title TEXT, body TEXT, at TEXT, end_at TEXT,
  source TEXT, source_id TEXT, file_id INTEGER, created_at TEXT,
  UNIQUE(source, source_id)
);
CREATE INDEX IF NOT EXISTS ix_records_at ON records(at);
CREATE VIRTUAL TABLE IF NOT EXISTS records_fts USING fts5(title, body, tokenize='trigram');
CREATE TABLE IF NOT EXISTS contacts(
  id INTEGER PRIMARY KEY, name TEXT, phones TEXT DEFAULT '[]', emails TEXT DEFAULT '[]',
  relation TEXT, saved_at TEXT, source TEXT, source_id TEXT, memo TEXT,
  person_id INTEGER,
  UNIQUE(source, source_id)
);
CREATE TABLE IF NOT EXISTS record_people(
  record_id INTEGER, contact_id INTEGER, status TEXT DEFAULT 'suggested',
  PRIMARY KEY(record_id, contact_id)
);
CREATE TABLE IF NOT EXISTS projects(
  id INTEGER PRIMARY KEY, name TEXT UNIQUE, source TEXT, created_at TEXT
);
CREATE TABLE IF NOT EXISTS project_people(
  project_id INTEGER, contact_id INTEGER, status TEXT DEFAULT 'suggested',
  PRIMARY KEY(project_id, contact_id)
);
CREATE TABLE IF NOT EXISTS ai_usage(month TEXT PRIMARY KEY, calls INTEGER, cost_won REAL);
""",
    4: """
CREATE INDEX IF NOT EXISTS ix_files_year_kind ON files(taken_year, kind, taken_at);
CREATE INDEX IF NOT EXISTS ix_files_kind_size ON files(kind, size);
ANALYZE;
""",
    5: """
CREATE TABLE IF NOT EXISTS project_records(project_id INTEGER, record_id INTEGER, PRIMARY KEY(project_id, record_id));
""",
    6: """
CREATE INDEX IF NOT EXISTS ix_faces_person_conf ON faces(person_id, confirmed);
CREATE INDEX IF NOT EXISTS ix_record_people_contact ON record_people(contact_id, status);
CREATE INDEX IF NOT EXISTS ix_records_kind_at ON records(kind, at);
""",
}


def now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def connect(path: Path | str) -> sqlite3.Connection:
    conn = sqlite3.connect(str(path), timeout=30, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA foreign_keys=OFF")
    conn.execute("PRAGMA busy_timeout=30000")
    return conn


def get_version(conn: sqlite3.Connection) -> int:
    try:
        row = conn.execute("SELECT value FROM meta WHERE key='schema_version'").fetchone()
    except sqlite3.OperationalError:
        return 0
    return int(row[0]) if row else 0


def init(conn: sqlite3.Connection) -> int:
    """스키마를 만들고, 옛 버전이면 자동 변환한다. 변환 전 자동 백업."""
    current = get_version(conn)
    if current > SCHEMA_VERSION:
        raise RuntimeError("이 색인은 더 새로운 버전의 프로그램에서 만들어졌어요. 프로그램을 업데이트해 주세요.")
    if 0 < current < SCHEMA_VERSION:
        db_file = conn.execute("PRAGMA database_list").fetchone()[2]
        if db_file:
            backup(conn, Path(db_file).parent / "backups" / f"before_v{SCHEMA_VERSION}_{int(time.time())}.db")
    conn.executescript(BASE_SCHEMA)
    for ver in sorted(MIGRATIONS):
        if ver > max(current, 1):
            conn.executescript(MIGRATIONS[ver])
    conn.execute(
        "INSERT INTO meta(key,value) VALUES('schema_version',?) "
        "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        (str(SCHEMA_VERSION),),
    )
    conn.commit()
    return SCHEMA_VERSION


def backup(conn: sqlite3.Connection, dest: Path) -> Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    target = sqlite3.connect(str(dest))
    with target:
        conn.backup(target)
    target.close()
    return dest


def restore(db_path: Path, src: Path) -> None:
    """백업 파일을 확인한 뒤 현재 색인을 교체한다. 기존 색인은 따로 보관."""
    test = sqlite3.connect(str(src))
    try:
        ver = get_version(test)
        test.execute("PRAGMA integrity_check").fetchone()
    finally:
        test.close()
    if ver == 0:
        raise ValueError("올바른 백업 파일이 아니에요.")
    if db_path.exists():
        keep = db_path.parent / "backups" / f"replaced_{int(time.time())}.db"
        keep.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(db_path, keep)
    for suffix in ("-wal", "-shm"):
        p = Path(str(db_path) + suffix)
        if p.exists():
            p.unlink()
    shutil.copy2(src, db_path)
