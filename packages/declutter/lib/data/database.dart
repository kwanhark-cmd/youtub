import 'package:sqflite_common/sqlite_api.dart';

/// 데이터 버전. 올릴 때마다 _migrations 에 변환 단계를 추가합니다.
const int dataVersion = 3;

const _v1 = [
  '''CREATE TABLE users(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    created_at INTEGER NOT NULL)''',
  '''CREATE TABLE settings(
    user_id INTEGER NOT NULL,
    key TEXT NOT NULL,
    value TEXT,
    PRIMARY KEY(user_id, key))''',
  '''CREATE TABLE items(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    kind TEXT, condition TEXT, room TEXT, spot TEXT, tags TEXT,
    description TEXT, story TEXT,
    photo_path TEXT, thumb_path TEXT, original_path TEXT,
    source TEXT,
    decision TEXT, ai_suggestion TEXT, ai_reason TEXT,
    created_at INTEGER NOT NULL, decided_at INTEGER,
    sale_status TEXT, price_low INTEGER, price_high INTEGER, price INTEGER, initial_price INTEGER,
    listed_at INTEGER, last_price_drop_at INTEGER, price_drop_suggested_at INTEGER,
    sold_price INTEGER, sold_at INTEGER,
    listing_title TEXT, listing_body TEXT, listing_category TEXT, shipping INTEGER DEFAULT 0,
    one_year_warned_at INTEGER,
    moved_from_sale_at INTEGER, discard_done_at INTEGER)''',
  'CREATE INDEX idx_items_user ON items(user_id)',
  '''CREATE TABLE notices(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    kind TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL,
    item_id INTEGER, created_at INTEGER NOT NULL, read_at INTEGER)''',
  '''CREATE TABLE costs(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL, at INTEGER NOT NULL, usd REAL NOT NULL, what TEXT)''',
];

// 버전 2: 디지털 기록·내보내기, 타임랩스 추가
const _v2 = [
  'ALTER TABLE items ADD COLUMN digital_keep INTEGER DEFAULT 0',
  'ALTER TABLE items ADD COLUMN exported_at INTEGER',
  '''CREATE TABLE timelapse(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL, spot TEXT NOT NULL, path TEXT NOT NULL, taken_at INTEGER NOT NULL)''',
];

// 버전 3: 연습 모드로 만든 물건 표시 (실제 물건이 생기면 자동 숨김)
const _v3 = ['ALTER TABLE items ADD COLUMN is_practice INTEGER DEFAULT 0'];

const Map<int, List<String>> migrations = {1: _v1, 2: _v2, 3: _v3};

Future<void> _runFrom(Database db, int from, int to) async {
  for (var v = from + 1; v <= to; v++) {
    for (final sql in migrations[v]!) {
      await db.execute(sql);
    }
  }
}

Future<Database> openAppDatabase(DatabaseFactory factory, String path, {int version = dataVersion}) {
  return factory.openDatabase(
    path,
    options: OpenDatabaseOptions(version: version, onCreate: (db, v) => _runFrom(db, 0, v), onUpgrade: (db, oldV, newV) => _runFrom(db, oldV, newV)),
  );
}

/// 변환 없이 지금 자료 버전만 읽기 (파일이 없으면 null)
Future<int?> peekVersion(DatabaseFactory factory, String path) async {
  if (!await factory.databaseExists(path)) return null;
  final db = await factory.openDatabase(path, options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
  try {
    return await db.getVersion();
  } finally {
    await db.close();
  }
}
