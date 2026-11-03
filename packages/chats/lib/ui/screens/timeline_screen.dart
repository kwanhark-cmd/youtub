import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/dialogs.dart';
import '../widgets/page.dart';
import 'conversation_screen.dart';
import 'import_screen.dart';

/// 날짜순 타임라인: 연·월 이동, 주제·AI 거르기.
class TimelineScreen extends StatefulWidget {
  final bool asTab;
  const TimelineScreen({super.key, this.asTab = false});
  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  int? year;
  int? month;
  int? topicId;
  AiSource? source;
  int shown = 40;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final s = c.session!;
    final p = AppTheme.of(context).palette;
    final tt = Theme.of(context).textTheme;
    final months = s.store.months(topicId: topicId, source: source);
    if (months.isEmpty) {
      return AppPage(
        title: '날짜별 보기',
        isHome: widget.asTab,
        body: Column(
          children: [
            _filters(context, s.topics.all()),
            EmptyState(
              title: '보여줄 대화가 없어요',
              message: topicId != null || source != null ? '거르기를 풀어 보세요.' : '이렇게 시작하세요: 대화 기록을 넣으면 날짜순으로 보여드려요.',
              actionLabel: topicId != null || source != null ? null : '대화 넣기',
              onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportScreen())),
            ),
          ],
        ),
      );
    }
    var idx = months.indexWhere((m) => m.$1 == year && m.$2 == month);
    if (idx < 0) idx = 0;
    final (y, m, n) = months[idx];
    final from = DateTime(y, m);
    final to = DateTime(y, m + 1);
    final list = s.store.list(from: from, to: to, topicId: topicId, source: source, limit: shown);
    final years = months.map((e) => e.$1).toSet().toList();

    void select(int i) => setState(() {
      year = months[i].$1;
      month = months[i].$2;
      shown = 40;
    });

    final byDay = <String, List<ConversationSummary>>{};
    for (final conv in list) {
      byDay.putIfAbsent(dateText.format(conv.createdAt), () => []).add(conv);
    }

    return AppPage(
      title: '날짜별 보기',
      isHome: widget.asTab,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _filters(context, s.topics.all()),
          const SizedBox(height: AppSize.gapM),
          // 연도 이동
          Wrap(
            spacing: AppSize.gapS,
            runSpacing: AppSize.gapS,
            children: [
              for (final yy in years)
                ChoiceChip(label: Text('$yy년'), selected: yy == y, onSelected: (_) => select(months.indexWhere((e) => e.$1 == yy))),
            ],
          ),
          const SizedBox(height: AppSize.gapM),
          // 월 이동
          Row(
            children: [
              Expanded(
                child: BigButton(
                  label: '이전 달',
                  icon: Icons.chevron_left_rounded,
                  kind: ButtonKind.primary,
                  onPressed: idx < months.length - 1 ? () => select(idx + 1) : null,
                ),
              ),
              const SizedBox(width: AppSize.gapS),
              Expanded(
                child: BigButton(
                  label: '다음 달',
                  icon: Icons.chevron_right_rounded,
                  kind: ButtonKind.primary,
                  onPressed: idx > 0 ? () => select(idx - 1) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSize.gapM),
          Container(
            padding: const EdgeInsets.all(AppSize.gapM),
            decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(AppSize.radius)),
            child: Row(
              children: [
                Image.asset(AppIcons3d.calendar, width: 40, height: 40, excludeFromSemantics: true),
                const SizedBox(width: AppSize.gapM),
                Expanded(child: Text('$y년 $m월 · 대화 $n개', style: tt.titleLarge)),
              ],
            ),
          ),
          const SizedBox(height: AppSize.gapM),
          for (final e in byDay.entries) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: p.primary, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e.key, style: tt.titleMedium)),
                ],
              ),
            ),
            for (final conv in e.value) ...[
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: ConversationTile(
                  c: conv,
                  onOpen: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConversationScreen(id: conv.id))),
                ),
              ),
              const SizedBox(height: AppSize.gapS),
            ],
          ],
          if (list.length < n) BigButton(label: '더 보기', icon: Icons.expand_more_rounded, onPressed: () => setState(() => shown += 40)),
        ],
      ),
    );
  }

  Widget _filters(BuildContext context, List<Topic> topics) {
    return Wrap(
      spacing: AppSize.gapS,
      runSpacing: AppSize.gapS,
      children: [
        BigButton(
          label: topicId == null ? '모든 주제' : '주제: ${topics.where((t) => t.id == topicId).firstOrNull?.name ?? ''}',
          icon: Icons.filter_alt_rounded,
          expand: false,
          kind: ButtonKind.quiet,
          onPressed: () async {
            final picked = await pickOne<int>(
              context,
              title: '어느 주제만 볼까요?',
              options: [(-1, '모든 주제'), for (final t in topics) (t.id, t.name)],
            );
            if (picked != null) setState(() => topicId = picked == -1 ? null : picked);
          },
        ),
        ChoiceChip(label: const Text('모든 AI'), selected: source == null, onSelected: (_) => setState(() => source = null)),
        for (final a in AiSource.values)
          ChoiceChip(label: Text(a.label), selected: source == a, onSelected: (_) => setState(() => source = source == a ? null : a)),
      ],
    );
  }
}
