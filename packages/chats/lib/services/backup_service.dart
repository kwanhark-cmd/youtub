import 'dart:convert';
import 'dart:typed_data';

import '../core/app_log.dart';
import '../data/content_cipher.dart';
import '../data/conversation_store.dart';
import '../data/korean_tokenizer.dart';
import '../models/models.dart';

/// 비밀번호로 잠근 백업 파일 만들기·되살리기.
class BackupService {
  static const fileExtension = 'aibackup';
  static const _plainTables = ['topics', 'topic_keys', 'conversation_topics', 'tags', 'corrections', 'imports', 'cost_log', 'topic_digest'];

  static Future<Uint8List> create(ConversationStore store, String password, {Map<String, dynamic>? settings}) async {
    final db = store.db;
    final convs = <Map<String, dynamic>>[];
    for (final r in db.select('SELECT * FROM conversations')) {
      final m = Map<String, dynamic>.from(r);
      m['body'] = await store.cipher.decryptString(r['body'] as Uint8List);
      convs.add(m);
    }
    final notes = <Map<String, dynamic>>[];
    for (final r in db.select('SELECT * FROM notes')) {
      final m = Map<String, dynamic>.from(r);
      m['body'] = await store.cipher.decryptString(r['body'] as Uint8List);
      notes.add(m);
    }
    final payload = {
      'format': 'ai-chat-organizer-backup',
      'version': store.database.version,
      'created': DateTime.now().toIso8601String(),
      'conversations': convs,
      'notes': notes,
      for (final t in _plainTables) t: db.select('SELECT * FROM $t').map((r) => Map<String, dynamic>.from(r)).toList(),
      'settings': ?settings,
    };
    return PasswordCipher.encrypt(utf8.encode(jsonEncode(payload)), password);
  }

  /// 되살리기: 지금 자료를 지우고 백업 내용으로 바꿉니다. 반환값은 백업 안의 설정.
  static Future<Map<String, dynamic>?> restore(ConversationStore store, Uint8List data, String password) async {
    final json = jsonDecode(utf8.decode(await PasswordCipher.decrypt(data, password))) as Map<String, dynamic>;
    if (json['format'] != 'ai-chat-organizer-backup') throw const FormatException('백업 파일이 아니에요');
    final db = store.db;
    // 암호화를 먼저 끝내 둔 뒤 한 번에 바꿈
    final convs = <(Map<String, dynamic>, Uint8List)>[];
    for (final c in (json['conversations'] as List).cast<Map<String, dynamic>>()) {
      convs.add((c, await store.cipher.encryptString(c['body'] as String)));
    }
    final notes = <(Map<String, dynamic>, Uint8List)>[];
    for (final n in (json['notes'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      notes.add((n, await store.cipher.encryptString(n['body'] as String)));
    }
    db.execute('PRAGMA foreign_keys = OFF');
    db.execute('BEGIN');
    try {
      for (final t in [..._plainTables, 'notes', 'conversations']) {
        db.execute('DELETE FROM $t');
      }
      db.execute("DELETE FROM conv_fts");
      for (final (c, enc) in convs) {
        final cols = c.keys.where((k) => k != 'body').toList();
        db.execute('INSERT INTO conversations(${[...cols, 'body'].join(',')}) VALUES(${List.filled(cols.length + 1, '?').join(',')})', [
          ...cols.map((k) => c[k]),
          enc,
        ]);
        final msgs = (jsonDecode(c['body'] as String) as List).map((e) => Message.fromJson(e as Map<String, dynamic>)).toList();
        final bodyText = msgs.map((m) => m.text).join('\n');
        db.execute('INSERT INTO conv_fts(rowid, t, b, u) VALUES(?,?,?,?)', [
          c['id'],
          KoreanTokenizer.bigramIndex(c['title'] as String),
          KoreanTokenizer.bigramIndex(bodyText),
          KoreanTokenizer.unigramIndex('${c['title']}\n$bodyText'),
        ]);
      }
      for (final (n, enc) in notes) {
        final cols = n.keys.where((k) => k != 'body').toList();
        db.execute('INSERT INTO notes(${[...cols, 'body'].join(',')}) VALUES(${List.filled(cols.length + 1, '?').join(',')})', [
          ...cols.map((k) => n[k]),
          enc,
        ]);
      }
      for (final t in _plainTables) {
        for (final r in (json[t] as List? ?? const []).cast<Map<String, dynamic>>()) {
          final cols = r.keys.toList();
          db.execute(
            'INSERT OR IGNORE INTO $t(${cols.join(',')}) VALUES(${List.filled(cols.length, '?').join(',')})',
            cols.map((k) => r[k]).toList(),
          );
        }
      }
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      db.execute('PRAGMA foreign_keys = ON');
    }
    AppLog.info('백업 되살리기 완료', {'conversations': convs.length});
    return json['settings'] as Map<String, dynamic>?;
  }
}
