import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/db.dart';
import '../../core/failure.dart';
import '../../core/logger.dart';
import '../../core/secret_store.dart';

class LocalUser {
  LocalUser(this.id, this.name);
  final int id;
  final String name;
}

/// PBKDF2-HMAC-SHA256. 비밀번호 자체는 어디에도 저장하지 않고 이 해시만 저장한다.
String pbkdf2(String password, List<int> salt, {int iterations = 20000}) {
  final hmac = Hmac(sha256, utf8.encode(password));
  final block = Uint8List.fromList([...salt, 0, 0, 0, 1]);
  var u = hmac.convert(block).bytes;
  final out = List<int>.from(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return base64Encode(out);
}

/// 기기 안 로컬 사용자 계정. 사용자마다 자료 DB 파일이 따로 있다.
class LocalAccounts {
  LocalAccounts({required this.baseDir, required this.secrets, this.logger, this.inMemory = false})
    : db = inMemory
          ? AppDatabase.inMemory(usersMigrations)
          : AppDatabase.open(p.join(baseDir, usersDbFile), usersMigrations, logger: logger);

  final String baseDir;
  final SecretStore secrets;
  final AppLogger? logger;
  final bool inMemory;
  final AppDatabase db;
  final Map<int, AppDatabase> _memDbs = {};

  List<LocalUser> list() => db
      .select('SELECT id, name FROM users ORDER BY id')
      .map((r) => LocalUser(r['id'] as int, r['name'] as String))
      .toList();

  LocalUser create(String name, String password) {
    final n = name.trim();
    if (n.isEmpty) throw AppFailure(FailureKind.invalidInput, 'name empty');
    if (password.length < 4) throw AppFailure(FailureKind.invalidInput, 'password short');
    if (db.select('SELECT 1 FROM users WHERE name = ?', [n]).isNotEmpty) {
      throw AppFailure(FailureKind.conflict, 'name taken');
    }
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final id = db.insert('INSERT INTO users(name, pw_hash, salt, created_at) VALUES(?, ?, ?, ?)', [
      n,
      pbkdf2(password, salt),
      base64Encode(salt),
      DateTime.now().toIso8601String(),
    ]);
    logger?.info('사용자 생성: #$id');
    return LocalUser(id, n);
  }

  /// 맞으면 사용자, 틀리면 null.
  LocalUser? verify(int userId, String password) {
    final rows = db.select('SELECT id, name, pw_hash, salt FROM users WHERE id = ?', [userId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final hash = pbkdf2(password, base64Decode(r['salt'] as String));
    if (!_constantTimeEquals(hash, r['pw_hash'] as String)) return null;
    return LocalUser(r['id'] as int, r['name'] as String);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static const usersDbFile = 'users.sqlite';
  String get usersDbPath => p.join(baseDir, usersDbFile);
  String userDir(int userId) => p.join(baseDir, 'users', 'u$userId');
  String userDbPath(int userId) => p.join(userDir(userId), 'data.sqlite');

  /// 사용자 자료 DB 열기 (필요하면 자동 변환 + 변환 전 백업).
  AppDatabase openUserDb(int userId, {List<Migration> migrations = userDataMigrations}) {
    if (inMemory) {
      return _memDbs.putIfAbsent(userId, () => AppDatabase.inMemory(migrations));
    }
    return AppDatabase.open(
      userDbPath(userId),
      migrations,
      backupDir: p.join(userDir(userId), 'backups'),
      logger: logger,
    );
  }

  /// 사용자 자료 전부 지우기 (초기화). 사용자 계정 자체는 남긴다.
  Future<void> wipeUserData(int userId, AppDatabase? openDb) async {
    openDb?.close();
    _memDbs.remove(userId)?.close();
    await UserSecrets(secrets, userId).deleteAll();
    final f = File(userDbPath(userId));
    if (!inMemory && f.existsSync()) f.deleteSync();
    logger?.info('사용자 자료 초기화: #$userId');
  }

  Future<void> deleteUser(int userId, AppDatabase? openDb) async {
    await wipeUserData(userId, openDb);
    final d = Directory(userDir(userId));
    if (!inMemory && d.existsSync()) d.deleteSync(recursive: true);
    db.execute('DELETE FROM users WHERE id = ?', [userId]);
  }
}
