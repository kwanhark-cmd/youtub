import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'logger.dart';

/// 한 번의 자동 변환(마이그레이션): [version] 으로 올릴 때 실행할 SQL 목록.
class Migration {
  const Migration(this.version, this.statements);
  final int version;
  final List<String> statements;
}

/// 버전 번호가 있는 SQLite 데이터베이스.
/// 열 때 저장된 버전(PRAGMA user_version)이 앱 버전보다 낮으면,
/// 먼저 파일을 자동 백업한 뒤 차례로 변환한다.
class AppDatabase {
  AppDatabase._(this.db, this.path);

  final Database db;

  /// 메모리 DB 이면 null.
  final String? path;

  static AppDatabase open(String path, List<Migration> migrations, {String? backupDir, AppLogger? logger}) {
    File(path).parent.createSync(recursive: true);
    final existed = File(path).existsSync();
    final db = sqlite3.open(path);
    final adb = AppDatabase._(db, path);
    final current = adb.version;
    final target = migrations.isEmpty ? 0 : migrations.last.version;
    if (existed && current > 0 && current < target) {
      final dir = backupDir ?? p.join(p.dirname(path), 'backups');
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final backup = p.join(dir, '${p.basenameWithoutExtension(path)}-v$current-$stamp.sqlite');
      adb.copyTo(backup);
      logger?.info('DB 변환 전 백업: v$current → v$target');
    }
    adb._migrate(migrations, logger);
    return adb;
  }

  static AppDatabase inMemory(List<Migration> migrations) {
    final adb = AppDatabase._(sqlite3.openInMemory(), null);
    adb._migrate(migrations, null);
    return adb;
  }

  int get version => db.select('PRAGMA user_version').first.values.first as int;

  void _migrate(List<Migration> migrations, AppLogger? logger) {
    db.execute('PRAGMA foreign_keys = ON');
    final current = version;
    for (final m in migrations) {
      if (m.version <= current) continue;
      db.execute('BEGIN');
      try {
        for (final s in m.statements) {
          db.execute(s);
        }
        db.execute('PRAGMA user_version = ${m.version}');
        db.execute('COMMIT');
        logger?.info('DB 변환 완료: v${m.version}');
      } catch (e) {
        db.execute('ROLLBACK');
        rethrow;
      }
    }
  }

  /// 현재 DB 를 다른 파일로 안전하게 복사 (VACUUM INTO).
  void copyTo(String target) {
    File(target).parent.createSync(recursive: true);
    if (File(target).existsSync()) File(target).deleteSync();
    final escaped = target.replaceAll("'", "''");
    db.execute("VACUUM INTO '$escaped'");
  }

  ResultSet select(String sql, [List<Object?> params = const []]) => db.select(sql, params);

  void execute(String sql, [List<Object?> params = const []]) => db.execute(sql, params);

  int insert(String sql, [List<Object?> params = const []]) {
    db.execute(sql, params);
    return db.lastInsertRowId;
  }

  T transaction<T>(T Function() body) {
    db.execute('BEGIN');
    try {
      final r = body();
      db.execute('COMMIT');
      return r;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  // ---- 간단한 설정 저장 (key → JSON) ----
  T? getSetting<T>(String key) {
    final rows = db.select('SELECT value FROM settings WHERE key = ?', [key]);
    if (rows.isEmpty) return null;
    final v = jsonDecode(rows.first['value'] as String);
    return v is T ? v : null;
  }

  void setSetting(String key, Object? value) {
    db.execute(
      'INSERT INTO settings(key, value) VALUES(?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, jsonEncode(value)],
    );
  }

  void close() {
    try {
      db.close();
    } catch (_) {}
  }
}

/// 사용자 목록 DB (기기 안 로컬 계정).
const usersMigrations = <Migration>[
  Migration(1, [
    '''CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)''',
    '''CREATE TABLE users(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      pw_hash TEXT NOT NULL,
      salt TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''',
  ]),
];

/// 사용자 한 명의 자료 DB. 사용자마다 파일이 따로 있어 서로의 자료가 섞이지 않는다.
const userDataMigrations = <Migration>[
  // v1: 뼈대 + 1단계(유튜브 채널 관리)
  Migration(1, [
    '''CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)''',
    '''CREATE TABLE accounts(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      provider TEXT NOT NULL,
      label TEXT NOT NULL,
      connected_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'ok',
      mock INTEGER NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE channels(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      account_id INTEGER,
      channel_id TEXT NOT NULL UNIQUE,
      title TEXT NOT NULL,
      url TEXT NOT NULL DEFAULT '',
      thumbnail TEXT NOT NULL DEFAULT '',
      subscriber_count INTEGER NOT NULL DEFAULT 0,
      video_count INTEGER NOT NULL DEFAULT 0,
      view_count INTEGER NOT NULL DEFAULT 0,
      uploads_playlist TEXT NOT NULL DEFAULT '',
      style_json TEXT,
      added_at TEXT NOT NULL,
      last_synced TEXT
    )''',
    '''CREATE TABLE videos(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      channel_id TEXT NOT NULL,
      video_id TEXT NOT NULL UNIQUE,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      tags_json TEXT NOT NULL DEFAULT '[]',
      thumbnail_url TEXT NOT NULL DEFAULT '',
      view_count INTEGER NOT NULL DEFAULT 0,
      published_at TEXT NOT NULL DEFAULT '',
      privacy TEXT NOT NULL DEFAULT 'public',
      category_id TEXT NOT NULL DEFAULT '22',
      updated_at TEXT NOT NULL
    )''',
    'CREATE INDEX idx_videos_channel ON videos(channel_id, published_at DESC)',
    '''CREATE TABLE edits(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      target_type TEXT NOT NULL,
      target_id TEXT NOT NULL,
      parent_id TEXT NOT NULL DEFAULT '',
      before_json TEXT NOT NULL,
      after_json TEXT NOT NULL,
      views_before INTEGER NOT NULL DEFAULT 0,
      views_after INTEGER,
      status TEXT NOT NULL,
      reason TEXT NOT NULL DEFAULT '',
      day TEXT NOT NULL,
      created_at TEXT NOT NULL,
      reverted_at TEXT
    )''',
    'CREATE INDEX idx_edits_target ON edits(target_type, target_id, id DESC)',
    'CREATE INDEX idx_edits_day ON edits(day)',
    '''CREATE TABLE channel_stats(
      channel_id TEXT NOT NULL,
      day TEXT NOT NULL,
      view_count INTEGER NOT NULL,
      subscriber_count INTEGER NOT NULL,
      PRIMARY KEY(channel_id, day)
    )''',
    '''CREATE TABLE quota_usage(day TEXT PRIMARY KEY, used INTEGER NOT NULL)''',
    '''CREATE TABLE ai_costs(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      month TEXT NOT NULL,
      at TEXT NOT NULL,
      task TEXT NOT NULL,
      model TEXT NOT NULL,
      input_tokens INTEGER NOT NULL,
      output_tokens INTEGER NOT NULL,
      cost_usd REAL NOT NULL
    )''',
    '''CREATE TABLE jobs(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      payload TEXT NOT NULL DEFAULT '{}',
      status TEXT NOT NULL,
      run_day TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE job_log(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      at TEXT NOT NULL,
      message TEXT NOT NULL
    )''',
    '''CREATE TABLE memos(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      text TEXT NOT NULL,
      created_at TEXT NOT NULL,
      used INTEGER NOT NULL DEFAULT 0
    )''',
  ]),
  // v2: 2단계(콘텐츠 제작·업로드, 제작 도구)
  Migration(2, [
    '''CREATE TABLE productions(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      channel_id TEXT NOT NULL,
      format TEXT NOT NULL,
      topic TEXT NOT NULL DEFAULT '',
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      tags_json TEXT NOT NULL DEFAULT '[]',
      thumbnail_text TEXT NOT NULL DEFAULT '',
      script TEXT NOT NULL DEFAULT '',
      memo_id INTEGER,
      corner_id INTEGER,
      fingerprint TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL,
      video_path TEXT NOT NULL DEFAULT '',
      video_source TEXT NOT NULL DEFAULT '',
      ai_label_method TEXT NOT NULL DEFAULT '',
      uploaded_video_id TEXT NOT NULL DEFAULT '',
      upload_day TEXT NOT NULL DEFAULT '',
      extra_json TEXT NOT NULL DEFAULT '{}',
      day TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    'CREATE INDEX idx_prod_channel ON productions(channel_id, id DESC)',
    'CREATE INDEX idx_prod_status ON productions(status)',
    '''CREATE TABLE tool_status(
      tool TEXT PRIMARY KEY,
      connected_at TEXT,
      expires_at TEXT,
      status TEXT NOT NULL DEFAULT 'none',
      info_json TEXT NOT NULL DEFAULT '{}'
    )''',
  ]),
  // v3: 3단계(구글 블로그·티스토리)
  Migration(3, [
    '''CREATE TABLE blog_sites(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      platform TEXT NOT NULL,
      blog_id TEXT NOT NULL DEFAULT '',
      title TEXT NOT NULL,
      url TEXT NOT NULL DEFAULT '',
      account_id INTEGER NOT NULL DEFAULT 0,
      style_json TEXT,
      added_at TEXT NOT NULL
    )''',
    '''CREATE TABLE posts(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      site_id INTEGER NOT NULL,
      post_id TEXT NOT NULL,
      title TEXT NOT NULL,
      content TEXT NOT NULL DEFAULT '',
      labels_json TEXT NOT NULL DEFAULT '[]',
      url TEXT NOT NULL DEFAULT '',
      published_at TEXT NOT NULL DEFAULT '',
      updated_at TEXT NOT NULL,
      UNIQUE(site_id, post_id)
    )''',
    '''CREATE TABLE blog_drafts(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      site_id INTEGER NOT NULL,
      title TEXT NOT NULL,
      html TEXT NOT NULL,
      tags_json TEXT NOT NULL DEFAULT '[]',
      status TEXT NOT NULL,
      remote_post_id TEXT NOT NULL DEFAULT '',
      day TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''',
  ]),
  // v4: 4단계(사용자 코너)
  Migration(4, [
    '''CREATE TABLE corners(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      channel_id TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''',
    '''CREATE TABLE corner_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      corner_id INTEGER NOT NULL,
      kind TEXT NOT NULL,
      path TEXT NOT NULL DEFAULT '',
      title TEXT NOT NULL DEFAULT '',
      text TEXT NOT NULL DEFAULT '',
      source TEXT NOT NULL DEFAULT 'own',
      copyright TEXT NOT NULL DEFAULT 'own',
      duration_ms INTEGER NOT NULL DEFAULT 0,
      used INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )''',
    'CREATE INDEX idx_corner_items ON corner_items(corner_id)',
  ]),
  // v5: 추가 기능(주목할 영상) — 영상별 날마다 조회수 기록
  Migration(5, [
    '''CREATE TABLE video_stats(
      video_id TEXT NOT NULL,
      day TEXT NOT NULL,
      view_count INTEGER NOT NULL,
      PRIMARY KEY(video_id, day)
    )''',
  ]),
  // v6: 업데이트 기록 (어떤 버전을 언제부터 썼는지). 문제 신고·되돌리기 안내에 사용.
  Migration(6, [
    '''CREATE TABLE app_versions(
      version TEXT PRIMARY KEY,
      first_seen TEXT NOT NULL
    )''',
  ]),
];

/// 오늘 날짜 문자열 (yyyy-MM-dd, 기기 시간 기준).
String dayKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

String monthKey(DateTime t) => '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}';
