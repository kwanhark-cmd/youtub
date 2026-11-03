import 'dart:convert';

import '../../core/db.dart';
import '../../core/failure.dart';
import '../../core/logger.dart';
import '../../core/retry.dart';
import '../../core/strings.dart';
import '../ai/ai_service.dart';
import '../edits/edit_service.dart';
import '../settings/user_settings.dart';
import '../youtube/youtube_service.dart';
import 'notifier.dart';

class Job {
  Job(this.id, this.kind, this.payload, this.status, this.runDay, this.attempts, this.lastError);
  final int id;
  final String kind;
  final Map<String, dynamic> payload;
  final String status; // waiting | done | failed | needsUser
  final String runDay;
  final int attempts;
  final String lastError;
}

/// 작업 대기열. 한도가 모자란 작업은 다음 날로 넘긴다.
class JobQueue {
  JobQueue(this.db, this.now);
  final AppDatabase db;
  final DateTime Function() now;

  int add(String kind, Map<String, dynamic> payload, {DateTime? runOn, String status = 'waiting'}) => db.insert(
    'INSERT INTO jobs(kind, payload, status, run_day, created_at, updated_at) VALUES(?,?,?,?,?,?)',
    [kind, jsonEncode(payload), status, dayKey(runOn ?? now()), now().toIso8601String(), now().toIso8601String()],
  );

  List<Job> due() => _q("SELECT * FROM jobs WHERE status = 'waiting' AND run_day <= ? ORDER BY id", [dayKey(now())]);
  List<Job> byStatus(String status) => _q('SELECT * FROM jobs WHERE status = ? ORDER BY id', [status]);
  List<Job> all() => _q('SELECT * FROM jobs ORDER BY id DESC LIMIT 200', const []);

  List<Job> _q(String sql, List<Object?> args) => db
      .select(sql, args)
      .map(
        (r) => Job(
          r['id'] as int,
          r['kind'] as String,
          jsonDecode(r['payload'] as String) as Map<String, dynamic>,
          r['status'] as String,
          r['run_day'] as String,
          r['attempts'] as int,
          r['last_error'] as String,
        ),
      )
      .toList();

  void deferToTomorrow(int id, String reason) => db.execute(
    'UPDATE jobs SET run_day = ?, attempts = attempts + 1, last_error = ?, updated_at = ? WHERE id = ?',
    [dayKey(now().add(const Duration(days: 1))), reason, now().toIso8601String(), id],
  );

  void setStatus(int id, String status, {String error = ''}) => db.execute(
    'UPDATE jobs SET status = ?, last_error = ?, attempts = attempts + 1, updated_at = ? WHERE id = ?',
    [status, error, now().toIso8601String(), id],
  );

  void log(String message) =>
      db.execute('INSERT INTO job_log(at, message) VALUES(?, ?)', [now().toIso8601String(), redact(message)]);

  List<String> recentLog([int n = 50]) => db
      .select('SELECT at, message FROM job_log ORDER BY id DESC LIMIT ?', [n])
      .map((r) => '${(r['at'] as String).substring(0, 16).replaceAll('T', ' ')}  ${r['message']}')
      .toList();
}

typedef JobHandler = Future<void> Function(Job job, CancelToken cancel);

/// 자동 작업 실행기.
/// - 기본 꺼짐. 설정에서 켜고 실행 시간대를 정한다.
/// - 윈도우·맥(·리눅스) 컴퓨터에서만 실행. 휴대폰에서는 실행하지 않는다.
/// - 실행 전후에 알림.
/// - 실제 업로드·삭제·공개는 하지 않는다 (업로드는 사용자 확인이 필요한 작업으로 표시만).
class JobRunner {
  JobRunner({
    required this.settings,
    required this.queue,
    required this.youtube,
    required this.edits,
    required this.ai,
    required this.notifier,
    required this.now,
    required this.isDesktop,
    this.logger,
    String Function()? appName,
  }) : appName = appName ?? (() => S.appName);

  final UserSettings settings;
  final JobQueue queue;
  final YouTubeService youtube;
  final EditService edits;
  final AiService ai;
  final Notifier notifier;
  final DateTime Function() now;
  final bool isDesktop;
  final AppLogger? logger;

  /// 알림 제목 (앱 꾸미기의 이름)
  final String Function() appName;

  /// 다른 단계에서 작업 종류를 추가한다 (예: 'blogEdits').
  final Map<String, JobHandler> handlers = {};

  /// 매일 자동 작업 때 함께 할 일 (예: 3단계 블로그 글 다듬기). 돌려주는 값은 기록할 한 줄.
  final List<Future<String> Function(CancelToken cancel)> dailyTasks = [];

  bool running = false;
  CancelToken? _cancel;
  double progress = 0;
  String progressText = '';
  void Function()? onChange;

  bool inWindow(DateTime t) {
    final from = settings.runnerFromHour, to = settings.runnerToHour;
    final h = t.hour;
    return from <= to ? (h >= from && h < to) : (h >= from || h < to);
  }

  /// 1분마다 불린다. 조건이 맞을 때만 하루 한 번 실행.
  Future<bool> tick() async {
    if (!settings.runnerEnabled || !isDesktop || running) return false;
    final t = now();
    if (!inWindow(t)) return false;
    if (settings.lastRunnerDay == dayKey(t)) return false;
    await runNow();
    return true;
  }

  void cancel() => _cancel?.cancel();

  Future<({int edits, int deferred})> runNow() async {
    if (running) return (edits: 0, deferred: 0);
    running = true;
    _cancel = CancelToken();
    final cancel = _cancel!;
    var editsDone = 0, deferred = 0;
    settings.lastRunnerDay = dayKey(now());
    _set(0, S.runnerStarting);
    await notifier.show(appName(), S.runnerStarting);
    queue.log(S.runnerStarting);
    try {
      final chans = youtube.channels();
      // 1) 채널 새로 불러오기 → 2) 수정 계획·적용
      for (var i = 0; i < chans.length; i++) {
        if (cancel.isCancelled) break;
        final c = chans[i];
        _set(i / (chans.length + 1), '${c.title} 확인 중');
        try {
          await youtube.syncChannel(c.channelId, cancel: cancel);
          if (ai.overLimit && !ai.isPracticeMode) {
            queue.log(S.runnerCostStop);
            await notifier.show(appName(), S.runnerCostStop);
            break;
          }
          final plan = await edits.plan(c.channelId, cancel: cancel);
          final r = await edits.apply(plan, cancel: cancel);
          editsDone += r.applied;
          deferred += r.deferred;
          queue.log('${c.title}: 수정 ${r.applied}개, 실패 ${r.failed}개${r.deferred > 0 ? ', 내일로 ${r.deferred}개' : ''}');
          if (r.deferred > 0) break; // 한도 소진
        } on AppFailure catch (e) {
          if (e.kind == FailureKind.cancelled) break;
          if (e.kind == FailureKind.quotaExceeded) {
            queue.log(S.runnerQuotaDefer);
            deferred++;
            break;
          }
          if (e.kind == FailureKind.costLimit) {
            queue.log(S.runnerCostStop);
            await notifier.show(appName(), S.runnerCostStop);
            break;
          }
          // 오류는 기록하고 다음 채널 계속
          queue.log('${c.title}: ${e.userMessage}');
        } catch (e, st) {
          logger?.error('자동 작업 오류', e, st);
          queue.log('${c.title}: ${S.errorGeneric}');
        }
      }
      edits.updateViewsAfter();
      for (final task in dailyTasks) {
        if (cancel.isCancelled) break;
        try {
          queue.log(await task(cancel));
        } on AppFailure catch (e) {
          queue.log(e.userMessage);
        } catch (e, st) {
          logger?.error('추가 작업 오류', e, st);
          queue.log(S.errorGeneric);
        }
      }
      // 3) 대기열 작업
      for (final job in queue.due()) {
        if (cancel.isCancelled) break;
        final h = handlers[job.kind];
        if (h == null) {
          queue.setStatus(job.id, 'failed', error: 'unknown job');
          continue;
        }
        try {
          await h(job, cancel);
          queue.setStatus(job.id, 'done');
        } on AppFailure catch (e) {
          if (e.kind == FailureKind.quotaExceeded) {
            queue.deferToTomorrow(job.id, e.userMessage);
            queue.log(S.runnerQuotaDefer);
            deferred++;
          } else if (e.isRetryable && job.attempts < 3) {
            queue.deferToTomorrow(job.id, e.userMessage);
          } else {
            queue.setStatus(job.id, 'failed', error: e.userMessage);
          }
        } catch (e, st) {
          logger?.error('작업 오류', e, st);
          queue.setStatus(job.id, 'failed', error: S.errorGeneric);
        }
      }
    } finally {
      final msg = cancel.isCancelled ? S.progressCancelled : S.runnerDone(editsDone, deferred);
      queue.log(msg);
      await notifier.show(appName(), msg);
      running = false;
      _set(1, msg);
    }
    return (edits: editsDone, deferred: deferred);
  }

  void _set(double p, String t) {
    progress = p;
    progressText = t;
    onChange?.call();
  }
}
