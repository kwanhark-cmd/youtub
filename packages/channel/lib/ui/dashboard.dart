import 'package:flutter/material.dart';

import '../app/services.dart';
import '../core/db.dart';
import '../core/strings.dart';
import '../features/youtube/trending.dart';
import 'common.dart';
import 'connection_status.dart';
import 'edits_screen.dart';
import 'home_shell.dart';

/// 홈 화면 "오늘 할 일" 카드에 들어갈 한 가지.
class TodayTask {
  TodayTask({
    required this.status,
    required this.icon3d,
    required this.title,
    required this.action,
    required this.onTap,
  });
  final Status status;
  final String icon3d;
  final String title;
  final String action;
  final VoidCallback onTap;
}

/// 홈: 마스코트 인사 → 오늘 할 일 → 큰 타일 → 원형 게이지 → 브리핑·수정 요약.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.user, required this.shell});
  final UserContext user;
  final HomeShellState shell;

  /// 2~4단계에서 홈 카드를 더한다 (타일 아래).
  static final List<Widget Function(UserContext u, HomeShellState shell)> extraCards = [];

  /// "오늘 할 일" 후보. 앞에 있는 것이 먼저 (확인 대기가 1순위).
  static final List<TodayTask? Function(UserContext u, HomeShellState shell)> todaySources = [];

  /// 타일 옆 숫자 배지 (예: 확인 대기 개수).
  static final Map<String, int Function(UserContext u)> tileCounts = {};

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final busy = Busy();
  UserContext get u => widget.user;
  HomeShellState get shell => widget.shell;

  Future<void> _speak(String text) async {
    if (!u.settings.ttsEnabled) return;
    await u.env.speaker.setRate(u.settings.ttsRate);
    await u.env.speaker.speak(text);
  }

  TodayTask? _today() {
    for (final src in DashboardScreen.todaySources) {
      final t = src(u, shell);
      if (t != null) return t;
    }
    final broken = u.youtube.brokenAccounts();
    if (broken.isNotEmpty) {
      return TodayTask(
        status: Status.problem,
        icon3d: 'broken',
        title: S.dash2(broken.first.label),
        action: S.reconnect,
        onTap: () => shell.goTo('channels'),
      );
    }
    final exp = u.youtube.expiringAccounts();
    if (exp.isNotEmpty) {
      return TodayTask(
        status: Status.check,
        icon3d: 'bell',
        title: S.dash3(exp.first.label),
        action: S.reconnect,
        onTap: () => shell.goTo('channels'),
      );
    }
    if (u.youtube.channels().isEmpty) {
      return TodayTask(
        status: Status.check,
        icon3d: 'link',
        title: S.channelNone,
        action: S.channelAdd,
        onTap: () => shell.goTo('channels'),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final today = dayKey(u.env.now());
    final quotaLeft = u.quota.remaining;
    final quotaLimit = u.settings.quotaDailyLimit;
    final cost = u.ai.monthCostUsd;
    final limit = u.settings.monthlyCostLimitUsd;
    final edits = u.editLog.countOn(today);
    final s = u.settings;
    final todo = _today();
    final quotaRatio = quotaLimit == 0 ? 0.0 : quotaLeft / quotaLimit;
    final costLeft = limit <= 0 ? 0.0 : (1 - cost / limit).clamp(0.0, 1.0);
    Status gaugeStatus(double left) => left <= 0 ? Status.problem : (left < 0.2 ? Status.check : Status.done);
    final broken = u.youtube.brokenAccounts().isNotEmpty;
    final chans = u.youtube.channels().length;
    var i = 0;
    Widget ap(Widget w) => i < 3 ? Appear(index: i++, child: w) : w;

    final views = u.youtube.totalViews();
    final reviewN = DashboardScreen.tileCounts['review']?.call(u);
    final produceN = DashboardScreen.tileCounts['produce']?.call(u);

    // 중간 크기 (2열): 채널(파랑) · 제작(보라) — 숫자 카드
    final mainTiles = <Widget>[
      if (shell.hasTab('channels'))
        HueTile(
          key: const Key('tile-channels'),
          hue: Hue.blue,
          icon: 'chart',
          fallback: Icons.video_library,
          title: S.dashTileChannels,
          value: '$chans',
          caption: chans == 0 ? S.dashNoChannel : S.dashViews(S.num(views)),
          onTap: () => shell.goTo('channels'),
          badge: broken ? const StatusBadge(Status.problem, S.dashBroken, shake: true) : null,
        ),
      if (shell.hasTab('produce'))
        HueTile(
          key: const Key('tile-produce'),
          hue: Hue.purple,
          icon: 'create',
          fallback: Icons.movie_creation,
          title: S.dashTileProduce,
          value: produceN == null ? null : '$produceN',
          caption: produceN == null ? S.dashTileProduceSub : S.dashMaking,
          onTap: () => shell.goTo('produce'),
        ),
    ];
    // 작은 타일 (2열): 확인 대기(노랑) · 블로그(주황)
    final smallTiles = <Widget>[
      if (reviewN != null)
        HueTile(
          key: const Key('tile-review'),
          hue: Hue.yellow,
          icon: 'review',
          fallback: Icons.fact_check,
          title: S.dashTileReview,
          compact: true,
          caption: reviewN > 0 ? S.dash5(reviewN) : S.dashNothingWaiting,
          onTap: () => shell.goTo('review'),
        ),
      if (shell.hasTab('blog'))
        HueTile(
          key: const Key('tile-blog'),
          hue: Hue.orange,
          icon: 'blog',
          fallback: Icons.rss_feed,
          title: S.dashTileBlog,
          compact: true,
          caption: S.dashTileBlogShort,
          onTap: () => shell.goTo('blog'),
        ),
    ];

    // 화면에 보이는 것만 그리는 목록 (빠르게 열리도록).
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppTokens.pagePad, AppTokens.gapS, AppTokens.pagePad, AppTokens.bottomSpace),
      children: [
        ap(
          Row(
            children: [
              // 앱 꾸미기에서 고른 아이콘·이름
              AppIconView(look: u.look, size: 72),
              const SizedBox(width: AppTokens.gapM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.dash6(u.user.name), style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: AppTokens.gapXs),
                    // 연결 상태 (구글·인공지능 따로). 누르면 설정으로.
                    ConnectionBadges(user: u, onTap: () => shell.goTo('settings')),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.gapL),
        // 가장 중요한 것: 오늘 할 일 (가득 찬 폭, 가장 큼)
        ap(_todayCard(todo)),
        const SizedBox(height: AppTokens.gapL),
        // 작은 띠: 사용량·비용 (큰 숫자) + 오늘 수정·자동 작업
        SoftCard(
          key: const Key('usage-strip'),
          padding: const EdgeInsets.all(AppTokens.gapL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TwoUp(
                gap: AppTokens.gapXl,
                minWidth: 240,
                equalHeight: false,
                children: [
                  MeterCell(
                    label: S.homeQuota,
                    value: S.num(quotaLeft),
                    of: '/ ${S.num(quotaLimit)}',
                    ratio: quotaRatio,
                    status: gaugeStatus(quotaRatio),
                  ),
                  MeterCell(
                    label: S.homeCost,
                    value: S.dollars(cost),
                    of: '/ ${S.dollars(limit, 0)}',
                    ratio: costLeft,
                    status: gaugeStatus(costLeft),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.gapM),
              Wrap(
                spacing: AppTokens.gapS,
                runSpacing: AppTokens.gapS,
                children: [
                  StatusBadge(edits > 0 ? Status.done : Status.progress, '${S.homeTodayEdits} ${S.home1(edits)}'),
                  StatusBadge(
                    s.runnerEnabled ? Status.progress : Status.check,
                    s.runnerEnabled ? S.homeRunnerOn(s.runnerFromHour, s.runnerToHour) : S.homeRunnerOff,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (mainTiles.isNotEmpty) ap(TwoUp(children: mainTiles)),
        if (smallTiles.isNotEmpty) ...[const SizedBox(height: AppTokens.gapL), TwoUp(children: smallTiles)],
        if (shell.hasTab('corner')) ...[
          const SizedBox(height: AppTokens.gapL),
          HueTile(
            key: const Key('tile-corner'),
            hue: Hue.green,
            icon: 'corner',
            fallback: Icons.auto_stories,
            title: S.dashTileCorner,
            compact: true,
            caption: S.dashTileCornerSub,
            onTap: () => shell.goTo('corner'),
          ),
        ],
        const SizedBox(height: AppTokens.cardGap),
        ?_trendingCard(),
        for (final card in DashboardScreen.extraCards) ap(card(u, shell)),
        ap(
          SectionCard(
            title: S.briefingTitle,
            icon3d: 'hello',
            child: ButtonWrap(
              children: [
                BigButton(
                  key: const Key('briefing'),
                  label: S.homeBriefing,
                  icon: Icons.record_voice_over,
                  onPressed: () => busy.run(() async {
                    final b = u.briefing.compose();
                    u.briefing.markDone();
                    await _showText(S.briefingTitle, b.spoken, mascot: MascotMood.hello);
                  }),
                ),
                BigButton(
                  label: S.homeVoiceSummary,
                  icon: Icons.volume_up,
                  primary: false,
                  onPressed: () => busy.run(() async {
                    final t = u.voice.channelSummary();
                    await _showText(S.homeVoiceSummary, t);
                  }),
                ),
              ],
            ),
          ),
        ),
        ap(
          SectionCard(
            title: S.dailyReportTitle,
            icon3d: 'undo',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u.edits.dailySummary(today)),
                const SizedBox(height: AppTokens.gapM),
                ButtonWrap(
                  children: [
                    BigButton(
                      key: const Key('open-edits'),
                      label: S.homeDailyReport,
                      icon: Icons.list,
                      primary: false,
                      onPressed: () async {
                        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EditsScreen(user: u)));
                        if (mounted) setState(() {});
                      },
                    ),
                    BigButton(
                      key: const Key('run-edits'),
                      label: S.homeRunEdits,
                      icon: Icons.auto_fix_high,
                      onPressed: () async {
                        await runEditsFlow(context, u);
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 주목할 영상: 평소보다 조회수가 빨리 늘고 있는 내 영상 (없으면 카드도 없음).
  Widget? _trendingCard() {
    final list = TrendingService(u.db, u.youtube).find();
    if (list.isEmpty) return null;
    return SectionCard(
      key: const Key('trending-card'),
      title: S.trendTitle,
      icon3d: 'fire',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.trendHelp, style: TextStyle(color: context.tokens.textSoft)),
          for (final v in list)
            ListCard(
              icon: 'chart',
              title: v.title,
              subtitle: u.youtube.channel(v.channelId)?.title ?? '',
              status: Status.done,
              badge: StatusBadge(Status.done, S.trendBadge(v.ratio.round(), v.perDay), shake: true),
              onTap: () => u.env.launchUrl(Uri.parse('https://www.youtube.com/watch?v=${v.videoId}')),
            ),
        ],
      ),
    );
  }

  /// 오늘 할 일: 홈에서 가장 크고 눈에 띄는 카드 (상태 색으로 채움, 테두리 없음).
  Widget _todayCard(TodayTask? todo) {
    final t = context.tokens;
    final st = todo?.status ?? Status.done;
    final hue = AppTokens.hueOfStatus(st);
    final fg = t.onTile(hue);
    return SoftCard(
      key: const Key('today-card'),
      color: t.tileBg(hue),
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(AppTokens.gapXl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.dashTodayTitle,
                        style: TextStyle(fontSize: AppTokens.fontTitle, fontWeight: FontWeight.w900, color: fg),
                      ),
                      const SizedBox(height: AppTokens.gapS),
                      // 색 카드 위에서는 뒤집은 배지 (같은 색끼리 묻히지 않게)
                      StatusBadge(
                        st,
                        todo == null ? S.dashAllDone : S.dashTodo,
                        shake: todo != null,
                        colors: (fg, t.tileBg(hue)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTokens.gapM),
                Icon3D(todo?.icon3d ?? 'party', size: 96),
              ],
            ),
            const SizedBox(height: AppTokens.gapL),
            Text(
              todo?.title ?? S.dashAllDoneSub,
              style: TextStyle(fontSize: AppTokens.fontBody + 3, fontWeight: FontWeight.w600, color: fg, height: 1.4),
            ),
            if (todo != null) ...[
              const SizedBox(height: AppTokens.gapL),
              SizedBox(
                width: double.infinity,
                child: BigButton(
                  key: const Key('today-action'),
                  label: todo.action,
                  icon: Icons.arrow_forward,
                  onPressed: todo.onTap,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showText(String title, String text, {MascotMood? mascot}) async {
    final speak = _speak(text);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: mascot == null ? null : Mascot(mascot, size: 96),
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(
            text,
            key: const Key('spoken-text'),
            style: const TextStyle(fontSize: AppTokens.fontBody + 1),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              u.env.speaker.stop();
              Navigator.pop(c);
            },
            child: const Text(S.close),
          ),
        ],
      ),
    );
    await speak;
  }
}
