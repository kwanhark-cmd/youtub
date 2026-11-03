import '../core/clock.dart';
import '../data/models.dart';

DateTime addCycle(DateTime d, BillingCycle c) => switch (c) {
  BillingCycle.weekly => DateTime(d.year, d.month, d.day + 7),
  BillingCycle.monthly => addMonths(d, 1),
  BillingCycle.yearly => addMonths(d, 12),
};

DateTime addMonths(DateTime d, int months) {
  final y = d.year + (d.month - 1 + months) ~/ 12;
  final m = (d.month - 1 + months) % 12 + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d.day > lastDay ? lastDay : d.day);
}

/// 저장된 갱신일이 지났으면 결제 주기만큼 앞으로 굴려 "다음 갱신일"을 구한다.
DateTime upcomingRenewal(Subscription s, DateTime now) {
  final today = dateOnly(now);
  var d = dateOnly(s.nextRenewal);
  var guard = 0;
  while (d.isBefore(today) && guard++ < 2000) {
    d = addCycle(d, s.cycle);
  }
  return d;
}

/// 오늘부터 날짜까지 남은 날(오늘=0, 어제=-1). 서머타임에도 안전하게 UTC 로 계산.
int daysUntil(DateTime target, DateTime now) {
  final a = DateTime.utc(now.year, now.month, now.day);
  final b = DateTime.utc(target.year, target.month, target.day);
  return b.difference(a).inDays;
}

/// 이번 달 결제 예정(날짜 순).
List<(DateTime, Subscription)> renewalsInMonth(VaultData d, DateTime now) {
  final out = <(DateTime, Subscription)>[];
  final start = DateTime(now.year, now.month, 1);
  final end = DateTime(now.year, now.month + 1, 1);
  for (final s in d.subscriptions.where((s) => !s.isPaused)) {
    var day = dateOnly(s.nextRenewal);
    var guard = 0;
    while (day.isBefore(start) && guard++ < 2000) {
      day = addCycle(day, s.cycle);
    }
    while (day.isBefore(end) && guard++ < 4000) {
      out.add((day, s));
      day = addCycle(day, s.cycle);
    }
  }
  out.sort((a, b) => a.$1.compareTo(b.$1));
  return out;
}

String formatKoreanDate(DateTime d) => '${d.month}월 ${d.day}일';

String formatKoreanDateFull(DateTime d) => '${d.year}년 ${d.month}월 ${d.day}일';

String relativeDays(int days) {
  if (days == 0) return '오늘';
  if (days == 1) return '내일';
  if (days == 2) return '모레';
  if (days < 0) return '${-days}일 지남';
  return '$days일 남음';
}
