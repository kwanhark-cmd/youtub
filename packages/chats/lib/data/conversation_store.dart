import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../core/app_log.dart';
import '../core/cancel_token.dart';
import '../models/models.dart';
import '../parsers/parser_common.dart';
import 'app_database.dart';
import 'content_cipher.dart';
import 'korean_tokenizer.dart';

class ImportSummary {
  int added = 0;
  int updated = 0;
  int unchanged = 0;
  int skipped = 0;
  bool cancelled = false;
  final Set<AiSource> sources = {};
  final List<String> notices = [];
  final List<int> touchedIds = [];

  int get saved => added + updated;
}

/// 대화 저장소. 본문과 메모는 항상 암호화해서 저장합니다.
class ConversationStore {
  final AppDatabase database;
  final ContentCipher cipher;

  ConversationStore(this.database, this.cipher);

  /// true면 샘플 대화를 목록·검색·통계에서 숨깁니다(실제 대화가 들어오면 자동으로 켜짐).
  bool hideSamples = false;

  /// SQL 조건: 샘플 숨기기
  String sampleCond([String alias = 'c']) => hideSamples ? '$alias.sample=0' : '1=1';

  bool isHiddenSample(int id) => hideSamples && db.select('SELECT 1 FROM conversations WHERE id=? AND sample=1', [id]).isNotEmpty;

  int realCount() => db.select('SELECT COUNT(*) AS n FROM conversations WHERE sample=0').first['n'] as int;
  int sampleCount() => db.select('SELECT COUNT(*) AS n FROM conversations WHERE sample=1').first['n'] as int;

  Database get db => database.db;

  // ---------- 가져오기 ----------

  Future<ImportSummary> importResults(
    List<ParseResult> results, {
    required String fileName,
    void Function(int done, int total)? onProgress,
    CancelToken? cancel,
    bool sample = false,
  }) async {
    final summary = ImportSummary();
    final all = <ParsedConversation>[];
    for (final r in results) {
      all.addAll(r.conversations);
      summary.skipped += r.skipped;
      summary.sources.add(r.source);
      for (final n in r.notices) {
        if (!summary.notices.contains(n)) summary.notices.add(n);
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final find = db.prepare('SELECT id, msg_count, updated_at FROM conversations WHERE source=? AND ext_id=?');
    final insert = db.prepare('''INSERT INTO conversations(source, ext_id, title, created_at, updated_at, msg_count, link, has_attachments, imported_at, body, sample)
        VALUES(?,?,?,?,?,?,?,?,?,?,?)''');
    final update = db.prepare(
      '''UPDATE conversations SET title=?, updated_at=?, msg_count=?, link=?, has_attachments=?, imported_at=?, body=?,
        summary=CASE WHEN summary_by_ai=1 THEN summary ELSE NULL END WHERE id=?''',
    );
    try {
      const batch = 50;
      for (var i = 0; i < all.length; i += batch) {
        if (cancel?.isCancelled == true) {
          summary.cancelled = true;
          break;
        }
        final chunk = all.sublist(i, (i + batch).clamp(0, all.length));
        // 암호화는 비동기라 트랜잭션 밖에서 먼저 준비
        final prepared = <(ParsedConversation, Uint8List)>[];
        for (final c in chunk) {
          final body = jsonEncode(c.messages.map((m) => m.toJson()).toList());
          prepared.add((c, await cipher.encryptString(body)));
        }
        db.execute('BEGIN');
        try {
          for (final (c, enc) in prepared) {
            final existing = find.select([c.source.key, c.externalId]);
            if (existing.isEmpty) {
              insert.execute([
                c.source.key,
                c.externalId,
                c.title,
                c.createdAt.millisecondsSinceEpoch,
                c.updatedAt.millisecondsSinceEpoch,
                c.messages.length,
                c.link,
                c.hasAttachments ? 1 : 0,
                now,
                enc,
                sample ? 1 : 0,
              ]);
              final id = db.lastInsertRowId;
              _index(id, c.title, c.messages);
              summary.added++;
              summary.touchedIds.add(id);
            } else {
              final row = existing.first;
              final id = row['id'] as int;
              final oldCount = row['msg_count'] as int;
              final oldUpdated = row['updated_at'] as int;
              if (c.messages.length > oldCount || c.updatedAt.millisecondsSinceEpoch > oldUpdated) {
                update.execute([
                  c.title,
                  c.updatedAt.millisecondsSinceEpoch,
                  c.messages.length,
                  c.link,
                  c.hasAttachments ? 1 : 0,
                  now,
                  enc,
                  id,
                ]);
                db.execute('DELETE FROM conv_fts WHERE rowid=?', [id]);
                _index(id, c.title, c.messages);
                summary.updated++;
                summary.touchedIds.add(id);
              } else {
                summary.unchanged++;
              }
            }
          }
          db.execute('COMMIT');
        } catch (e) {
          db.execute('ROLLBACK');
          rethrow;
        }
        onProgress?.call((i + chunk.length).clamp(0, all.length), all.length);
        await Future<void>.delayed(Duration.zero); // 화면이 멈추지 않게 양보
      }
    } finally {
      find.close();
      insert.close();
      update.close();
    }
    db.execute('INSERT INTO imports(file_name, source, at, added, updated, unchanged, skipped) VALUES(?,?,?,?,?,?,?)', [
      fileName,
      summary.sources.map((s) => s.key).join(','),
      now,
      summary.added,
      summary.updated,
      summary.unchanged,
      summary.skipped,
    ]);
    AppLog.info('가져오기 완료', {
      'added': summary.added,
      'updated': summary.updated,
      'unchanged': summary.unchanged,
      'skipped': summary.skipped,
      'cancelled': summary.cancelled,
    });
    return summary;
  }

  void _index(int id, String title, List<Message> messages) {
    final bodyText = messages.map((m) => m.text).join('\n');
    db.execute('INSERT INTO conv_fts(rowid, t, b, u) VALUES(?,?,?,?)', [
      id,
      KoreanTokenizer.bigramIndex(title),
      KoreanTokenizer.bigramIndex(bodyText),
      KoreanTokenizer.unigramIndex('$title\n$bodyText'),
    ]);
  }

  // ---------- 읽기 ----------

  static ConversationSummary rowToSummary(Row r) => ConversationSummary(
    id: r['id'] as int,
    source: AiSourceInfo.fromKey(r['source'] as String) ?? AiSource.claude,
    externalId: r['ext_id'] as String,
    title: r['title'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
    messageCount: r['msg_count'] as int,
    starred: (r['starred'] as int) == 1,
    summary: r['summary'] as String?,
    link: r['link'] as String?,
    hasAttachments: (r['has_attachments'] as int) == 1,
    importedAt: DateTime.fromMillisecondsSinceEpoch(r['imported_at'] as int),
  );

  static const summaryColumns =
      'c.id, c.source, c.ext_id, c.title, c.created_at, c.updated_at, c.msg_count, c.starred, c.summary, c.link, c.has_attachments, c.imported_at';

  (String, List<Object?>) _filters({AiSource? source, int? topicId, bool? starred, String? tag, DateTime? from, DateTime? to}) {
    final where = <String>[sampleCond()];
    final args = <Object?>[];
    if (source != null) {
      where.add('c.source=?');
      args.add(source.key);
    }
    if (topicId != null) {
      where.add(
        "c.id IN (SELECT conv_id FROM conversation_topics WHERE origin!='removed' AND topic_id IN (WITH RECURSIVE sub(id) AS (SELECT ? UNION ALL SELECT t.id FROM topics t JOIN sub ON t.parent_id=sub.id) SELECT id FROM sub))",
      );
      args.add(topicId);
    }
    if (starred == true) where.add('c.starred=1');
    if (tag != null) {
      where.add('c.id IN (SELECT conv_id FROM tags WHERE tag=?)');
      args.add(tag);
    }
    if (from != null) {
      where.add('c.created_at>=?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('c.created_at<?');
      args.add(to.millisecondsSinceEpoch);
    }
    return (where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}', args);
  }

  List<ConversationSummary> list({
    int offset = 0,
    int limit = 40,
    AiSource? source,
    int? topicId,
    bool? starred,
    String? tag,
    DateTime? from,
    DateTime? to,
    bool newestFirst = true,
  }) {
    final (w, args) = _filters(source: source, topicId: topicId, starred: starred, tag: tag, from: from, to: to);
    final rows = db.select(
      'SELECT $summaryColumns FROM conversations c $w ORDER BY c.created_at ${newestFirst ? 'DESC' : 'ASC'}, c.id DESC LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return rows.map(rowToSummary).toList();
  }

  int count({AiSource? source, int? topicId, bool? starred, String? tag, DateTime? from, DateTime? to}) {
    final (w, args) = _filters(source: source, topicId: topicId, starred: starred, tag: tag, from: from, to: to);
    return db.select('SELECT COUNT(*) AS n FROM conversations c $w', args).first['n'] as int;
  }

  Map<AiSource, int> countBySource() {
    final out = <AiSource, int>{};
    for (final r in db.select('SELECT source, COUNT(*) AS n FROM conversations c WHERE ${sampleCond()} GROUP BY source')) {
      final s = AiSourceInfo.fromKey(r['source'] as String);
      if (s != null) out[s] = r['n'] as int;
    }
    return out;
  }

  ConversationSummary? get(int id) {
    final r = db.select('SELECT $summaryColumns FROM conversations c WHERE c.id=?', [id]);
    return r.isEmpty ? null : rowToSummary(r.first);
  }

  Future<List<Message>> messages(int id) async {
    final r = db.select('SELECT body FROM conversations WHERE id=?', [id]);
    if (r.isEmpty) return const [];
    final plain = await cipher.decryptString(r.first['body'] as Uint8List);
    return (jsonDecode(plain) as List).map((e) => Message.fromJson(e as Map<String, dynamic>)).toList();
  }

  List<ConversationSummary> importedSince(DateTime since) {
    final rows = db.select(
      'SELECT $summaryColumns FROM conversations c WHERE c.imported_at>=? AND ${sampleCond()} ORDER BY c.created_at DESC',
      [since.millisecondsSinceEpoch],
    );
    return rows.map(rowToSummary).toList();
  }

  DateTime? lastImportAt() {
    final r = db.select('SELECT MAX(at) AS m FROM imports');
    final v = r.first['m'];
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);
  }

  /// 연·월별 개수(타임라인용).
  List<(int year, int month, int count)> months({int? topicId, AiSource? source}) {
    final (w, args) = _filters(topicId: topicId, source: source);
    final rows = db.select(
      "SELECT strftime('%Y', c.created_at/1000, 'unixepoch', 'localtime') AS y, strftime('%m', c.created_at/1000, 'unixepoch', 'localtime') AS m, COUNT(*) AS n FROM conversations c $w GROUP BY y, m ORDER BY y DESC, m DESC",
      args,
    );
    return rows.map((r) => (int.parse(r['y'] as String), int.parse(r['m'] as String), r['n'] as int)).toList();
  }

  // ---------- 별표·태그·지우기 ----------

  void setStarred(int id, bool v) => db.execute('UPDATE conversations SET starred=? WHERE id=?', [v ? 1 : 0, id]);

  List<String> tagsOf(int id) =>
      db.select('SELECT tag FROM tags WHERE conv_id=? ORDER BY tag', [id]).map((r) => r['tag'] as String).toList();

  List<(String, int)> allTags() => db
      .select('SELECT tag, COUNT(*) AS n FROM tags GROUP BY tag ORDER BY n DESC, tag')
      .map((r) => (r['tag'] as String, r['n'] as int))
      .toList();

  void addTag(int id, String tag) {
    final t = tag.trim();
    if (t.isEmpty) return;
    db.execute('INSERT OR IGNORE INTO tags(conv_id, tag) VALUES(?,?)', [id, t]);
  }

  void removeTag(int id, String tag) => db.execute('DELETE FROM tags WHERE conv_id=? AND tag=?', [id, tag]);

  /// 앱 안의 기록만 지웁니다. 사용자가 넣은 원본 파일은 건드리지 않습니다.
  void deleteFromApp(int id) {
    db.execute('DELETE FROM conv_fts WHERE rowid=?', [id]);
    db.execute('DELETE FROM conversations WHERE id=?', [id]);
  }

  void setSummary(int id, String summary, {required bool byAi}) =>
      db.execute('UPDATE conversations SET summary=?, summary_by_ai=? WHERE id=?', [summary, byAi ? 1 : 0, id]);

  // ---------- 메모 ----------

  Future<void> addNote(int convId, String text, {bool byVoice = false}) async {
    final enc = await cipher.encryptString(text);
    db.execute('INSERT INTO notes(conv_id, created_at, by_voice, body) VALUES(?,?,?,?)', [
      convId,
      DateTime.now().millisecondsSinceEpoch,
      byVoice ? 1 : 0,
      enc,
    ]);
  }

  Future<List<Note>> notes(int convId) async {
    final out = <Note>[];
    for (final r in db.select('SELECT * FROM notes WHERE conv_id=? ORDER BY created_at DESC', [convId])) {
      out.add(
        Note(
          id: r['id'] as int,
          conversationId: convId,
          createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
          text: await cipher.decryptString(r['body'] as Uint8List),
          byVoice: (r['by_voice'] as int) == 1,
        ),
      );
    }
    return out;
  }

  void deleteNote(int noteId) => db.execute('DELETE FROM notes WHERE id=?', [noteId]);

  // ---------- 비용 ----------

  void addCost(String model, int inTok, int outTok, double usd) => db.execute(
    'INSERT INTO cost_log(at, model, input_tokens, output_tokens, usd) VALUES(?,?,?,?,?)',
    [DateTime.now().millisecondsSinceEpoch, model, inTok, outTok, usd],
  );

  double costThisMonth([DateTime? now]) {
    final n = now ?? DateTime.now();
    final start = DateTime(n.year, n.month).millisecondsSinceEpoch;
    return (db.select('SELECT COALESCE(SUM(usd),0) AS s FROM cost_log WHERE at>=?', [start]).first['s'] as num).toDouble();
  }

  double costTotal() => (db.select('SELECT COALESCE(SUM(usd),0) AS s FROM cost_log').first['s'] as num).toDouble();
}
