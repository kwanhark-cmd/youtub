import '../../core/db.dart';
import '../../core/failure.dart';
import '../../core/logger.dart';
import '../../core/retry.dart';
import '../../core/strings.dart';
import '../ai/brain.dart';
import '../settings/user_settings.dart';
import '../youtube/models.dart';
import '../youtube/youtube_service.dart';

enum EditStatus { applied, reverted, failed }

class EditRecord {
  EditRecord({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.parentId,
    required this.before,
    required this.after,
    required this.viewsBefore,
    required this.viewsAfter,
    required this.status,
    required this.reason,
    required this.day,
    required this.createdAt,
    required this.revertedAt,
  });

  final int id;
  final String targetType; // 'video' | 'post'
  final String targetId;
  final String parentId; // 채널 ID 또는 블로그 ID
  final VideoMeta before;
  final VideoMeta after;
  final int viewsBefore;
  final int? viewsAfter;
  final EditStatus status;
  final String reason;
  final String day;
  final DateTime createdAt;
  final DateTime? revertedAt;

  static EditRecord fromRow(Map<String, dynamic> r) => EditRecord(
    id: r['id'] as int,
    targetType: r['target_type'] as String,
    targetId: r['target_id'] as String,
    parentId: r['parent_id'] as String,
    before: VideoMeta.decode(r['before_json'] as String),
    after: VideoMeta.decode(r['after_json'] as String),
    viewsBefore: r['views_before'] as int,
    viewsAfter: r['views_after'] as int?,
    status: EditStatus.values.byName(r['status'] as String),
    reason: r['reason'] as String,
    day: r['day'] as String,
    createdAt: DateTime.parse(r['created_at'] as String),
    revertedAt: r['reverted_at'] == null ? null : DateTime.parse(r['reverted_at'] as String),
  );
}

class EditProposal {
  EditProposal(this.video, this.after);
  final YtVideo video;
  final VideoMeta after;
}

enum RevertOutcome { reverted, alreadyReverted, newerEditExists, conflict, failed }

class RevertResult {
  RevertResult(this.outcome, [this.failure]);
  final RevertOutcome outcome;
  final AppFailure? failure;
  bool get ok => outcome == RevertOutcome.reverted || outcome == RevertOutcome.alreadyReverted;
}

/// 수정 내역 저장소 (영상·블로그 글 공통). 모든 자동 수정은 여기에 원본이 먼저 기록된다.
class EditLog {
  EditLog(this.db, this.now);
  final AppDatabase db;
  final DateTime Function() now;

  int record({
    required String targetType,
    required String targetId,
    required String parentId,
    required VideoMeta before,
    required VideoMeta after,
    required int viewsBefore,
    required EditStatus status,
    String reason = '',
  }) => db.insert(
    '''INSERT INTO edits(target_type, target_id, parent_id, before_json, after_json, views_before, status, reason, day, created_at)
           VALUES(?,?,?,?,?,?,?,?,?,?)''',
    [
      targetType,
      targetId,
      parentId,
      before.encode(),
      after.encode(),
      viewsBefore,
      status.name,
      reason,
      dayKey(now()),
      now().toIso8601String(),
    ],
  );

  void setStatus(int id, EditStatus s, {String reason = ''}) => db.execute(
    'UPDATE edits SET status = ?, reason = ?, reverted_at = ? WHERE id = ?',
    [s.name, reason, s == EditStatus.reverted ? now().toIso8601String() : null, id],
  );

  EditRecord? byId(int id) {
    final r = db.select('SELECT * FROM edits WHERE id = ?', [id]);
    return r.isEmpty ? null : EditRecord.fromRow(Map<String, dynamic>.from(r.first));
  }

  List<EditRecord> list({
    String? day,
    String? targetType,
    String? parentId,
    String? targetId,
    int limit = 200,
    int offset = 0,
  }) {
    final where = <String>[];
    final args = <Object?>[];
    if (day != null) {
      where.add('day = ?');
      args.add(day);
    }
    if (targetType != null) {
      where.add('target_type = ?');
      args.add(targetType);
    }
    if (parentId != null) {
      where.add('parent_id = ?');
      args.add(parentId);
    }
    if (targetId != null) {
      where.add('target_id = ?');
      args.add(targetId);
    }
    final w = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    return db
        .select('SELECT * FROM edits $w ORDER BY id DESC LIMIT ? OFFSET ?', [...args, limit, offset])
        .map((r) => EditRecord.fromRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// 이 대상에 이 수정보다 나중에 적용된(아직 되돌리지 않은) 수정이 있는가.
  bool hasNewerApplied(EditRecord e) => db.select(
    "SELECT 1 FROM edits WHERE target_type = ? AND target_id = ? AND id > ? AND status = 'applied'",
    [e.targetType, e.targetId, e.id],
  ).isNotEmpty;

  /// 최근 [days] 일 안에 수정한 대상 ID.
  Set<String> recentlyEdited(String targetType, int days) {
    final since = dayKey(now().subtract(Duration(days: days)));
    return db
        .select("SELECT DISTINCT target_id FROM edits WHERE target_type = ? AND day >= ? AND status = 'applied'", [
          targetType,
          since,
        ])
        .map((r) => r['target_id'] as String)
        .toSet();
  }

  int countOn(String day, {String? parentId, String targetType = 'video'}) {
    final r = parentId == null
        ? db.select("SELECT COUNT(*) AS n FROM edits WHERE day = ? AND target_type = ? AND status != 'failed'", [
            day,
            targetType,
          ])
        : db.select(
            "SELECT COUNT(*) AS n FROM edits WHERE day = ? AND target_type = ? AND parent_id = ? AND status != 'failed'",
            [day, targetType, parentId],
          );
    return r.first['n'] as int;
  }

  void setViewsAfter(int id, int views) => db.execute('UPDATE edits SET views_after = ? WHERE id = ?', [views, id]);
}

/// 기존 영상 제목·설명·키워드 자동 수정 + 되돌리기.
class EditService {
  EditService({
    required this.log,
    required this.youtube,
    required this.brain,
    required this.settings,
    required this.now,
    this.logger,
  });

  final EditLog log;
  final YouTubeService youtube;
  final Brain brain;
  final UserSettings settings;
  final DateTime Function() now;
  final AppLogger? logger;

  /// 오늘 이 채널에서 더 수정할 수 있는 개수.
  int remainingToday(String channelId) {
    final limit = settings.effectiveEditsPerDay(now());
    final used = log.countOn(dayKey(now()), parentId: channelId);
    return (limit - used).clamp(0, limit);
  }

  /// 수정 제안 만들기 (아직 유튜브에 반영 안 함).
  /// 최근 30일 안에 수정한 영상은 빼고, 조회수가 낮은 영상부터.
  Future<List<EditProposal>> plan(String channelId, {CancelToken? cancel}) async {
    final n = remainingToday(channelId);
    if (n <= 0) return [];
    final ch = youtube.channel(channelId);
    if (ch == null) return [];
    final style =
        StyleCard.decode(ch.styleJson) ??
        Brain.mockStyle(ch.title, youtube.videos(channelId, limit: 30).map((v) => v.title).toList());
    final recent = log.recentlyEdited('video', 30);
    final candidates =
        youtube
            .videos(channelId, limit: 500)
            .where((v) => !recent.contains(v.videoId) && v.privacy == 'public')
            .toList()
          ..sort((a, b) => a.viewCount.compareTo(b.viewCount));
    final out = <EditProposal>[];
    for (final v in candidates) {
      if (out.length >= n) break;
      cancel?.throwIfCancelled();
      final m = await brain.suggestMeta(v, style);
      if (m != null) out.add(EditProposal(v, m));
    }
    return out;
  }

  /// 제안을 유튜브에 반영. 원본을 먼저 기록하고 나서 바꾼다.
  /// 한도 초과면 남은 것은 멈추고 [deferred] 로 돌려준다 (다음 날 다시 계획).
  Future<({int applied, int failed, int deferred})> apply(
    List<EditProposal> proposals, {
    CancelToken? cancel,
    void Function(double, String)? progress,
  }) async {
    var applied = 0, failed = 0, deferred = 0;
    for (var i = 0; i < proposals.length; i++) {
      final p = proposals[i];
      if (cancel?.isCancelled ?? false) break;
      if (remainingToday(p.video.channelId) <= 0) {
        deferred++;
        continue;
      }
      final current = youtube.video(p.video.videoId) ?? p.video;
      final id = log.record(
        targetType: 'video',
        targetId: current.videoId,
        parentId: current.channelId,
        before: current.meta,
        after: p.after,
        viewsBefore: current.viewCount,
        status: EditStatus.failed,
        reason: '진행 중',
      );
      try {
        await youtube.updateMeta(current.videoId, p.after);
        log.setStatus(id, EditStatus.applied);
        applied++;
      } on AppFailure catch (e) {
        log.setStatus(id, EditStatus.failed, reason: e.userMessage);
        if (e.kind == FailureKind.quotaExceeded) {
          deferred += proposals.length - i - 1;
          logger?.warn('수정 중 한도 초과 → 남은 ${proposals.length - i - 1}개 내일로');
          failed++;
          break;
        }
        failed++;
        logger?.warn('수정 실패: ${e.kind.name}');
      }
      progress?.call((i + 1) / proposals.length, '${i + 1}/${proposals.length}');
    }
    return (applied: applied, failed: failed, deferred: deferred);
  }

  /// 되돌리기.
  /// - 이미 되돌렸으면 아무것도 안 함 (두 번 눌러도 안전)
  /// - 같은 영상에 더 최근 수정이 있으면 그것부터 되돌리라고 안내
  /// - 수정 뒤에 유튜브에서 내용이 또 바뀌었으면 [force] 없이는 되돌리지 않음 (사용자 수정 보호)
  Future<RevertResult> revert(int editId, {bool force = false}) async {
    final e = log.byId(editId);
    if (e == null) return RevertResult(RevertOutcome.failed, AppFailure(FailureKind.notFound));
    if (e.status == EditStatus.reverted) return RevertResult(RevertOutcome.alreadyReverted);
    if (e.status == EditStatus.failed) {
      // 실패한 수정은 유튜브에 반영되지 않았으므로 되돌릴 것이 없다.
      log.setStatus(e.id, EditStatus.reverted, reason: '반영되지 않았던 수정');
      return RevertResult(RevertOutcome.alreadyReverted);
    }
    if (log.hasNewerApplied(e)) return RevertResult(RevertOutcome.newerEditExists);
    try {
      if (!force) {
        final remote = await youtube.fetchRemote(e.targetId);
        if (remote != null && !remote.meta.sameAs(e.after)) {
          return RevertResult(RevertOutcome.conflict);
        }
      }
      await youtube.updateMeta(e.targetId, e.before);
      log.setStatus(e.id, EditStatus.reverted);
      logger?.info('되돌리기 완료 #${e.id}');
      return RevertResult(RevertOutcome.reverted);
    } on AppFailure catch (f) {
      return RevertResult(RevertOutcome.failed, f);
    }
  }

  /// 하루치 수정을 최근 것부터 차례로 모두 되돌린다.
  Future<({int reverted, int conflicts, int failed})> revertDay(String day, {bool force = false}) async {
    var reverted = 0, conflicts = 0, failed = 0;
    final list = log.list(day: day, targetType: 'video').where((e) => e.status == EditStatus.applied).toList()
      ..sort((a, b) => b.id.compareTo(a.id));
    for (final e in list) {
      final r = await revert(e.id, force: force);
      if (r.outcome == RevertOutcome.reverted) {
        reverted++;
      } else if (r.outcome == RevertOutcome.conflict) {
        conflicts++;
      } else if (!r.ok) {
        failed++;
      }
    }
    return (reverted: reverted, conflicts: conflicts, failed: failed);
  }

  /// 수정 전후 조회수 비교용: 저장된 최신 조회수로 views_after 를 채운다.
  void updateViewsAfter() {
    for (final e in log.list(targetType: 'video', limit: 1000)) {
      if (e.status != EditStatus.applied) continue;
      final v = youtube.video(e.targetId);
      if (v != null) log.setViewsAfter(e.id, v.viewCount);
    }
  }

  /// 매일 수정 내역 요약 (화면 + 음성).
  String dailySummary(String day) {
    final list = log.list(day: day, targetType: 'video');
    if (list.isEmpty) return S.editsNone;
    final applied = list.where((e) => e.status == EditStatus.applied).length;
    final reverted = list.where((e) => e.status == EditStatus.reverted).length;
    final failed = list.where((e) => e.status == EditStatus.failed).length;
    final buf = StringBuffer('$day 수정 요약: 수정 $applied개');
    if (reverted > 0) buf.write(', 되돌림 $reverted개');
    if (failed > 0) buf.write(', 실패 $failed개');
    buf.write('. ');
    final byChannel = <String, int>{};
    for (final e in list.where((e) => e.status == EditStatus.applied)) {
      final t = youtube.channel(e.parentId)?.title ?? '알 수 없는 채널';
      byChannel[t] = (byChannel[t] ?? 0) + 1;
    }
    byChannel.forEach((k, v) => buf.write('$k $v개. '));
    final compared = log
        .list(targetType: 'video', limit: 500)
        .where((e) => e.status == EditStatus.applied && e.viewsAfter != null);
    if (compared.isNotEmpty) {
      final gain = compared.fold<int>(0, (s, e) => s + (e.viewsAfter! - e.viewsBefore));
      buf.write('지금까지 수정한 영상들의 조회수는 수정 뒤 모두 합쳐 ${S.num(gain)}회 늘었어요.');
    }
    return buf.toString().trim();
  }
}
