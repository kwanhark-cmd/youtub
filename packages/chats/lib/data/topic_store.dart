import 'package:sqlite3/sqlite3.dart';

import '../models/models.dart';

/// 주제(폴더) 관리. 사용자가 고친 내용(옮기기·빼기·이름 바꾸기·합치기)을 기억합니다.
///
/// conversation_topics.origin:
/// - 'auto'   : 자동 분류가 넣음(다시 분류하면 바뀔 수 있음)
/// - 'user'   : 사용자가 직접 넣음(자동 분류가 바꾸지 않음)
/// - 'removed': 사용자가 뺌(자동 분류가 다시 넣지 않음)
class TopicStore {
  final Database db;
  TopicStore(this.db);

  /// 샘플 대화를 숨길 때 주제별 개수에서도 뺌.
  bool hideSamples = false;

  List<Topic> all() {
    final rows = db.select('''SELECT t.id, t.name, t.parent_id,
        (SELECT COUNT(*) FROM conversation_topics ct JOIN conversations c ON c.id=ct.conv_id WHERE ct.topic_id=t.id AND ct.origin!='removed' AND (${hideSamples ? 'c.sample=0' : '1=1'})) AS n
        FROM topics t ORDER BY t.name''');
    return rows
        .map((r) => Topic(id: r['id'] as int, name: r['name'] as String, parentId: r['parent_id'] as int?, count: r['n'] as int))
        .toList();
  }

  Topic? byId(int id) => all().where((t) => t.id == id).firstOrNull;

  Topic? byName(String name) {
    final n = name.trim();
    final r = db.select('SELECT id, name, parent_id FROM topics WHERE name=? COLLATE NOCASE', [n]);
    if (r.isEmpty) return null;
    return Topic(id: r.first['id'] as int, name: r.first['name'] as String, parentId: r.first['parent_id'] as int?);
  }

  int create(String name, {int? parentId, String? key}) {
    final existing = byName(name);
    if (existing != null) {
      if (key != null) setKey(key, existing.id);
      return existing.id;
    }
    db.execute('INSERT INTO topics(name, parent_id, created_at) VALUES(?,?,?)', [
      name.trim(),
      parentId,
      DateTime.now().millisecondsSinceEpoch,
    ]);
    final id = db.lastInsertRowId;
    if (key != null) setKey(key, id);
    return id;
  }

  /// 분류 사전의 열쇠(key)가 가리키는 주제. 이름을 바꾸거나 합쳐도 따라갑니다.
  int? topicForKey(String key) {
    final r = db.select('SELECT topic_id FROM topic_keys WHERE key=?', [key]);
    return r.isEmpty ? null : r.first['topic_id'] as int;
  }

  void setKey(String key, int topicId) => db.execute('INSERT OR REPLACE INTO topic_keys(key, topic_id) VALUES(?,?)', [key, topicId]);

  void rename(int id, String newName) {
    final n = newName.trim();
    if (n.isEmpty) return;
    db.execute('UPDATE topics SET name=? WHERE id=?', [n, id]);
  }

  /// 하위 주제로 옮기기(자기 자신이나 자기 아래로는 옮길 수 없음).
  bool setParent(int id, int? parentId) {
    if (parentId == id) return false;
    if (parentId != null && _descendants(id).contains(parentId)) return false;
    db.execute('UPDATE topics SET parent_id=? WHERE id=?', [parentId, id]);
    return true;
  }

  Set<int> _descendants(int id) {
    final rows = db.select(
      'WITH RECURSIVE sub(id) AS (SELECT id FROM topics WHERE parent_id=? UNION ALL SELECT t.id FROM topics t JOIN sub ON t.parent_id=sub.id) SELECT id FROM sub',
      [id],
    );
    return rows.map((r) => r['id'] as int).toSet();
  }

  /// [fromId] 주제를 [intoId] 주제로 합칩니다.
  void merge(int fromId, int intoId) {
    if (fromId == intoId) return;
    db.execute('BEGIN');
    try {
      db.execute(
        '''INSERT OR IGNORE INTO conversation_topics(conv_id, topic_id, origin)
          SELECT conv_id, ?, CASE WHEN origin='removed' THEN 'removed' ELSE 'user' END FROM conversation_topics WHERE topic_id=?''',
        [intoId, fromId],
      );
      db.execute('UPDATE topic_keys SET topic_id=? WHERE topic_id=?', [intoId, fromId]);
      db.execute('UPDATE OR IGNORE corrections SET topic_id=? WHERE topic_id=?', [intoId, fromId]);
      db.execute('UPDATE topics SET parent_id=? WHERE parent_id=?', [intoId, fromId]);
      db.execute('DELETE FROM topics WHERE id=?', [fromId]);
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// 고른 대화들을 새 주제로 나눕니다.
  int split(int fromId, String newName, List<int> convIds) {
    final parent = byId(fromId)?.parentId;
    final newId = create(newName, parentId: parent);
    for (final c in convIds) {
      setOrigin(c, fromId, 'removed');
      setOrigin(c, newId, 'user');
    }
    return newId;
  }

  void delete(int id) {
    db.execute('UPDATE topics SET parent_id=(SELECT parent_id FROM topics WHERE id=?) WHERE parent_id=?', [id, id]);
    db.execute('DELETE FROM topics WHERE id=?', [id]);
  }

  void setOrigin(int convId, int topicId, String origin) => db.execute(
    'INSERT INTO conversation_topics(conv_id, topic_id, origin) VALUES(?,?,?) ON CONFLICT(conv_id, topic_id) DO UPDATE SET origin=excluded.origin',
    [convId, topicId, origin],
  );

  /// 자동 분류 결과 넣기(사용자가 정한 것은 건드리지 않음).
  void addAuto(int convId, int topicId) =>
      db.execute("INSERT OR IGNORE INTO conversation_topics(conv_id, topic_id, origin) VALUES(?,?,'auto')", [convId, topicId]);

  void clearAuto(int convId) => db.execute("DELETE FROM conversation_topics WHERE conv_id=? AND origin='auto'", [convId]);

  /// 사용자가 이 대화를 이 주제로 옮김: 다른 주제에서는 빼고 이 주제에 넣음.
  void moveTo(int convId, int topicId) {
    final current = db.select("SELECT topic_id FROM conversation_topics WHERE conv_id=? AND origin!='removed'", [convId]);
    for (final r in current) {
      final t = r['topic_id'] as int;
      if (t != topicId) setOrigin(convId, t, 'removed');
    }
    setOrigin(convId, topicId, 'user');
  }

  List<Topic> topicsOf(int convId) => db
      .select(
        "SELECT t.id, t.name, t.parent_id FROM topics t JOIN conversation_topics ct ON ct.topic_id=t.id WHERE ct.conv_id=? AND ct.origin!='removed' ORDER BY t.name",
        [convId],
      )
      .map((r) => Topic(id: r['id'] as int, name: r['name'] as String, parentId: r['parent_id'] as int?))
      .toList();

  Set<int> removedTopicsOf(int convId) => db
      .select("SELECT topic_id FROM conversation_topics WHERE conv_id=? AND origin='removed'", [convId])
      .map((r) => r['topic_id'] as int)
      .toSet();

  bool hasUserTopic(int convId) =>
      db.select("SELECT 1 FROM conversation_topics WHERE conv_id=? AND origin='user' LIMIT 1", [convId]).isNotEmpty;

  // ---------- 사용자 수정 기억 ----------

  void rememberCorrection(List<String> words, int topicId) {
    for (final w in words) {
      db.execute(
        'INSERT INTO corrections(word, topic_id, weight) VALUES(?,?,1) ON CONFLICT(word, topic_id) DO UPDATE SET weight=weight+1',
        [w, topicId],
      );
    }
  }

  /// 낱말 → (주제, 무게)
  Map<String, List<(int, int)>> corrections() {
    final out = <String, List<(int, int)>>{};
    for (final r in db.select('SELECT word, topic_id, weight FROM corrections')) {
      out.putIfAbsent(r['word'] as String, () => []).add((r['topic_id'] as int, r['weight'] as int));
    }
    return out;
  }

  // ---------- 지금까지 정한 내용 ----------

  (String, bool, DateTime)? digest(int topicId) {
    final r = db.select('SELECT text, by_ai, updated_at FROM topic_digest WHERE topic_id=?', [topicId]);
    if (r.isEmpty) return null;
    return (r.first['text'] as String, (r.first['by_ai'] as int) == 1, DateTime.fromMillisecondsSinceEpoch(r.first['updated_at'] as int));
  }

  void setDigest(int topicId, String text, {required bool byAi}) => db.execute(
    'INSERT OR REPLACE INTO topic_digest(topic_id, text, by_ai, updated_at) VALUES(?,?,?,?)',
    [topicId, text, byAi ? 1 : 0, DateTime.now().millisecondsSinceEpoch],
  );
}
