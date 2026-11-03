import '../../core/db.dart';

class Memo {
  Memo(this.id, this.text, this.createdAt, this.used);
  final int id;
  final String text;
  final DateTime createdAt;
  final bool used;
}

/// 말로 남긴 아이디어·사연. 제작 소재로 쓰인다.
class MemoService {
  MemoService(this.db, this.now);
  final AppDatabase db;
  final DateTime Function() now;

  int add(String text) =>
      db.insert('INSERT INTO memos(text, created_at) VALUES(?, ?)', [text.trim(), now().toIso8601String()]);

  List<Memo> list({bool unusedOnly = false, int limit = 100, int offset = 0}) => db
      .select('SELECT * FROM memos ${unusedOnly ? 'WHERE used = 0' : ''} ORDER BY id DESC LIMIT ? OFFSET ?', [
        limit,
        offset,
      ])
      .map(
        (r) => Memo(
          r['id'] as int,
          r['text'] as String,
          DateTime.parse(r['created_at'] as String),
          (r['used'] as int) == 1,
        ),
      )
      .toList();

  Memo? byId(int id) {
    final r = list(limit: 100000).where((m) => m.id == id);
    return r.isEmpty ? null : r.first;
  }

  void markUsed(int id) => db.execute('UPDATE memos SET used = 1 WHERE id = ?', [id]);
  void delete(int id) => db.execute('DELETE FROM memos WHERE id = ?', [id]);
}
