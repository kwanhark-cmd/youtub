import '../core/crypto/password_tools.dart';
import '../data/models.dart';
import 'dates.dart';
import 'services_catalog.dart';

class UnusedSuggestion {
  const UnusedSuggestion(
    this.subscription,
    this.daysSinceUse,
    this.neverRecorded,
  );
  final Subscription subscription;

  /// 마지막 사용 후 지난 날. 기록이 없으면 등록 후 지난 날.
  final int daysSinceUse;
  final bool neverRecorded;
}

class DuplicateGroup {
  const DuplicateGroup(this.group, this.subscriptions);
  final String group;
  final List<Subscription> subscriptions;
}

/// 오래 안 쓴 구독(해지 후보 추천).
List<UnusedSuggestion> unusedSubscriptions(VaultData d, DateTime now) {
  final limit = d.prefs.unusedDays;
  final out = <UnusedSuggestion>[];
  for (final s in d.subscriptions.where((s) => !s.isPaused)) {
    final last = s.lastUsedAt;
    final days = -daysUntil(last ?? s.createdAt, now);
    if (days >= limit) out.add(UnusedSuggestion(s, days, last == null));
  }
  out.sort((a, b) => b.daysSinceUse.compareTo(a.daysSinceUse));
  return out;
}

/// 비슷한 기능의 구독을 2개 이상 쓰는 경우.
List<DuplicateGroup> duplicateSubscriptions(VaultData d) {
  final map = <String, List<Subscription>>{};
  for (final s in d.subscriptions.where((s) => !s.isPaused)) {
    final g =
        findKnownService(s.serviceName)?.group ?? _categoryGroup(s.category);
    if (g == null) continue;
    map.putIfAbsent(g, () => []).add(s);
  }
  return [
    for (final e in map.entries)
      if (e.value.length >= 2) DuplicateGroup(e.key, e.value),
  ];
}

String? _categoryGroup(String category) =>
    const {'AI': 'AI 대화', '영상': '영상 보기', '음악': '음악 듣기'}[category];

enum HealthIssue {
  reused('여러 곳에 같은 비밀번호'),
  weak('약한 비밀번호'),
  old('오래된 비밀번호(6개월 이상)'),
  missing('비밀번호 미등록');

  const HealthIssue(this.label);
  final String label;
}

class HealthReport {
  HealthReport(this.issues, this.total);

  /// 계정 id → 문제 목록
  final Map<String, List<HealthIssue>> issues;
  final int total;

  int count(HealthIssue i) => issues.values.where((l) => l.contains(i)).length;

  /// 0~100점. 문제 없는 계정 비율.
  int get score {
    if (total == 0) return 100;
    final bad = issues.values
        .where((l) => l.any((i) => i != HealthIssue.missing))
        .length;
    return ((total - bad) * 100 / total).round();
  }
}

/// 금고 건강 보고서: 재사용·약한·오래된 비밀번호.
/// 비밀번호 비교는 메모리 안에서만 하며 결과에는 비밀번호를 담지 않는다.
HealthReport vaultHealth(VaultData d, DateTime now) {
  final byPw = <String, int>{};
  for (final a in d.accounts.where((a) => a.hasPassword)) {
    byPw[a.password!] = (byPw[a.password!] ?? 0) + 1;
  }
  final issues = <String, List<HealthIssue>>{};
  for (final a in d.accounts) {
    final list = <HealthIssue>[];
    if (!a.hasPassword) {
      list.add(HealthIssue.missing);
    } else {
      if ((byPw[a.password!] ?? 0) > 1) list.add(HealthIssue.reused);
      if (PasswordTools.strength(a.password!).isWeak) {
        list.add(HealthIssue.weak);
      }
      final changed = a.passwordChangedAt ?? a.createdAt;
      if (-daysUntil(changed, now) >= 180) list.add(HealthIssue.old);
    }
    if (list.isNotEmpty) issues[a.id] = list;
  }
  return HealthReport(issues, d.accounts.length);
}

/// "이 구독의 로그인 계정" 자동 연결 후보(같은 서비스 이름).
Account? guessAccountFor(VaultData d, Subscription s) {
  final linked = d.accountById(s.accountId);
  if (linked != null) return linked;
  final aliases = aliasesFor(s.serviceName).toSet();
  for (final a in d.accounts) {
    if (aliasesFor(a.serviceName).any(aliases.contains)) return a;
  }
  return null;
}
