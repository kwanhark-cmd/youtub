import 'package:flutter/material.dart';

import '../../logic/alerts.dart';
import '../../logic/cleanup.dart';
import '../../logic/money.dart';
import '../../logic/dates.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'accounts_screens.dart';
import 'cleanup_screens.dart';
import 'credits_screens.dart';
import 'restore_routes.dart';
import 'settings_screens.dart';
import 'subscriptions_screens.dart';
import 'voice_screen.dart';

StatusKind statusOf(AlertItem a) =>
    a.level == AlertLevel.danger ? StatusKind.danger : StatusKind.caution;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // 알림이 절전 때문에 안 왔을 수 있으니 앱을 열면 밀린 알림을 먼저 보여 준다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showMissed());
  }

  Future<void> _showMissed() async {
    final app = context.appRead;
    if (!app.isUnlocked) return;
    // 잠기기 전에 보던 화면으로 돌아간다(같은 사용자일 때만).
    final resume = app.takeResume();
    if (resume.isNotEmpty) restoreScreens(Navigator.of(context), resume);
    final missed = app.takeUnseenAlerts();
    if (missed.isEmpty || !mounted) return;
    // 알림은 화면 + 음성으로(소리 설정이 켜져 있을 때). 금고가 열린 뒤에만 읽는다.
    if (app.settings.sound) {
      app.services.tts.speak(
        '확인할 알림이 ${missed.length}건 있어요. ${missed.take(3).map((a) => '${a.title}, ${a.detail}').join('. ')}',
      );
    }
    await showSafeDialog<void>(
      context,
      (c) => AlertDialog(
        title: Row(
          children: [
            const Emoji3D('bell', size: 40),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '확인할 알림 ${missed.length}건',
                style: Theme.of(c).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final a in missed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FlatCard(
                      status: statusOf(a),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StatusBadge(
                            statusOf(a),
                            a.level == AlertLevel.danger ? '위험' : '확인 필요',
                            compact: true,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            a.title,
                            style: Theme.of(c).textTheme.titleMedium,
                          ),
                          Text(
                            a.detail,
                            style: Theme.of(c).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          BigButton(
            label: '확인했어요',
            expand: false,
            raised: false,
            onPressed: () => Navigator.pop(c),
          ),
        ],
      ),
    );
  }

  void _go(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  ScrollController? _scroll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.appRead;
    // 홈도 보던 위치 유지(갱신·잠금 후에도)
    _scroll ??=
        ScrollController(
          initialScrollOffset: app.scrollOffsets['home'] ?? 0,
        )..addListener(() {
          if (_scroll!.hasClients) app.scrollOffsets['home'] = _scroll!.offset;
        });
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.isUnlocked) return const SizedBox.shrink();
    final d = app.data;
    final now = app.now();
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final sum = summarize(d);
    final task = todayTask(d, now);
    final alerts = computeAlerts(d, now);
    final creditAlerts = alerts.where((a) => a.isCredit).length;
    final health = vaultHealth(d, now);
    final cleanupCount =
        unusedSubscriptions(d, now).length +
        d.subscriptions.where((s) => s.isCancelCandidate).length;
    final name = app.currentProfile?.name ?? '';
    // 이번 주(오늘~7일) 결제 예정
    final week = <(DateTime, String, String)>[];
    for (final s in d.subscriptions.where((s) => !s.isPaused)) {
      final next = upcomingRenewal(s, now);
      if (daysUntil(next, now) <= 7) {
        week.add((next, s.serviceName, formatAmount(s.amount, s.currency)));
      }
    }
    week.sort((a, b) => a.$1.compareTo(b.$1));

    return Scaffold(
      bottomNavigationBar: const ClipboardBanner(),
      body: SafeArea(
        child: ListView(
          key: const PageStorageKey('home'),
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // 머리: 작은 인사 + 잠그기
            Row(
              children: [
                const LockAnimation(open: true, size: 40),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('$name님, 안녕하세요', style: t.titleLarge),
                  ),
                ),
                const SizedBox(width: 8),
                BigButton(
                  label: '잠그기',
                  icon: Icons.lock_rounded,
                  kind: ButtonKind.plain,
                  expand: false,
                  raised: false,
                  onPressed: () => app.lock(),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s3),
            const TipBubble(
              id: 'home',
              text: '맨 위 큰 숫자가 이번 달 구독료예요. 2분 동안 아무것도 안 하면 금고가 자동으로 잠겨요.',
            ),
            // 1. 주인공: 이번 달 구독료
            HeroNumberCard(
              label: '이번 달 구독료',
              value: formatWon(sum.monthly),
              caption: '구독 ${sum.activeCount}개 · 1년이면 ${formatWon(sum.yearly)}',
              onTap: () => _go(const SubscriptionsScreen()),
            ),
            const SizedBox(height: AppTokens.cardGap),
            // 2. 오늘 할 일(만료 임박 1건) — 노랑·빨강으로 채운 카드
            _TodayCard(
              task: task,
              onTap: task == null
                  ? null
                  : () => _go(
                      task.isCredit
                          ? const CreditsScreen()
                          : const SubscriptionsScreen(),
                    ),
            ),
            const SizedBox(height: AppTokens.cardGap),
            // 3. 이번 주 결제 타임라인
            FlatCard(
              onTap: () => _go(const SubscriptionsScreen()),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('이번 주 결제 예정', style: t.titleMedium),
                  const SizedBox(height: 8),
                  if (week.isEmpty)
                    Text('이번 주에는 결제가 없어요.', style: t.bodyLarge)
                  else
                    for (final (day, svc, amount) in week.take(4))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            ServiceAvatar(svc, size: 36),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    svc,
                                    style: t.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${formatKoreanDate(day)} · ${relativeDays(daysUntil(day, now))} · $amount',
                                    style: t.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.cardGap),
            // 4. 타일 2열
            LayoutBuilder(
              builder: (context, c) {
                final scale = MediaQuery.textScalerOf(context).scale(1);
                final cols = c.maxWidth / (170 * scale) >= 2 ? 2 : 1;
                final tiles = <Widget>[
                  Tile3D(
                    emoji: 'credit_card',
                    title: '구독 결제',
                    subtitle: '요금·결제일·카드',
                    onTap: () => _go(const SubscriptionsScreen()),
                  ),
                  Tile3D(
                    emoji: 'key',
                    title: '계정·비밀번호',
                    subtitle: '아이디·이메일·복사',
                    onTap: () => _go(const AccountsScreen()),
                  ),
                  Tile3D(
                    emoji: 'shield',
                    title: '금고 건강',
                    subtitle: '점수 ${health.score}점',
                    badge: health.issues.isEmpty
                        ? null
                        : '${health.issues.length}건',
                    badgeKind: ScoreRing.kindFor(health.score),
                    onTap: () => _go(const HealthScreen()),
                  ),
                  Tile3D(
                    emoji: 'alarm_clock',
                    title: '만료 알림',
                    subtitle: '크레딧·체험판',
                    badge: creditAlerts > 0 ? '$creditAlerts건' : null,
                    badgeKind:
                        alerts.any(
                          (a) => a.isCredit && a.level == AlertLevel.danger,
                        )
                        ? StatusKind.danger
                        : StatusKind.caution,
                    onTap: () => _go(const CreditsScreen()),
                  ),
                ];
                final rows = <Widget>[];
                for (var i = 0; i < tiles.length; i += cols) {
                  final slice = tiles.sublist(
                    i,
                    (i + cols).clamp(0, tiles.length),
                  );
                  rows.add(
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var j = 0; j < slice.length; j++) ...[
                            if (j > 0) const SizedBox(width: 14),
                            Expanded(child: slice[j]),
                          ],
                        ],
                      ),
                    ),
                  );
                  rows.add(const SizedBox(height: 14));
                }
                return Column(children: rows);
              },
            ),
            // 5. 그 밖의 메뉴(한 카드 안의 목록)
            FlatCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _MenuRow(
                    emoji: 'microphone',
                    title: '말로 묻기 · 아침 브리핑',
                    onTap: () => _go(const VoiceScreen()),
                  ),
                  Divider(height: 1, color: p.border),
                  _MenuRow(
                    emoji: 'broom',
                    title: '정리 도우미',
                    badge: cleanupCount > 0 ? '$cleanupCount건' : null,
                    onTap: () => _go(const CleanupScreen()),
                  ),
                  Divider(height: 1, color: p.border),
                  _MenuRow(
                    emoji: 'gear',
                    title: '설정 · 백업 · 업데이트',
                    onTap: () => _go(const SettingsScreen()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.cardGap),
            // 6. 금고 상태 띠(가장 작게)
            Text('연결 상태', style: t.bodyMedium?.copyWith(color: p.textMuted)),
            const SizedBox(height: 6),
            const ConnectionStatusRow(),
          ],
        ),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.task, this.onTap});
  final AlertItem? task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final kind = task == null ? StatusKind.safe : statusOf(task!);
    final fg = context.palette.onStatusFill(kind);
    return StatusFillCard(
      kind: kind,
      onTap: onTap,
      child: Row(
        children: [
          Emoji3D(
            task == null
                ? 'check_mark_button'
                : (task!.isCredit ? 'hourglass_not_done' : 'calendar'),
            size: 52,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '오늘 할 일',
                  style: t.bodyLarge?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  task?.title ?? '오늘은 할 일이 없어요',
                  style: t.titleLarge?.copyWith(color: fg),
                ),
                if (task != null)
                  Text(task!.detail, style: t.bodyLarge?.copyWith(color: fg)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.emoji,
    required this.title,
    required this.onTap,
    this.badge,
  });
  final String emoji;
  final String title;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: () {
        context.tapFeedback();
        onTap();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTokens.buttonHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Emoji3D(emoji, size: 36),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: t.titleMedium)),
              if (badge != null) ...[
                StatusBadge(StatusKind.caution, badge!, compact: true),
                const SizedBox(width: 6),
              ],
              const Icon(Icons.chevron_right_rounded, size: 30),
            ],
          ),
        ),
      ),
    );
  }
}
