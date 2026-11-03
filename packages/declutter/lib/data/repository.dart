import 'package:sqflite_common/sqlite_api.dart';

import 'models.dart';

/// 모든 데이터 읽기·쓰기. 사용자마다 자료가 분리됩니다(user_id).
class Repository {
  final Database db;
  Repository(this.db);

  static const int globalUser = 0;

  // ---------- 사용자 ----------
  Future<List<AppUser>> users() async => (await db.query('users', orderBy: 'id')).map(AppUser.fromMap).toList();

  Future<AppUser> createUser(String name, DateTime now) async {
    final id = await db.insert('users', {'name': name, 'created_at': now.millisecondsSinceEpoch});
    return AppUser(id: id, name: name, createdAt: now);
  }

  Future<void> renameUser(int id, String name) => db.update('users', {'name': name}, where: 'id=?', whereArgs: [id]);

  Future<void> deleteUser(int id) async {
    await db.transaction((t) async {
      for (final table in ['items', 'notices', 'costs', 'timelapse', 'settings']) {
        await t.delete(table, where: 'user_id=?', whereArgs: [id]);
      }
      await t.delete('users', where: 'id=?', whereArgs: [id]);
    });
  }

  // ---------- 설정 ----------
  Future<String?> getSetting(int userId, String key) async {
    final r = await db.query('settings', where: 'user_id=? AND key=?', whereArgs: [userId, key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<Map<String, String>> allSettings(int userId) async {
    final r = await db.query('settings', where: 'user_id=?', whereArgs: [userId]);
    return {for (final m in r) m['key'] as String: (m['value'] as String?) ?? ''};
  }

  Future<void> setSetting(int userId, String key, String? value) =>
      db.insert('settings', {'user_id': userId, 'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  // ---------- 물건 ----------
  Future<int> insertItem(Item item) async {
    final id = await db.insert('items', item.toMap()..remove('id'));
    item.id = id;
    return id;
  }

  Future<void> updateItem(Item item) => db.update('items', item.toMap(), where: 'id=? AND user_id=?', whereArgs: [item.id, item.userId]);

  Future<void> deleteItem(int userId, int id) => db.delete('items', where: 'id=? AND user_id=?', whereArgs: [id, userId]);

  Future<Item?> item(int userId, int id) async {
    final r = await db.query('items', where: 'id=? AND user_id=?', whereArgs: [id, userId]);
    return r.isEmpty ? null : Item.fromMap(r.first);
  }

  /// 실제(연습이 아닌) 물건이 하나라도 있는지
  Future<bool> hasRealItems(int userId) async =>
      (await db.query('items', columns: ['id'], where: 'user_id=? AND (is_practice IS NULL OR is_practice=0)', whereArgs: [userId], limit: 1)).isNotEmpty;

  /// 연습 물건은 실제 물건이 하나라도 등록되면 자동으로 숨깁니다.
  Future<List<Item>> items(int userId, {Decision? decision, bool undecidedOnly = false, String? search, bool includePractice = false}) async {
    final where = <String>['user_id=?'];
    final args = <Object?>[userId];
    if (!includePractice && await hasRealItems(userId)) where.add('(is_practice IS NULL OR is_practice=0)');
    if (undecidedOnly) {
      where.add('decision IS NULL');
    } else if (decision != null) {
      where.add('decision=?');
      args.add(decision.code);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('(name LIKE ? OR room LIKE ? OR spot LIKE ? OR tags LIKE ? OR kind LIKE ?)');
      final q = '%${search.trim()}%';
      args.addAll([q, q, q, q, q]);
    }
    final r = await db.query('items', where: where.join(' AND '), whereArgs: args, orderBy: 'created_at DESC, id DESC');
    return r.map(Item.fromMap).toList();
  }

  Future<ProgressStats> stats(int userId) async {
    final all = await items(userId);
    int c(bool Function(Item) f) => all.where(f).length;
    return ProgressStats(
      total: all.length,
      undecided: c((i) => i.decision == null),
      use: c((i) => i.decision == Decision.use),
      sell: c((i) => i.decision == Decision.sell),
      discard: c((i) => i.decision == Decision.discard),
      sold: c((i) => i.decision == Decision.sell && i.saleStatus == SaleStatus.sold),
      discarded: c((i) => i.decision == Decision.discard && i.discardDoneAt != null),
      income: all.where((i) => i.saleStatus == SaleStatus.sold).fold(0, (s, i) => s + (i.soldPrice ?? i.price ?? 0)),
      estimatedValue: all.where((i) => i.decision == Decision.sell && i.saleStatus != SaleStatus.sold).fold(0, (s, i) => s + (i.price ?? i.priceHigh ?? 0)),
    );
  }

  // ---------- 앱 안 알림 ----------
  Future<int> addNotice(Notice n) => db.insert('notices', n.toMap()..remove('id'));

  Future<List<Notice>> notices(int userId, {bool unreadOnly = false}) async {
    final r = await db.query(
      'notices',
      where: unreadOnly ? 'user_id=? AND read_at IS NULL' : 'user_id=?',
      whereArgs: [userId],
      orderBy: 'created_at DESC, id DESC',
      limit: 200,
    );
    return r.map(Notice.fromMap).toList();
  }

  Future<bool> hasNoticeSince(int userId, String kind, DateTime since, {int? itemId}) async {
    final r = await db.query(
      'notices',
      where: 'user_id=? AND kind=? AND created_at>=?${itemId != null ? ' AND item_id=?' : ''}',
      whereArgs: [userId, kind, since.millisecondsSinceEpoch, ?itemId],
      limit: 1,
    );
    return r.isNotEmpty;
  }

  Future<void> markAllRead(int userId, DateTime now) =>
      db.update('notices', {'read_at': now.millisecondsSinceEpoch}, where: 'user_id=? AND read_at IS NULL', whereArgs: [userId]);

  // ---------- AI 비용 ----------
  Future<void> addCost(int userId, DateTime at, double usd, String what) =>
      db.insert('costs', {'user_id': userId, 'at': at.millisecondsSinceEpoch, 'usd': usd, 'what': what});

  Future<double> costSince(int userId, DateTime since) async {
    final r = await db.rawQuery('SELECT SUM(usd) s FROM costs WHERE user_id=? AND at>=?', [userId, since.millisecondsSinceEpoch]);
    return (r.first['s'] as num?)?.toDouble() ?? 0;
  }

  Future<double> costTotal(int userId) async {
    final r = await db.rawQuery('SELECT SUM(usd) s FROM costs WHERE user_id=?', [userId]);
    return (r.first['s'] as num?)?.toDouble() ?? 0;
  }

  // ---------- 타임랩스 ----------
  Future<int> addShot(TimelapseShot s) => db.insert('timelapse', s.toMap()..remove('id'));

  Future<List<TimelapseShot>> shots(int userId, {String? spot}) async {
    final r = await db.query(
      'timelapse',
      where: spot == null ? 'user_id=?' : 'user_id=? AND spot=?',
      whereArgs: [userId, ?spot],
      orderBy: 'taken_at ASC, id ASC',
    );
    return r.map(TimelapseShot.fromMap).toList();
  }

  Future<List<String>> shotSpots(int userId) async {
    final r = await db.rawQuery('SELECT DISTINCT spot FROM timelapse WHERE user_id=? ORDER BY spot', [userId]);
    return r.map((m) => m['spot'] as String).toList();
  }

  // ---------- 백업용 전체 내보내기/가져오기 ----------
  static const backupTables = ['users', 'settings', 'items', 'notices', 'costs', 'timelapse'];

  Future<Map<String, List<Map<String, Object?>>>> dumpAll() async {
    final out = <String, List<Map<String, Object?>>>{};
    for (final t in backupTables) {
      try {
        out[t] = await db.query(t);
      } catch (_) {
        out[t] = []; // 오래된 자료 버전에는 없는 표
      }
    }
    return out;
  }

  Future<int> deletePracticeItems(int userId) => db.delete('items', where: 'user_id=? AND is_practice=1', whereArgs: [userId]);

  Future<void> restoreAll(Map<String, List<Map<String, Object?>>> data) async {
    await db.transaction((t) async {
      for (final table in backupTables) {
        await t.delete(table);
        for (final row in data[table] ?? const []) {
          await t.insert(table, row);
        }
      }
    });
  }

  Future<void> wipeAll() async {
    await db.transaction((t) async {
      for (final table in backupTables) {
        await t.delete(table);
      }
    });
  }
}
