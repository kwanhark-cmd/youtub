import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/db.dart';
import '../../core/failure.dart';
import '../../core/logger.dart';
import '../ai/brain.dart';
import '../production/production_service.dart';
import '../voice/memos.dart';
import 'material_source.dart';

class Corner {
  Corner(this.id, this.name, this.channelId);
  final int id;
  final String name;
  final String channelId;
}

class CornerItem {
  CornerItem(this.row);
  final Map<String, dynamic> row;
  int get id => row['id'] as int;
  String get kind => row['kind'] as String;
  String get path => row['path'] as String;
  String get title => row['title'] as String;
  String get text => row['text'] as String;
  String get source => row['source'] as String;

  /// 'own' | 'licensed' | 'unknown'(확인 필요) | 'approved'(사용자가 사용 허락) | 'excluded'(빼기)
  String get copyright => row['copyright'] as String;
  bool get needsCheck => copyright == 'unknown';
  bool get usable => copyright == 'own' || copyright == 'licensed' || copyright == 'approved';
}

/// 4단계: 사용자 자신의 이야기를 콘텐츠로 (코너 이름·채널은 사용자가 정함).
class CornerService {
  CornerService({
    required this.db,
    required this.production,
    required this.memos,
    required this.now,
    required this.mediaDir,
    this.logger,
  });

  final AppDatabase db;
  final ProductionService production;
  final MemoService memos;
  final DateTime Function() now;
  final String mediaDir;
  final AppLogger? logger;

  List<Corner> corners() => db
      .select('SELECT * FROM corners ORDER BY id')
      .map((r) => Corner(r['id'] as int, r['name'] as String, r['channel_id'] as String))
      .toList();

  Corner? corner(int id) {
    final l = corners().where((c) => c.id == id);
    return l.isEmpty ? null : l.first;
  }

  Corner create(String name, String channelId) {
    if (name.trim().isEmpty || channelId.isEmpty) throw AppFailure(FailureKind.invalidInput, 'corner');
    final id = db.insert('INSERT INTO corners(name, channel_id, created_at) VALUES(?,?,?)', [
      name.trim(),
      channelId,
      now().toIso8601String(),
    ]);
    return corner(id)!;
  }

  void rename(int id, String name, String channelId) =>
      db.execute('UPDATE corners SET name = ?, channel_id = ? WHERE id = ?', [name.trim(), channelId, id]);

  void delete(int id) => db.transaction(() {
    db.execute('DELETE FROM corner_items WHERE corner_id = ?', [id]);
    db.execute('DELETE FROM corners WHERE id = ?', [id]);
  });

  List<CornerItem> items(int cornerId) => db
      .select('SELECT * FROM corner_items WHERE corner_id = ? ORDER BY id', [cornerId])
      .map((r) => CornerItem(Map<String, dynamic>.from(r)))
      .toList();

  CornerItem _add(
    int cornerId, {
    required String kind,
    String path = '',
    String title = '',
    String text = '',
    String source = 'own',
    String copyright = 'own',
  }) {
    final id = db.insert(
      'INSERT INTO corner_items(corner_id, kind, path, title, text, source, copyright, created_at) VALUES(?,?,?,?,?,?,?,?)',
      [cornerId, kind, path, title, text, source, copyright, now().toIso8601String()],
    );
    return CornerItem(Map<String, dynamic>.from(db.select('SELECT * FROM corner_items WHERE id = ?', [id]).first));
  }

  /// 사용자가 직접 찍은 영상. 파일 이름이 방송·영화 등으로 보이면 확인을 받는다.
  CornerItem addOwnVideo(int cornerId, String path) {
    if (!File(path).existsSync() || kindOf(path) != 'video') throw AppFailure(FailureKind.invalidInput, 'video');
    return _add(
      cornerId,
      kind: 'video',
      path: path,
      title: p.basenameWithoutExtension(path),
      copyright: looksCopyrighted(path) ? 'unknown' : 'own',
    );
  }

  CornerItem addMemo(int cornerId, int memoId) {
    final m = memos.byId(memoId);
    if (m == null) throw AppFailure(FailureKind.notFound, 'memo');
    return _add(cornerId, kind: 'memo', text: m.text, title: '음성 메모', source: 'memo:$memoId');
  }

  CornerItem addText(int cornerId, String text) => _add(cornerId, kind: 'text', text: text.trim(), title: '이야기');

  /// 폴더(또는 3·4번 앱)에서 소재 가져오기. 저작권 확인이 필요한 소재 개수도 돌려준다.
  Future<({int added, int needCheck})> importFrom(int cornerId, MaterialSource source) async {
    final list = await source.list();
    var check = 0;
    db.transaction(() {
      for (final m in list) {
        if (m.needsCopyrightCheck) check++;
        _add(
          cornerId,
          kind: m.kind,
          path: m.path,
          title: m.title,
          text: m.note,
          source: 'folder:${m.sourceApp.isEmpty ? source.name : m.sourceApp}',
          copyright: m.needsCopyrightCheck ? 'unknown' : m.copyright,
        );
      }
    });
    return (added: list.length, needCheck: check);
  }

  /// 저작권 확인 결과: true → 사용, false → 빼기.
  void decideCopyright(int itemId, bool allow) =>
      db.execute('UPDATE corner_items SET copyright = ? WHERE id = ?', [allow ? 'approved' : 'excluded', itemId]);

  void removeItem(int itemId) => db.execute('DELETE FROM corner_items WHERE id = ?', [itemId]);

  /// 영상 길이를 모를 때: 글자 수로 짐작 (한 글자 0.25초, 최소 15초).
  static Duration estimateDuration(String text) {
    final ms = (text.length * 250).clamp(15000, 3600000);
    return Duration(milliseconds: ms);
  }

  /// 영상 + 음성 메모 → 자막·제목·설명·키워드·썸네일을 여러 형식으로 자동 제작.
  /// 저작권 확인이 끝나지 않은 소재가 있으면 만들지 않는다 (자동 삽입 금지).
  Future<List<Production>> make(
    int cornerId, {
    List<ContentFormat> formats = const [ContentFormat.shorts, ContentFormat.long, ContentFormat.image],
  }) async {
    final c = corner(cornerId);
    if (c == null) throw AppFailure(FailureKind.notFound, 'corner');
    final all = items(cornerId);
    final pending = all.where((i) => i.needsCheck).toList();
    if (pending.isNotEmpty) {
      throw ProductionBlocked('저작권 확인이 필요한 소재가 ${pending.length}개 있어요. 먼저 사용 여부를 정해 주세요.');
    }
    final usable = all.where((i) => i.usable).toList();
    if (usable.isEmpty) throw ProductionBlocked('만들 소재가 없어요. 영상이나 음성 메모를 먼저 넣어 주세요.');
    final left = production.settings.produceDailyLimit - production.madeToday();
    if (left < formats.length) {
      throw ProductionBlocked('오늘 만들 수 있는 개수가 $left개 남았어요. 형식을 줄이거나 설정에서 한도를 늘려 주세요.');
    }
    final story = usable.where((i) => i.text.isNotEmpty).map((i) => i.text).join('\n');
    final video = usable.where((i) => i.kind == 'video' && File(i.path).existsSync()).firstOrNull;
    final topic = story.isNotEmpty ? '${c.name}: ${story.split(RegExp(r'[.!?\n]')).first.trim()}' : c.name;
    final srt = story.isEmpty ? '' : Brain.makeSrt(story, estimateDuration(story));
    String srtPath = '';
    if (srt.isNotEmpty) {
      final f = File(p.join(mediaDir, 'corner_${cornerId}_${now().millisecondsSinceEpoch}.srt'));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(srt);
      srtPath = f.path;
    }
    final out = <Production>[];
    for (var i = 0; i < formats.length; i++) {
      final pr = await production.create(
        channelId: c.channelId,
        format: formats[i],
        topic: topic,
        cornerId: cornerId,
        extraMemo: story,
        extra: {'srt': srtPath, 'srtText': srt, 'cornerName': c.name},
        checkSimilarity: i == 0,
      );
      if (video != null && pr.isUploadable) production.attachOwnVideo(pr.id, video.path);
      out.add(production.byId(pr.id)!);
    }
    db.execute(
      'UPDATE corner_items SET used = 1 WHERE corner_id = ? AND copyright IN (\'own\',\'licensed\',\'approved\')',
      [cornerId],
    );
    logger?.info('코너 제작: ${out.length}개');
    return out;
  }
}
