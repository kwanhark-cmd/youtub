import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../core/app_log.dart';

/// 데이터 버전과 자동 변환(마이그레이션).
/// 버전을 올릴 때는 [_migrations]에 단계를 추가합니다. 변환 전에 DB 파일을 백업합니다.
class AppDatabase {
  static const currentVersion = 3;
  final Database db;
  final String? path;

  AppDatabase._(this.db, this.path);

  static AppDatabase openInMemory() {
    final d = AppDatabase._(sqlite3.openInMemory(), null);
    d._migrate();
    return d;
  }

  static AppDatabase openFile(String path) {
    File(path).parent.createSync(recursive: true);
    final existing = File(path).existsSync();
    final db = sqlite3.open(path);
    final d = AppDatabase._(db, path);
    if (existing) {
      final v = d.version;
      if (v > 0 && v < currentVersion) d._backupBeforeMigrate(v);
    }
    d._migrate();
    return d;
  }

  int get version {
    try {
      final r = db.select("SELECT value FROM meta WHERE key='schema_version'");
      return r.isEmpty ? 0 : int.parse(r.first['value'] as String);
    } catch (_) {
      return 0;
    }
  }

  void _backupBeforeMigrate(int from) {
    if (path == null) return;
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      db.execute("VACUUM INTO '${path!}.bak-v$from-$stamp'");
      AppLog.info('데이터 변환 전 백업 완료', {'from': from});
    } catch (e, st) {
      AppLog.error('데이터 변환 전 백업 실패', e, st);
    }
  }

  static final List<List<String>> _migrations = [
    // 1: 처음 구조
    [
      'CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)',
      '''CREATE TABLE conversations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source TEXT NOT NULL,
        ext_id TEXT NOT NULL,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        msg_count INTEGER NOT NULL,
        starred INTEGER NOT NULL DEFAULT 0,
        summary TEXT,
        summary_by_ai INTEGER NOT NULL DEFAULT 0,
        link TEXT,
        has_attachments INTEGER NOT NULL DEFAULT 0,
        imported_at INTEGER NOT NULL,
        body BLOB NOT NULL,
        UNIQUE(source, ext_id))''',
      'CREATE INDEX idx_conv_created ON conversations(created_at)',
      'CREATE INDEX idx_conv_imported ON conversations(imported_at)',
      "CREATE VIRTUAL TABLE conv_fts USING fts5(t, b, u, content='', contentless_delete=1, tokenize='unicode61 remove_diacritics 0')",
      '''CREATE TABLE topics(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        parent_id INTEGER REFERENCES topics(id) ON DELETE SET NULL,
        created_at INTEGER NOT NULL)''',
      'CREATE TABLE topic_keys(key TEXT PRIMARY KEY, topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE)',
      '''CREATE TABLE conversation_topics(
        conv_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
        topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
        origin TEXT NOT NULL,
        PRIMARY KEY(conv_id, topic_id))''',
      'CREATE TABLE tags(conv_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE, tag TEXT NOT NULL, PRIMARY KEY(conv_id, tag))',
      '''CREATE TABLE notes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conv_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
        created_at INTEGER NOT NULL,
        by_voice INTEGER NOT NULL DEFAULT 0,
        body BLOB NOT NULL)''',
      'CREATE TABLE corrections(word TEXT NOT NULL, topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE, weight INTEGER NOT NULL DEFAULT 1, PRIMARY KEY(word, topic_id))',
      '''CREATE TABLE imports(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_name TEXT NOT NULL, source TEXT, at INTEGER NOT NULL,
        added INTEGER NOT NULL, updated INTEGER NOT NULL, unchanged INTEGER NOT NULL, skipped INTEGER NOT NULL)''',
      '''CREATE TABLE cost_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER NOT NULL,
        model TEXT NOT NULL, input_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL, usd REAL NOT NULL)''',
    ],
    // 2: 주제별 "지금까지 정한 내용"
    [
      'CREATE TABLE topic_digest(topic_id INTEGER PRIMARY KEY REFERENCES topics(id) ON DELETE CASCADE, text TEXT NOT NULL, by_ai INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL)',
    ],
    // 3 (앱 1.1.0): 샘플 대화 표시(실제 대화가 들어오면 숨기기 위해)
    [
      'ALTER TABLE conversations ADD COLUMN sample INTEGER NOT NULL DEFAULT 0',
      "UPDATE conversations SET sample=1 WHERE ext_id LIKE 'c1a2b3c4-000_-4000-8000-00000000000_' OR ext_id LIKE '6720a1b2-000_-8000-9000-00000000aa0_' "
          "OR (source='gemini' AND title IN ('블로그에 올릴 가을 산책 글 첫 문장 써 줘', '유튜브 앱에 넣을 알림 기능 이름 추천해 줘', '무릎에 무리 없는 운동 알려 줘'))",
      'CREATE INDEX idx_conv_sample ON conversations(sample)',
    ],
  ];

  void _migrate() {
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA journal_mode = WAL');
    var v = version;
    while (v < currentVersion) {
      final steps = _migrations[v];
      db.execute('BEGIN');
      try {
        for (final s in steps) {
          db.execute(s);
        }
        db.execute("INSERT OR REPLACE INTO meta(key, value) VALUES('schema_version', '${v + 1}')");
        db.execute('COMMIT');
      } catch (e) {
        db.execute('ROLLBACK');
        rethrow;
      }
      v++;
    }
  }

  void close() => db.close();
}
