import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/db.dart';
import '../../core/failure.dart';
import '../../core/logger.dart';
import '../../core/retry.dart';
import '../../core/strings.dart';
import '../ai/brain.dart';
import '../settings/user_settings.dart';
import '../tools/tools_service.dart';
import '../voice/memos.dart';
import '../youtube/models.dart';
import '../youtube/quota.dart';
import '../youtube/youtube_service.dart';
import 'desc_template.dart';

enum ProductionStatus {
  /// 만든 직후 (영상 파일 없음 또는 확인 전)
  draft,

  /// 오늘 유튜브 한도가 모자라 내일 올리도록 준비해 둠 (사용자가 다시 "올리기" 를 눌러야 함)
  uploadTomorrow,

  /// 비공개로 올림 → 사용자 확인 대기
  uploadedPrivate,

  /// 사용자가 유튜브에서 확인하고 공개했다고 표시
  doneByUser,
}

/// 왜 만들지 못했는지 (사용자에게 그대로 보여 줄 안내).
class ProductionBlocked implements Exception {
  ProductionBlocked(this.message);
  final String message;
  @override
  String toString() => message;
}

class Production {
  Production(this.row);
  final Map<String, dynamic> row;

  int get id => row['id'] as int;
  String get channelId => row['channel_id'] as String;
  ContentFormat get format => ContentFormat.values.byName(row['format'] as String);
  String get title => row['title'] as String;
  String get description => row['description'] as String;
  List<String> get tags => (jsonDecode(row['tags_json'] as String) as List<dynamic>).map((e) => '$e').toList();
  String get thumbnailText => row['thumbnail_text'] as String;
  String get script => row['script'] as String;
  ProductionStatus get status => ProductionStatus.values.byName(row['status'] as String);
  String get videoPath => row['video_path'] as String;
  String get videoSource => row['video_source'] as String;
  String get aiLabelMethod => row['ai_label_method'] as String;
  String get uploadedVideoId => row['uploaded_video_id'] as String;
  String get uploadDay => row['upload_day'] as String;
  int? get cornerId => row['corner_id'] as int?;
  Map<String, dynamic> get extra => jsonDecode(row['extra_json'] as String) as Map<String, dynamic>;
  bool get hasVideo => videoPath.isNotEmpty && File(videoPath).existsSync();
  String get thumbPath => '${extra['thumb'] ?? ''}';
  bool get hasThumb => thumbPath.isNotEmpty && File(thumbPath).existsSync();

  /// 사진·이미지 게시물은 영상 업로드가 아니라 커뮤니티 게시물이라 사용자가 직접 올린다.
  bool get isUploadable => format != ContentFormat.image;

  String get studioUrl => 'https://studio.youtube.com/video/$uploadedVideoId/edit';
}

String formatLabel(ContentFormat f) => switch (f) {
  ContentFormat.shorts => S.formatShorts,
  ContentFormat.long => S.formatLong,
  ContentFormat.docu => S.formatDocu,
  ContentFormat.image => S.formatImage,
  ContentFormat.talk => S.formatTalk,
};

const aiLabelText = '\n\n※ 이 콘텐츠는 AI의 도움을 받아 만들었어요.';

/// 2단계: 채널 스타일에 맞춘 기획·제작 → 항상 비공개 업로드 → 확인 대기 목록.
class ProductionService {
  ProductionService({
    required this.db,
    required this.youtube,
    required this.brain,
    required this.settings,
    required this.memos,
    required this.tools,
    required this.quota,
    required this.now,
    required this.mediaDir,
    this.logger,
  });

  final AppDatabase db;
  final YouTubeService youtube;
  final Brain brain;
  final UserSettings settings;
  final MemoService memos;
  final ToolsService tools;
  final QuotaTracker quota;
  final DateTime Function() now;
  final String mediaDir;
  final AppLogger? logger;
  late final DescTemplateStore templates = DescTemplateStore(db);

  // ---------------- 읽기 ----------------
  List<Production> list({String? channelId, List<ProductionStatus>? statuses, int limit = 50, int offset = 0}) {
    final where = <String>[];
    final args = <Object?>[];
    if (channelId != null) {
      where.add('channel_id = ?');
      args.add(channelId);
    }
    if (statuses != null && statuses.isNotEmpty) {
      where.add('status IN (${List.filled(statuses.length, '?').join(',')})');
      args.addAll(statuses.map((e) => e.name));
    }
    final w = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    return db
        .select('SELECT * FROM productions $w ORDER BY id DESC LIMIT ? OFFSET ?', [...args, limit, offset])
        .map((r) => Production(Map<String, dynamic>.from(r)))
        .toList();
  }

  Production? byId(int id) {
    final r = db.select('SELECT * FROM productions WHERE id = ?', [id]);
    return r.isEmpty ? null : Production(Map<String, dynamic>.from(r.first));
  }

  /// 확인 대기 목록: 비공개로 올라가 사용자의 확인을 기다리는 것 + 내일 올리기로 미룬 것.
  List<Production> reviewList() =>
      list(statuses: [ProductionStatus.uploadedPrivate, ProductionStatus.uploadTomorrow], limit: 500);

  int madeToday() =>
      db.select('SELECT COUNT(*) AS n FROM productions WHERE day = ?', [dayKey(now())]).first['n'] as int;

  // ---------------- 만들기 ----------------
  /// 반복 방지 지문: 제목·키워드의 낱말 모음.
  static Set<String> fingerprintWords(String title, List<String> tags) => {
    for (final w in '$title ${tags.join(' ')}'.toLowerCase().split(RegExp(r'[\s|,()\[\].!?#:~\-]+')))
      if (w.length >= 2) w,
  };

  static double similarity(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    return a.intersection(b).length / a.union(b).length;
  }

  /// 같은 채널의 최근 콘텐츠와 너무 비슷하면 true.
  bool tooSimilar(String channelId, String title, List<String> tags, {double threshold = 0.6}) {
    final mine = fingerprintWords(title, tags);
    final since = dayKey(now().subtract(const Duration(days: 30)));
    final rows = db.select('SELECT fingerprint FROM productions WHERE channel_id = ? AND day >= ?', [channelId, since]);
    for (final r in rows) {
      final other = (r['fingerprint'] as String).split(' ').where((e) => e.isNotEmpty).toSet();
      if (similarity(mine, other) >= threshold) return true;
    }
    return false;
  }

  Future<Production> create({
    required String channelId,
    required ContentFormat format,
    String topic = '',
    int? memoId,
    int? cornerId,
    String extraMemo = '',
    Map<String, dynamic> extra = const {},
    bool countsTowardLimit = true,
    bool checkSimilarity = true,
  }) async {
    if (countsTowardLimit && madeToday() >= settings.produceDailyLimit) {
      throw ProductionBlocked(S.produceLimitReached);
    }
    final ch = youtube.channel(channelId);
    if (ch == null) throw AppFailure(FailureKind.notFound, 'channel');
    final style =
        StyleCard.decode(ch.styleJson) ??
        Brain.mockStyle(ch.title, youtube.videos(channelId, limit: 30).map((v) => v.title).toList());
    final memo = [if (memoId != null) memos.byId(memoId)?.text ?? '', extraMemo].where((e) => e.isNotEmpty).join('\n');
    final raw = await brain.planContent(style, format, topic, memo: memo);
    // 채널 설명 템플릿(고정 문구·링크·해시태그)을 설명 끝에 붙인다
    final plan = ContentPlan(
      title: raw.title,
      description: templates.get(channelId).applyTo(raw.description),
      tags: raw.tags,
      thumbnailText: raw.thumbnailText,
      script: raw.script,
    );
    if (checkSimilarity && tooSimilar(channelId, plan.title, plan.tags)) throw ProductionBlocked(S.produceTooSimilar);
    final id = db.insert(
      '''INSERT INTO productions(channel_id, format, topic, title, description, tags_json, thumbnail_text, script,
           memo_id, corner_id, fingerprint, status, ai_label_method, extra_json, day, created_at, updated_at)
         VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
      [
        channelId,
        format.name,
        topic,
        plan.title,
        plan.description,
        jsonEncode(plan.tags),
        plan.thumbnailText,
        plan.script,
        memoId,
        cornerId,
        fingerprintWords(plan.title, plan.tags).join(' '),
        ProductionStatus.draft.name,
        settings.aiLabelMethod,
        jsonEncode(extra),
        dayKey(now()),
        now().toIso8601String(),
        now().toIso8601String(),
      ],
    );
    if (memoId != null) memos.markUsed(memoId);
    logger?.info('콘텐츠 제작 #$id (${format.name})');
    return byId(id)!;
  }

  void updateText(
    int id, {
    String? title,
    String? description,
    List<String>? tags,
    String? thumbnailText,
    String? script,
  }) {
    final p = byId(id)!;
    db.execute(
      'UPDATE productions SET title=?, description=?, tags_json=?, thumbnail_text=?, script=?, updated_at=? WHERE id=?',
      [
        title ?? p.title,
        description ?? p.description,
        jsonEncode(tags ?? p.tags),
        thumbnailText ?? p.thumbnailText,
        script ?? p.script,
        now().toIso8601String(),
        id,
      ],
    );
  }

  void delete(int id) => db.execute('DELETE FROM productions WHERE id = ?', [id]);

  // ---------------- 영상 파일 ----------------
  static const videoExtensions = ['mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm'];

  /// 사용자가 직접 만든 영상 파일 넣기.
  void attachOwnVideo(int id, String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (!File(path).existsSync() || !videoExtensions.contains(ext)) {
      throw AppFailure(FailureKind.invalidInput, 'bad video');
    }
    db.execute('UPDATE productions SET video_path=?, video_source=?, updated_at=? WHERE id=?', [
      path,
      'own',
      now().toIso8601String(),
      id,
    ]);
  }

  /// 힉스필드 예상 크레딧과 남은 크레딧 (승인 화면에 보여 줄 값).
  Future<({int estimate, int left})> higgsfieldQuote(int id) async {
    final g = await tools.videoGenerator();
    final pr = byId(id)!;
    final secs = pr.format == ContentFormat.shorts ? 10 : 20;
    return (estimate: g.estimateCredits(pr.script, seconds: secs), left: await g.credits());
  }

  /// 힉스필드로 영상 만들기. [userApproved] 가 true 일 때만 실행 (크레딧 사용).
  Future<void> generateWithHiggsfield(int id, {required bool userApproved, CancelToken? cancel}) async {
    if (!userApproved) throw AppFailure(FailureKind.invalidInput, 'not approved');
    final g = await tools.videoGenerator();
    final pr = byId(id)!;
    final secs = pr.format == ContentFormat.shorts ? 10 : 20;
    final est = g.estimateCredits(pr.script, seconds: secs);
    if (await g.credits() < est) throw ProductionBlocked(S.produceHiggsfieldNotEnough);
    final job = await g.start('${pr.title}\n${pr.script}', seconds: secs);
    String? url;
    for (var i = 0; i < 120 && url == null; i++) {
      cancel?.throwIfCancelled();
      url = await withRetry(() => g.poll(job));
      if (url == null) await Future<void>.delayed(const Duration(seconds: 5));
    }
    if (url == null) throw AppFailure(FailureKind.timeout, 'generation');
    final file = File(p.join(mediaDir, 'production_$id.mp4'));
    await g.download(url, file);
    db.execute('UPDATE productions SET video_path=?, video_source=?, updated_at=? WHERE id=?', [
      file.path,
      'higgsfield',
      now().toIso8601String(),
      id,
    ]);
  }

  // ---------------- 썸네일 그림 ----------------
  static const imageExtensions = ['png', 'jpg', 'jpeg'];

  void _setExtra(int id, Map<String, dynamic> add) {
    final pr = byId(id)!;
    db.execute('UPDATE productions SET extra_json = ? WHERE id = ?', [
      jsonEncode({...pr.extra, ...add}),
      id,
    ]);
  }

  /// 썸네일 문구로 그림 만들기 (그리는 함수는 화면에서 넣어 준다: [render]).
  Future<String> makeThumbnail(int id, Future<List<int>> Function(String text, int seed) render) async {
    final pr = byId(id)!;
    final f = File(p.join(mediaDir, 'thumb_$id.png'));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(await render(pr.thumbnailText, id));
    _setExtra(id, {'thumb': f.path});
    return f.path;
  }

  /// 썸네일 비교: 문구와 색이 다른 썸네일 2개를 만든다 (A: 썸네일 문구, B: 제목 앞부분).
  /// 사용자가 하나를 고르면 [chooseThumbnail]. 자동 A/B 시험은 다음 단계.
  Future<List<String>> makeThumbnailChoices(int id, Future<List<int>> Function(String text, int seed) render) async {
    final pr = byId(id)!;
    final shortTitle = pr.title.length > 14 ? pr.title.substring(0, 14) : pr.title;
    final texts = [pr.thumbnailText.isEmpty ? shortTitle : pr.thumbnailText, shortTitle];
    if (texts[0] == texts[1]) texts[1] = '${texts[1]}!';
    final paths = <String>[];
    for (var i = 0; i < 2; i++) {
      final f = File(p.join(mediaDir, 'thumb_${id}_${i == 0 ? 'a' : 'b'}.png'));
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(await render(texts[i], id * 2 + i + 1));
      paths.add(f.path);
    }
    _setExtra(id, {'thumbChoices': paths});
    return paths;
  }

  void chooseThumbnail(int id, String path) {
    final choices = ((byId(id)!.extra['thumbChoices'] as List<dynamic>?) ?? const []).map((e) => '$e');
    if (!choices.contains(path)) throw AppFailure(FailureKind.invalidInput, 'not a choice');
    _setExtra(id, {'thumb': path, 'thumbChosen': path.endsWith('_a.png') ? 'A' : 'B'});
  }

  /// 사용자가 만든 썸네일 그림 넣기.
  void attachThumbnail(int id, String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (!File(path).existsSync() || !imageExtensions.contains(ext)) {
      throw AppFailure(FailureKind.invalidInput, 'bad image');
    }
    _setExtra(id, {'thumb': path});
  }

  // ---------------- 업로드 (항상 비공개) ----------------
  /// [userConfirmed] 는 화면(과 음성)에서 사용자가 "올리기" 를 확인했을 때만 true.
  /// 자동 작업 실행기는 이 함수를 부르지 않는다.
  Future<ProductionStatus> uploadPrivate(int id, {required bool userConfirmed, required String aiLabelMethod}) async {
    if (!userConfirmed) throw AppFailure(FailureKind.invalidInput, 'not confirmed');
    final pr = byId(id)!;
    if (!pr.isUploadable) throw AppFailure(FailureKind.invalidInput, 'image post');
    if (!pr.hasVideo) throw ProductionBlocked(S.produceNeedVideo);
    db.execute('UPDATE productions SET ai_label_method=? WHERE id=?', [aiLabelMethod, id]);
    if (!quota.canSpend(QuotaCost.upload)) {
      _setStatus(id, ProductionStatus.uploadTomorrow, uploadDay: dayKey(now().add(const Duration(days: 1))));
      return ProductionStatus.uploadTomorrow;
    }
    final desc = aiLabelMethod == 'description' && !pr.description.contains(aiLabelText.trim())
        ? '${pr.description}$aiLabelText'
        : pr.description;
    try {
      final vid = await youtube.uploadPrivate(
        pr.channelId,
        File(pr.videoPath),
        UploadMeta(
          title: pr.title,
          description: desc,
          tags: pr.tags,
          containsSyntheticMedia: aiLabelMethod == 'setting',
        ),
      );
      db.execute('UPDATE productions SET uploaded_video_id=?, description=? WHERE id=?', [vid, desc, id]);
      if (pr.hasThumb) {
        try {
          await youtube.setThumbnail(pr.channelId, vid, File(pr.thumbPath));
          _setExtra(id, {'thumbUploaded': true});
        } on AppFailure catch (e) {
          // 썸네일만 실패한 경우: 영상은 올라갔으니 안내만 (유튜브 스튜디오에서 직접 넣을 수 있음)
          _setExtra(id, {'thumbUploaded': false, 'thumbError': e.userMessage});
          logger?.warn('썸네일 올리기 실패: ${e.kind.name}');
        }
      }
      _setStatus(id, ProductionStatus.uploadedPrivate);
      return ProductionStatus.uploadedPrivate;
    } on AppFailure catch (e) {
      if (e.kind == FailureKind.quotaExceeded) {
        _setStatus(id, ProductionStatus.uploadTomorrow, uploadDay: dayKey(now().add(const Duration(days: 1))));
        return ProductionStatus.uploadTomorrow;
      }
      rethrow;
    }
  }

  /// 사용자가 유튜브에서 직접 확인·공개했다고 표시 (앱은 공개 전환을 하지 않는다).
  void markDoneByUser(int id) => _setStatus(id, ProductionStatus.doneByUser);

  void _setStatus(int id, ProductionStatus s, {String? uploadDay}) => db.execute(
    'UPDATE productions SET status=?, upload_day=COALESCE(?, upload_day), updated_at=? WHERE id=?',
    [s.name, uploadDay, now().toIso8601String(), id],
  );

  // ---------------- 브리핑·음성 연결 ----------------
  List<String> briefingItems() {
    final out = <String>[];
    final waiting = list(statuses: [ProductionStatus.uploadedPrivate], limit: 500).length;
    if (waiting > 0) out.add('확인을 기다리는 비공개 영상이 $waiting개 있어요');
    final ready = list(
      statuses: [ProductionStatus.uploadTomorrow],
      limit: 500,
    ).where((e) => e.uploadDay.compareTo(dayKey(now())) <= 0).length;
    if (ready > 0) out.add('어제 미뤄 둔 업로드 $ready개를 오늘 올릴 수 있어요. 확인 대기 목록에서 "올리기"를 눌러 주세요');
    final left = settings.produceDailyLimit - madeToday();
    if (left > 0) out.add('오늘 콘텐츠를 $left개 더 만들 수 있어요');
    return out;
  }
}
