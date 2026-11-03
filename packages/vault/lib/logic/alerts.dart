import '../core/clock.dart';
import '../data/models.dart';
import 'dates.dart';

enum AlertLevel {
  /// 노랑: 확인 필요(만료 임박)
  warning,

  /// 빨강: 내일·오늘 만료, 또는 이미 만료
  danger,
}

class AlertItem {
  const AlertItem({
    required this.key,
    required this.level,
    required this.title,
    required this.detail,
    required this.date,
    required this.daysLeft,
    required this.targetId,
    required this.isCredit,
  });

  /// 같은 알림을 두 번 보여 주지 않기 위한 키. 예) credit:id:7
  final String key;
  final AlertLevel level;
  final String title;
  final String detail;
  final DateTime date;
  final int daysLeft;
  final String targetId;
  final bool isCredit;
}

/// 크레딧·체험판: 7일 전, 1일 전, 만료 후 알림. 구독: 갱신 N일 전 알림.
List<AlertItem> computeAlerts(VaultData d, DateTime now) {
  final out = <AlertItem>[];
  for (final c in d.credits.where((c) => !c.done)) {
    final left = daysUntil(c.expiresAt, now);
    final snooze = c.snoozeUntil;
    final snoozed = snooze != null && dateOnly(now).isBefore(dateOnly(snooze));
    if (snoozed) continue; // "다시 알림" 날짜 전에는 조용히
    final reAlert = snooze != null; // 다시 알림 날짜가 되면 기간과 상관없이 한 번 더
    // 7일 넘게 남았거나, 만료 후 14일이 지난 항목은 알리지 않는다(다시 알림 제외).
    if (!reAlert && (left > 7 || left < -14)) continue;
    final stage =
        (reAlert ? 'again-${snooze.toIso8601String()}-' : '') +
        (left < 0 ? 'expired' : (left <= 1 ? '1' : '7'));
    final what = c.amountText.isEmpty
        ? c.kind.label
        : '${c.kind.label} ${c.amountText}';
    out.add(
      AlertItem(
        key: 'credit:${c.id}:$stage:${c.expiresAt.toIso8601String()}',
        level: left <= 1 ? AlertLevel.danger : AlertLevel.warning,
        title: '${c.serviceName} $what',
        detail: left < 0
            ? '${formatKoreanDate(c.expiresAt)}에 만료되었어요'
            : '${formatKoreanDate(c.expiresAt)} 만료 (${relativeDays(left)})',
        date: c.expiresAt,
        daysLeft: left,
        targetId: c.id,
        isCredit: true,
      ),
    );
  }
  for (final s in d.subscriptions.where((s) => !s.isPaused)) {
    final next = upcomingRenewal(s, now);
    final left = daysUntil(next, now);
    if (left > s.remindDaysBefore) continue;
    out.add(
      AlertItem(
        key: 'renew:${s.id}:${next.toIso8601String()}',
        level: s.isCancelCandidate ? AlertLevel.danger : AlertLevel.warning,
        title: '${s.serviceName} 결제 예정',
        detail: s.isCancelCandidate
            ? '해지 후보예요! ${formatKoreanDate(next)} 결제 전에 해지할지 정해 주세요'
            : '${formatKoreanDate(next)} 결제 (${relativeDays(left)})',
        date: next,
        daysLeft: left,
        targetId: s.id,
        isCredit: false,
      ),
    );
  }
  out.sort((a, b) {
    final l = b.level.index.compareTo(a.level.index);
    return l != 0 ? l : a.date.compareTo(b.date);
  });
  return out;
}

/// 아직 보여 주지 않은(밀린) 알림.
List<AlertItem> unseenAlerts(VaultData d, DateTime now) =>
    computeAlerts(d, now).where((a) => !d.seenAlerts.contains(a.key)).toList();

void markSeen(VaultData d, Iterable<AlertItem> alerts) {
  d.seenAlerts.addAll(alerts.map((a) => a.key));
  // 오래된 키가 무한히 쌓이지 않도록 지금 유효한 알림 키 + 최근 것만 남긴다.
  if (d.seenAlerts.length > 500) {
    final keep = d.seenAlerts.toList().sublist(d.seenAlerts.length - 300);
    d.seenAlerts
      ..clear()
      ..addAll(keep);
  }
}

/// 운영체제 알림을 예약할 시각들(오전 9시). 문구에는 개인 정보를 넣지 않는다.
List<DateTime> notificationTimes(VaultData d, DateTime now) {
  final times = <DateTime>{};
  DateTime at9(DateTime day) => DateTime(day.year, day.month, day.day, 9);
  for (final c in d.credits.where((c) => !c.done)) {
    for (final before in [7, 1]) {
      final t = at9(c.expiresAt.subtract(Duration(days: before)));
      if (t.isAfter(now)) times.add(t);
    }
    final snooze = c.snoozeUntil;
    if (snooze != null && at9(snooze).isAfter(now)) times.add(at9(snooze));
  }
  for (final s in d.subscriptions.where((s) => !s.isPaused)) {
    final next = upcomingRenewal(s, now);
    final t = at9(next.subtract(Duration(days: s.remindDaysBefore)));
    if (t.isAfter(now)) times.add(t);
  }
  final list = times.toList()..sort();
  return list.take(40).toList();
}

/// 홈 맨 위 "오늘 할 일" 한 건.
AlertItem? todayTask(VaultData d, DateTime now) {
  final all = computeAlerts(d, now);
  return all.isEmpty ? null : all.first;
}
