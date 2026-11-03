import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app/app.dart';
import 'core/strings.dart';
import 'features/ai/brain.dart';
import 'features/blog/blog_service.dart';
import 'features/corner/corner_service.dart';
import 'features/blog/blogger_api.dart';
import 'features/production/production_service.dart';
import 'features/tools/tools_service.dart';
import 'ui/blog_screen.dart';
import 'ui/channels_screen.dart';
import 'ui/common.dart';
import 'ui/corner_screen.dart';
import 'ui/dashboard.dart';
import 'ui/produce_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/tabs_registry.dart';
import 'ui/tools_screen.dart';

/// 2~4단계 기능을 앱에 붙이는 곳. 단계가 추가될 때마다 여기에 늘어난다.
bool _registered = false;

void registerStages() {
  if (_registered) return;
  _registered = true;
  _stage2();
  _stage3();
  _stage4();
}

// ---------------- 2단계: 콘텐츠 제작과 업로드 ----------------
void _stage2() {
  AppState.plugins.add((u) async {
    final tools = ToolsService(
      db: u.db,
      secrets: u.secrets,
      json: u.env.jsonHttp,
      raw: u.env.httpClient,
      oauth: u.oauth,
      now: u.env.now,
      logger: u.env.logger,
    );
    final ps = ProductionService(
      db: u.db,
      youtube: u.youtube,
      brain: u.brain,
      settings: u.settings,
      memos: u.memos,
      tools: tools,
      quota: u.quota,
      now: u.env.now,
      mediaDir: p.join(u.env.accounts.userDir(u.user.id), 'media'),
      logger: u.env.logger,
    );
    u.extensions['tools'] = tools;
    u.extensions['production'] = ps;
    u.voice.privateList = () =>
        ps.list(statuses: [ProductionStatus.uploadedPrivate], limit: 500).map((e) => e.title).toList();
    u.voice.makeContent = (channelTitle, format, topic) async {
      final ch = u.youtube.channels().firstWhere(
        (c) => c.title == channelTitle,
        orElse: () => u.youtube.channels().first,
      );
      try {
        final pr = await ps.create(channelId: ch.channelId, format: format, topic: topic);
        return S.stage1(ch.title, formatLabel(format), pr.title);
      } on ProductionBlocked catch (e) {
        return e.message;
      }
    };
    u.briefing.todaySources.add(ps.briefingItems);
    var toolNotices = <String>[];
    u.briefing.expiringSources.add(() => toolNotices);
    toolNotices = await tools.expiringNotices();
  });

  TabsRegistry.addTab(
    (u, shell) => AppTab(
      S.navProduce,
      Icons.movie_creation,
      (k) => ProduceScreen(key: k, user: u),
      id: 'produce',
    ),
  );
  TabsRegistry.addRoute('review', (context, u) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReviewScreen(user: u)));
  });

  ChannelsScreen.waitingCount = (u, ch) => productionOf(u).reviewList().where((p) => p.channelId == ch).length;
  DashboardScreen.tileCounts['review'] = (u) => productionOf(u).reviewList().length;
  DashboardScreen.tileCounts['produce'] = (u) =>
      productionOf(u).list(statuses: [ProductionStatus.draft, ProductionStatus.uploadTomorrow], limit: 500).length;
  DashboardScreen.todaySources.add((u, shell) {
    final n = productionOf(u).reviewList().length;
    if (n == 0) return null;
    return TodayTask(
      status: Status.check,
      icon3d: 'review',
      title: S.dash7(n),
      action: S.dashReviewNow,
      onTap: () => shell.goTo('review'),
    );
  });

  SettingsScreen.extraSections.add((context, u, refresh) {
    final s = u.settings;
    return SectionCard(
      title: S.stage2,
      icon3d: 'tools',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NumberField(
            label: S.settingsProduceLimit,
            value: s.produceDailyLimit,
            onChanged: (v) => s.produceDailyLimit = v.toInt(),
          ),
          const SizedBox(height: AppTokens.gapM),
          DropdownButtonFormField<String>(
            initialValue: s.aiLabelMethod,
            isExpanded: true,
            decoration: const InputDecoration(labelText: S.settingsAiLabel),
            items: const [
              DropdownMenuItem(value: 'description', child: Text(S.produceAiLabelDesc)),
              DropdownMenuItem(value: 'channel', child: Text(S.produceAiLabelChannel)),
              DropdownMenuItem(value: 'setting', child: Text(S.produceAiLabelSetting)),
            ],
            onChanged: (v) {
              s.aiLabelMethod = v ?? 'setting';
              refresh();
            },
          ),
          const SizedBox(height: AppTokens.gapM),
          BigButton(
            key: const Key('open-tools'),
            label: S.settingsTools,
            icon: Icons.build,
            primary: false,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ToolsScreen(user: u))),
          ),
        ],
      ),
    );
  });
}

// ---------------- 3단계: 구글 블로그·티스토리 ----------------
/// 테스트에서 가짜 블로그를 바꿔 끼울 때.
MockBloggerApi Function() mockBloggerFactory = MockBloggerApi.new;

void _stage3() {
  AppState.plugins.add((u) async {
    final bs = BlogService(
      db: u.db,
      youtube: u.youtube,
      realApi: RealBloggerApi(u.env.jsonHttp),
      mockApi: mockBloggerFactory(),
      tokens: u.tokens,
      oauth: u.oauth,
      brain: u.brain,
      editLog: u.editLog,
      settings: u.settings,
      now: u.env.now,
      logger: u.env.logger,
    );
    u.extensions['blog'] = bs;
    u.runner.dailyTasks.add(bs.dailyTask);
    u.briefing.todaySources.add(bs.briefingItems);
  });
  TabsRegistry.addTab(
    (u, shell) => AppTab(
      S.navBlog,
      Icons.rss_feed,
      (k) => BlogScreen(key: k, user: u),
      id: 'blog',
    ),
  );
}

// ---------------- 4단계: 사용자 코너 ----------------
void _stage4() {
  AppState.plugins.add((u) async {
    u.extensions['corner'] = CornerService(
      db: u.db,
      production: productionOf(u),
      memos: u.memos,
      now: u.env.now,
      mediaDir: p.join(u.env.accounts.userDir(u.user.id), 'media'),
      logger: u.env.logger,
    );
  });
  TabsRegistry.addTab(
    (u, shell) => AppTab(
      S.navCorner,
      Icons.auto_stories,
      (k) => CornerScreen(key: k, user: u),
      id: 'corner',
    ),
  );
}

/// 테스트 등에서 형식 이름이 필요할 때.
String formatName(ContentFormat f) => formatLabel(f);
