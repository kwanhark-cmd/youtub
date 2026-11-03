import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../classify/ai_provider.dart';
import '../../search/query_parser.dart';
import '../../services/app_controller.dart';
import '../../services/settings.dart';
import '../../summary/summarizer.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/dialogs.dart';
import '../widgets/page.dart';
import '../widgets/voice_input.dart';
import 'conversation_screen.dart';
import 'topics_screen.dart';

SearchQuery parseQuery(String text, AppSettings s) => QueryParser.parse(text, exact: s.exactMatch, similar: s.similarWords);

/// 주제를 골라 "지금까지 정한 내용"을 봅니다.
class DecisionsScreen extends StatelessWidget {
  const DecisionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final s = c.session!;
    final topics = s.topics.all()..sort((a, b) => b.count.compareTo(a.count));
    return AppPage(
      title: '정한 내용',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TipBubble(id: 'decisions', text: '여러 AI와 나눈 대화에서 "하기로 했다", "정했다" 같은 내용을 주제별로 모아 보여드려요.'),
          if (topics.isEmpty)
            EmptyState(
              title: '아직 주제가 없어요',
              message: '대화를 넣고 정리하면 주제별로 정한 내용을 모아 드려요.',
              actionLabel: '주제별 보기',
              onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TopicsScreen())),
            )
          else
            for (final (i, t) in topics.indexed) ...[
              AppearUp(
                index: i,
                child: HomeTile(
                  image: AppIcons3d.memo,
                  title: t.name,
                  subtitle: '대화 ${t.count}개',
                  color: AppTheme.of(context).palette.warning,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TopicDigestScreen(topicId: t.id))),
                ),
              ),
              const SizedBox(height: AppSize.gapM),
            ],
        ],
      ),
    );
  }
}

class TopicDigestScreen extends StatefulWidget {
  final int topicId;
  const TopicDigestScreen({super.key, required this.topicId});
  @override
  State<TopicDigestScreen> createState() => _TopicDigestScreenState();
}

class _TopicDigestScreenState extends State<TopicDigestScreen> {
  List<Decision>? decisions;
  bool aiBusy = false;

  @override
  void initState() {
    super.initState();
    context.read<AppController>().session!.classifier.decisionsForTopic(widget.topicId).then((d) {
      if (mounted) setState(() => decisions = d.reversed.toList());
    });
  }

  Future<void> _ai() async {
    final c = context.read<AppController>();
    final s = c.session!;
    final p = await c.provider();
    if (!mounted) return;
    if (!c.aiReady || p == null) {
      await showInfo(context, title: 'AI 연결이 필요해요', message: '설정 > AI 연결에서 키를 넣고 동의하면 AI가 깔끔하게 정리해 드려요.', mood: MascotMood.warning);
      return;
    }
    final ok = await confirmOnce(
      context,
      title: 'AI로 정리할까요?',
      message: '이 주제의 대화 제목·요약과 "정한 내용" 문장을 AI로 보내요. 비용은 보통 몇 원 정도예요.',
      confirmLabel: '보내고 정리하기',
    );
    if (!ok) return;
    setState(() => aiBusy = true);
    try {
      await s.classifier.aiDigest(widget.topicId, provider: p, model: s.settings.aiModel, monthlyCapUsd: s.settings.monthlyCapUsd);
      c.touch();
    } on AiError catch (e) {
      if (mounted) showNotice(context, e.message, kind: StatusKind.problem);
    }
    if (mounted) setState(() => aiBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final s = c.session!;
    final topic = s.topics.byId(widget.topicId);
    final tt = Theme.of(context).textTheme;
    final p = AppTheme.of(context).palette;
    final digest = s.topics.digest(widget.topicId);
    final ds = decisions;
    final readText = digest?.$1 ?? ds?.map((d) => d.text).join('. ') ?? '';
    return AppPage(
      title: '${topic?.name ?? ''} — 지금까지 정한 내용',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSize.gapS,
            runSpacing: AppSize.gapS,
            children: [
              BigButton(
                label: '읽어주기',
                image: AppIcons3d.speaker,
                expand: false,
                onPressed: readText.isEmpty ? null : () => readAloud(context, c, '${topic?.name ?? ''}에서 정한 내용. $readText'),
              ),
              BigButton(
                label: aiBusy ? 'AI가 정리하는 중…' : 'AI로 깔끔하게 정리',
                image: AppIcons3d.robot,
                expand: false,
                kind: ButtonKind.accent,
                onPressed: aiBusy ? null : _ai,
              ),
            ],
          ),
          const SizedBox(height: AppSize.gapL),
          if (digest != null) ...[
            SectionCard(
              title: 'AI가 정리한 내용',
              image: AppIcons3d.sparkles,
              children: [
                Text(digest.$1, style: tt.bodyLarge),
                const SizedBox(height: AppSize.gapS),
                Text('정리한 날: ${dateTimeText.format(digest.$3)}', style: tt.bodySmall),
              ],
            ),
            const SizedBox(height: AppSize.gapL),
          ],
          Text('대화에서 찾은 "정한 내용"', style: tt.titleLarge),
          const SizedBox(height: AppSize.gapS),
          if (ds == null)
            const Center(child: CircularProgressIndicator())
          else if (ds.isEmpty)
            const EmptyState(mood: MascotMood.warning, title: '아직 정한 내용을 못 찾았어요', message: '대화에 "하기로 했어요", "정했어요" 같은 말이 있으면 여기에 모여요.')
          else
            for (final d in ds) ...[
              Container(
                padding: const EdgeInsets.all(AppSize.gapM),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(AppSize.radius),
                  border: Border.all(color: p.border, width: p.borderWidth),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: p.success),
                        const SizedBox(width: 8),
                        Expanded(child: Text(d.text, style: tt.bodyLarge)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SourceBadge(d.source, small: true),
                        Text(dateText.format(d.when), style: tt.bodySmall),
                        BigButton(
                          label: '대화 보기: ${d.conversationTitle}',
                          icon: Icons.open_in_new_rounded,
                          expand: false,
                          kind: ButtonKind.quiet,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ConversationScreen(id: d.conversationId, highlight: [d.text]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSize.gapS),
            ],
        ],
      ),
    );
  }
}
