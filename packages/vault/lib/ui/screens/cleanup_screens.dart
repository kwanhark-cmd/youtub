import 'package:flutter/material.dart';

import '../../logic/breach.dart';
import '../../logic/cleanup.dart';
import '../../logic/money.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'accounts_screens.dart';
import 'subscriptions_screens.dart';

/// 정리 도우미: 해지 후보, 오래 안 쓴 구독, 중복 구독, 금고 건강 보고서.
class CleanupScreen extends StatelessWidget {
  const CleanupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.isUnlocked) return const SizedBox.shrink();
    final d = app.data;
    final now = app.now();
    final t = Theme.of(context).textTheme;
    final candidates = d.subscriptions
        .where((s) => s.isCancelCandidate)
        .toList();
    final unused = unusedSubscriptions(
      d,
      now,
    ).where((u) => !u.subscription.isCancelCandidate).toList();
    final dups = duplicateSubscriptions(d);
    final health = vaultHealth(d, now);
    final saving = candidates.fold<double>(
      0,
      (a, s) => a + monthlyWon(s, d.prefs.usdToKrw),
    );

    return AppPage(
      title: '정리 도우미',
      restoreId: 'cleanup',
      children: [
        FlatCard(
          status: health.score >= 80 ? StatusKind.safe : StatusKind.caution,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HealthScreen()),
          ),
          child: Row(
            children: [
              const Emoji3D('shield', size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('금고 건강 점수 ${health.score}점', style: t.titleLarge),
                    Text('비밀번호 점검 결과 보기 →', style: t.bodyLarge),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionTitle('해지 후보 ${candidates.length}개'),
        if (candidates.isEmpty)
          Text('해지 후보가 없어요.', style: t.bodyLarge)
        else ...[
          Text(
            '모두 해지하면 한 달에 ${formatWon(saving)}을 아낄 수 있어요.',
            style: t.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final s in candidates) ...[
            SubscriptionCard(sub: s, now: now),
            const SizedBox(height: 8),
          ],
        ],
        SectionTitle('오래 안 쓴 구독 ${unused.length}개'),
        Text(
          '${d.prefs.unusedDays}일 넘게 사용 기록이 없는 구독이에요. 최근에 쓰셨나요?',
          style: t.bodyLarge,
        ),
        const SizedBox(height: 8),
        for (final u in unused) ...[
          FlatCard(
            status: StatusKind.caution,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u.subscription.serviceName, style: t.titleLarge),
                Text(
                  u.neverRecorded
                      ? '등록 후 ${u.daysSinceUse}일 동안 사용 기록이 없어요'
                      : '마지막 사용 후 ${u.daysSinceUse}일 지났어요',
                  style: t.bodyLarge,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: BigButton(
                        label: '아직 써요',
                        kind: ButtonKind.safe,
                        raised: false,
                        onPressed: () =>
                            app.mutate((_) => u.subscription.lastUsedAt = now),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: BigButton(
                        label: '해지 후보로',
                        kind: ButtonKind.caution,
                        raised: false,
                        onPressed: () => app.mutate(
                          (_) => u.subscription.isCancelCandidate = true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        SectionTitle('비슷한 구독 ${dups.length}묶음'),
        if (dups.isEmpty)
          Text('비슷한 기능의 구독이 겹치지 않아요.', style: t.bodyLarge)
        else
          for (final g in dups) ...[
            FlatCard(
              status: StatusKind.caution,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '"${g.group}" 구독이 ${g.subscriptions.length}개예요',
                    style: t.titleMedium,
                  ),
                  Text(
                    g.subscriptions.map((s) => s.serviceName).join(', '),
                    style: t.bodyLarge,
                  ),
                  Text('하나만 남겨도 충분한지 생각해 보세요.', style: t.bodyMedium),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

/// 금고 건강 보고서(재사용·약한·오래된 비밀번호) + 유출 확인(켤 때만).
class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  bool checking = false;
  Map<String, int>? breached;

  Future<void> _checkBreach() async {
    final app = context.appRead;
    setState(() => checking = true);
    final checker = BreachChecker();
    final out = <String, int>{};
    var failed = false;
    for (final a in app.data.accounts.where((a) => a.hasPassword)) {
      try {
        final n = await checker.pwnedCount(a.password!);
        if (n > 0) out[a.id] = n;
      } on BreachCheckFailed {
        failed = true;
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      checking = false;
      breached = failed ? null : out;
    });
    if (failed) {
      await showErrorDialog(
        context,
        stage: FailStage.breach,
        message: '유출 확인 서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.',
        onRetry: _checkBreach,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.isUnlocked) return const SizedBox.shrink();
    final d = app.data;
    final t = Theme.of(context).textTheme;
    final r = vaultHealth(d, app.now());

    Widget section(HealthIssue issue, String help) {
      final ids = r.issues.entries
          .where((e) => e.value.contains(issue))
          .map((e) => e.key)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle('${issue.label} ${ids.length}개'),
          Text(help, style: t.bodyMedium),
          const SizedBox(height: 6),
          for (final id in ids)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FlatCard(
                status: issue == HealthIssue.missing
                    ? null
                    : StatusKind.caution,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AccountDetailScreen(id: id),
                  ),
                ),
                child: Text(
                  d.accountById(id)?.serviceName ?? '',
                  style: t.titleMedium,
                ),
              ),
            ),
        ],
      );
    }

    return AppPage(
      title: '금고 건강 보고서',
      restoreId: 'health',
      children: [
        FlatCard(
          child: Column(
            children: [
              ScoreRing(score: r.score, size: 140),
              const SizedBox(height: 12),
              Text(
                r.score >= 80 ? '아주 잘 관리하고 계세요!' : '아래 항목을 바꾸면 더 안전해져요.',
                textAlign: TextAlign.center,
                style: t.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final i in HealthIssue.values)
                    StatusBadge(
                      r.count(i) == 0
                          ? StatusKind.safe
                          : (i == HealthIssue.missing
                                ? StatusKind.progress
                                : StatusKind.caution),
                      '${i.label} ${r.count(i)}',
                      compact: true,
                    ),
                ],
              ),
            ],
          ),
        ),
        gap,
        BigButton(
          label: '튼튼한 비밀번호 만들기',
          icon: Icons.auto_fix_high_rounded,
          kind: ButtonKind.accent,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const GeneratorScreen()),
          ),
        ),
        section(HealthIssue.reused, '한 곳이 털리면 다른 곳도 위험해요. 서비스마다 다르게 바꿔 주세요.'),
        section(HealthIssue.weak, '짧거나 흔한 비밀번호예요.'),
        section(HealthIssue.old, '6개월 넘게 바꾸지 않았어요.'),
        section(HealthIssue.missing, '비밀번호가 비어 있는 계정이에요(괜찮다면 그대로 두셔도 돼요).'),
        SectionTitle('유출된 비밀번호 확인'),
        if (!d.prefs.breachCheckEnabled)
          Text(
            '설정 → 유출 확인에서 켜면 쓸 수 있어요. 비밀번호는 보내지 않고, 암호화한 값의 앞 5글자만 보내 확인해요.',
            style: t.bodyLarge,
          )
        else ...[
          Text('비밀번호 자체는 보내지 않아요(암호화한 값 앞 5글자만).', style: t.bodyMedium),
          const SizedBox(height: 8),
          checking
              ? const Center(child: CircularProgressIndicator())
              : BigButton(
                  label: '지금 확인하기',
                  icon: Icons.travel_explore_rounded,
                  onPressed: _checkBreach,
                ),
          if (breached != null) ...[
            gap,
            if (breached!.isEmpty)
              const StatusBadge(StatusKind.safe, '유출된 비밀번호가 발견되지 않았어요')
            else
              for (final e in breached!.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FlatCard(
                    status: StatusKind.danger,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AccountDetailScreen(id: e.key),
                      ),
                    ),
                    child: Text(
                      '${d.accountById(e.key)?.serviceName}: 유출 목록에 있어요. 바로 바꿔 주세요.',
                      style: t.titleMedium,
                    ),
                  ),
                ),
          ],
        ],
      ],
    );
  }
}
