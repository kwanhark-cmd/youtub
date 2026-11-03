import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../shell.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/page.dart';
import '../widgets/pressable.dart';
import '../widgets/status_strip.dart';
import '../widgets/voice_input.dart';
import 'conversation_screen.dart';
import 'decisions_screen.dart';
import 'export_guide_screen.dart';
import 'import_screen.dart';
import 'topics_screen.dart';

void go(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

/// 홈: 크기로 중요도 표시 — 검색창 > 오늘 할 일 > 주제 타일(2열) > 최근 대화 > 통계 띠.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final s = c.session!;
    final tt = Theme.of(context).textTheme;
    final total = s.store.count();
    final due = s.settings.exportDue(DateTime.now());
    final topics = s.topics.all().where((t) => t.count > 0).toList()..sort((a, b) => b.count.compareTo(a.count));
    final recent = s.store.list(limit: 5);
    final starred = s.store.count(starred: true);
    const gap = SizedBox(height: AppSize.cardGap);

    return AppPage(
      title: c.appName,
      isHome: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 인사(작게)
          Row(
            children: [
              const AppIconAvatar(size: 52),
              const SizedBox(width: AppSize.gapM),
              Expanded(child: Text('${s.user.name}님, 안녕하세요!', style: tt.titleMedium)),
              if (c.hasUpdateBadge)
                InkWell(
                  onTap: () => ShellNav.goTab(ShellNav.settings),
                  borderRadius: BorderRadius.circular(AppSize.radiusSmall),
                  child: Wiggle(
                    child: StatusBadge(kind: StatusKind.check, text: '새 버전 있어요'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSize.gapM),
          // 1. 주인공: 화면 폭 전체의 큰 검색창 + 마이크
          VoiceTextField(large: true, hint: '무엇을 찾을까요? 예: 지난달 유튜브 앱', onSubmit: ShellNav.openSearch),
          gap,
          // 2. 오늘 할 일
          _TodayCard(total: total, due: due),
          gap,
          // 연결 상태(대화 수 / AI / 지메일)
          const StatusStrip(),
          gap,
          // 3. 주제 타일(2열, 주제마다 색)
          _SectionHeader(title: '주제', action: '모두 보기', onAction: () => ShellNav.goTab(ShellNav.topics)),
          const SizedBox(height: AppSize.gapS),
          if (topics.isEmpty)
            Text(total == 0 ? '대화를 넣으면 주제별로 나눠 드려요.' : '아직 주제로 나누지 않았어요. 주제 탭에서 "다시 정리하기"를 눌러 보세요.', style: tt.bodyLarge)
          else
            _TopicGrid(topics: topics.take(6).toList()),
          gap,
          // 4. 최근 대화
          _SectionHeader(title: '최근 대화', action: '모두 보기', onAction: () => ShellNav.openSearch('')),
          const SizedBox(height: AppSize.gapS),
          if (recent.isEmpty)
            Text('아직 대화가 없어요.', style: tt.bodyLarge)
          else
            for (final (i, conv) in recent.indexed) ...[
              AppearUp(
                index: i,
                child: ConversationTile(
                  c: conv,
                  onOpen: () => go(context, ConversationScreen(id: conv.id)),
                ),
              ),
              const SizedBox(height: AppSize.gapM),
            ],
          gap,
          // 5. 통계 띠(큰 숫자 + 작은 설명)
          _StatsStrip(total: total, topics: topics.length, starred: starred),
          const SizedBox(height: AppSize.gapM),
          BigButton(
            label: '정한 내용 모아 보기',
            image: AppIcons3d.memo,
            kind: ButtonKind.quiet,
            onPressed: () => go(context, const DecisionsScreen()),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String action;
  final VoidCallback onAction;
  const _SectionHeader({required this.title, required this.action, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context).palette;
    return Row(
      children: [
        Expanded(
          child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: p.primaryText,
            backgroundColor: Color.lerp(p.background, p.primary, 0.10),
            minimumSize: const Size(AppSize.minTouch, AppSize.minTouch),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSize.radiusSmall)),
          ),
          onPressed: onAction,
          child: Text(action, style: Theme.of(context).textTheme.labelMedium!.copyWith(color: p.primaryText)),
        ),
      ],
    );
  }
}

/// 주제 타일 2열. 타일마다 주제 색.
class _TopicGrid extends StatelessWidget {
  final List<Topic> topics;
  const _TopicGrid({required this.topics});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < topics.length; i += 2) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSize.gapM),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: AppearUp(index: i, child: _TopicTile(topics[i])),
                ),
                const SizedBox(width: AppSize.gapM),
                Expanded(
                  child: i + 1 < topics.length ? AppearUp(index: i + 1, child: _TopicTile(topics[i + 1])) : const SizedBox(),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _TopicTile extends StatelessWidget {
  final Topic t;
  const _TopicTile(this.t);

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context).palette;
    final tt = Theme.of(context).textTheme;
    final color = TopicColors.of(t.id);
    return Pressable(
      onTap: () => go(context, TopicDetailScreen(topicId: t.id)),
      color: Color.lerp(p.surface, color, p.brightness == Brightness.dark ? 0.22 : 0.14)!,
      borderRadius: BorderRadius.circular(AppSize.radiusCard),
      border: p.borderWidth > 1 ? BorderSide(color: p.border, width: p.borderWidth) : null,
      semanticLabel: '${t.name} 주제, 대화 ${t.count}개',
      child: Padding(
        padding: const EdgeInsets.all(AppSize.gapL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.folder_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(height: AppSize.gapS),
            Text(
              t.name,
              style: tt.titleMedium!.copyWith(fontWeight: FontWeight.w800),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text('대화 ${t.count}개', style: tt.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// "오늘 할 일" 카드: 지금 눌러야 할 것 하나만 크게.
class _TodayCard extends StatelessWidget {
  final int total;
  final List<AiSource> due;
  const _TodayCard({required this.total, required this.due});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final p = AppTheme.of(context).palette;
    final tt = Theme.of(context).textTheme;
    final mails = c.settings.gmailFoundCount;
    final (String text, String button, String image, VoidCallback onTap, bool wiggle) = switch ((total, mails > 0, due.isNotEmpty)) {
      (0, _, _) => (
        '먼저 AI 대화 기록 파일을 넣어 주세요. 샘플로 체험할 수도 있어요.',
        '대화 기록 넣기',
        AppIcons3d.inbox,
        () => go(context, const ImportScreen()),
        false,
      ),
      (_, true, _) => (
        '내보내기 안내 메일이 $mails통 왔어요. 링크가 만료되기 전에 내려받을 때가 됐어요.',
        '내려받고 넣기',
        AppIcons3d.envelope,
        () => go(context, const ImportScreen()),
        true,
      ),
      (_, _, true) => (
        '${due.map((d) => d.label).join(', ')} 대화 기록 내보내기를 요청할 때가 됐어요.',
        '내보내기 요청하러 가기',
        AppIcons3d.bell,
        () => go(context, const ExportGuideScreen()),
        true,
      ),
      _ => ('새 대화 기록을 받았다면 넣어 주세요. 주제별 정리는 자동으로 돼요.', '대화 넣기', AppIcons3d.inbox, () => go(context, const ImportScreen()), false),
    };
    final card = Container(
      padding: const EdgeInsets.all(AppSize.gapL),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [p.primary, Color.lerp(p.primary, Colors.black, 0.25)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSize.radiusCard),
        boxShadow: AppShadows.raised(p),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Image.asset(image, width: 48, height: 48, excludeFromSemantics: true),
              const SizedBox(width: AppSize.gapM),
              Expanded(
                child: Text('오늘 할 일', style: tt.titleLarge!.copyWith(color: p.onPrimary)),
              ),
            ],
          ),
          const SizedBox(height: AppSize.gapS),
          Text(text, style: tt.bodyLarge!.copyWith(color: p.onPrimary)),
          const SizedBox(height: AppSize.gapM),
          BigButton(label: button, onPressed: onTap, kind: ButtonKind.accent, icon: Icons.arrow_forward_rounded),
        ],
      ),
    );
    return Semantics(container: true, child: wiggle ? Wiggle(child: card) : card);
  }
}

/// 큰 숫자 + 작은 설명(하나의 띠 안에).
class _StatsStrip extends StatelessWidget {
  final int total;
  final int topics;
  final int starred;
  const _StatsStrip({required this.total, required this.topics, required this.starred});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context).palette;
    final tt = Theme.of(context).textTheme;
    Widget stat(String n, String label) => Expanded(
      child: Semantics(
        label: '$label $n',
        excludeSemantics: true,
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(n, style: tt.displaySmall!.copyWith(color: p.primaryText)),
            ),
            Text(label, style: tt.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSize.gapL, horizontal: AppSize.gapS),
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(AppSize.radiusCard)),
      child: Row(children: [stat('$total', '대화'), stat('$topics', '주제'), stat('$starred', '별표')]),
    );
  }
}
