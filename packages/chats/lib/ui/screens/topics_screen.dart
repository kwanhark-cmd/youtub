import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../classify/ai_provider.dart';
import '../../models/models.dart';
import '../../services/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/dialogs.dart';
import '../widgets/page.dart';
import '../shell.dart';
import '../widgets/voice_input.dart';
import 'conversation_screen.dart';
import 'decisions_screen.dart';
import 'import_screen.dart';
import 'settings_screen.dart';

/// 정리하기: 무료(낱말 기준) 또는 AI(비용 안내 + 보내는 범위 동의 후).
Future<void> startClassify(BuildContext context, List<int> ids) async {
  final c = context.read<AppController>();
  if (ids.isEmpty) {
    showNotice(context, '정리할 대화가 없어요.', kind: StatusKind.check);
    return;
  }
  final hasKey = await c.hasApiKey();
  if (!context.mounted) return;
  final choice = await pickOne<String>(
    context,
    title: '어떻게 정리할까요?',
    message: '대화 ${ids.length}개를 주제별로 나누고 한두 줄 요약을 붙여요.',
    options: [('free', '무료로 정리하기(낱말 기준, 인터넷 필요 없음)'), ('ai', c.aiReady && hasKey ? 'AI로 더 똑똑하게 정리하기(비용 있음)' : 'AI로 정리하기(먼저 설정이 필요해요)')],
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'free') {
    final j = await c.classify(ids, useAi: false);
    if (context.mounted && j != null) {
      showNotice(context, j.message ?? '', kind: j.state == JobState.done ? StatusKind.done : StatusKind.check);
    }
    return;
  }
  if (!c.aiReady || !hasKey) {
    await showInfo(
      context,
      title: 'AI 연결이 필요해요',
      message: '설정 > AI 연결에서 연결 키를 넣고, 무엇을 보낼지 고른 뒤 동의해 주세요. 그 전까지는 무료 정리를 쓸 수 있어요.',
      mood: MascotMood.warning,
    );
    if (context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen(focusAi: true)));
    return;
  }
  final s = c.session!;
  final est = await s.classifier.estimate(ids, s.settings.shareScope, s.settings.aiModel);
  if (!context.mounted) return;
  final month = s.store.costThisMonth();
  final ok = await confirmOnce(
    context,
    title: 'AI로 보내기 전에 확인해 주세요',
    message:
        '• 보내는 내용: ${s.settings.shareScope.label}\n'
        '• 대화 수: ${est.conversations}개\n'
        '• 예상 비용: ${est.wonText} (약 \$${est.usd.toStringAsFixed(3)})\n'
        '• 이번 달 사용: 약 \$${month.toStringAsFixed(2)} / 한도 \$${s.settings.monthlyCapUsd.toStringAsFixed(2)}\n\n'
        '한도를 넘으면 자동으로 멈춰요.',
    confirmLabel: '보내고 정리하기',
  );
  if (!ok || !context.mounted) return;
  final j = await c.classify(ids, useAi: true);
  if (context.mounted && j != null) {
    showNotice(context, j.message ?? '', kind: j.state == JobState.done ? StatusKind.done : StatusKind.check);
  }
}

class TopicsScreen extends StatelessWidget {
  final bool asTab;
  const TopicsScreen({super.key, this.asTab = false});

  List<(Topic, int)> _tree(List<Topic> all) {
    final byParent = <int?, List<Topic>>{};
    final ids = all.map((t) => t.id).toSet();
    for (final t in all) {
      final parent = ids.contains(t.parentId) ? t.parentId : null;
      byParent.putIfAbsent(parent, () => []).add(t);
    }
    final out = <(Topic, int)>[];
    void walk(int? parent, int depth) {
      final list = [...?byParent[parent]];
      list.sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : a.name.compareTo(b.name));
      for (final t in list) {
        out.add((t, depth));
        if (depth < 6) walk(t.id, depth + 1);
      }
    }

    walk(null, 0);
    return out;
  }

  Future<void> _menu(BuildContext context, Topic t) async {
    final c = context.read<AppController>();
    final s = c.session!;
    final action = await pickOne<String>(
      context,
      title: '"${t.name}" 주제',
      options: [
        ('rename', '이름 바꾸기'),
        ('move', '다른 주제 아래로 옮기기(하위 주제)'),
        ('top', '맨 위 주제로 꺼내기'),
        ('merge', '다른 주제와 합치기'),
        ('delete', '주제 지우기(대화는 남아요)'),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'rename':
        final n = await askText(context, title: '새 이름', initial: t.name, confirmLabel: '바꾸기');
        if (n != null && n.trim().isNotEmpty) {
          final old = t.name;
          s.topics.rename(t.id, n);
          c.touch();
          if (context.mounted) {
            showNotice(
              context,
              '이름을 바꿨어요. 다음 자동 정리도 새 이름을 써요.',
              onUndo: () {
                s.topics.rename(t.id, old);
                c.touch();
              },
            );
          }
        }
      case 'move':
        final others = s.topics.all().where((x) => x.id != t.id).toList();
        final target = await pickOne<int>(context, title: '어느 주제 아래로 옮길까요?', options: [for (final o in others) (o.id, o.name)]);
        if (target != null) {
          final ok = s.topics.setParent(t.id, target);
          c.touch();
          if (context.mounted && !ok) showNotice(context, '자기 아래 주제로는 옮길 수 없어요.', kind: StatusKind.check);
        }
      case 'top':
        s.topics.setParent(t.id, null);
        c.touch();
      case 'merge':
        final others = s.topics.all().where((x) => x.id != t.id).toList();
        final into = await pickOne<int>(context, title: '"${t.name}"을(를) 어느 주제로 합칠까요?', options: [for (final o in others) (o.id, o.name)]);
        if (into == null || !context.mounted) return;
        final name = others.firstWhere((o) => o.id == into).name;
        if (await confirmTwice(
          context,
          title: '주제를 합칠까요?',
          message: '"${t.name}"의 대화가 모두 "$name"(으)로 옮겨지고 "${t.name}"은 없어져요.',
          confirmLabel: '합칠게요',
        )) {
          s.topics.merge(t.id, into);
          c.touch();
        }
      case 'delete':
        if (await confirmTwice(
          context,
          title: '"${t.name}" 주제를 지울까요?',
          message: '주제만 지워져요. 대화는 그대로 남고 다른 주제에서 볼 수 있어요.',
          confirmLabel: '지울게요',
        )) {
          s.topics.delete(t.id);
          c.touch();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final s = c.session!;
    final p = AppTheme.of(context).palette;
    final tt = Theme.of(context).textTheme;
    final tree = _tree(s.topics.all());
    final total = s.store.count();
    final wide = asTab && isWide(context);
    final listColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TipBubble(id: 'topics', text: '주제는 폴더예요. 대화를 다른 주제로 옮기면 다음 정리 때도 기억해요.'),
        Wrap(
          spacing: AppSize.gapS,
          runSpacing: AppSize.gapS,
          children: [
            BigButton(
              label: '다시 정리하기',
              image: AppIcons3d.sparkles,
              expand: false,
              kind: ButtonKind.accent,
              onPressed: c.busy ? null : () => startClassify(context, c.allIds()),
            ),
            BigButton(
              label: '새 주제 만들기',
              icon: Icons.create_new_folder_rounded,
              expand: false,
              kind: ButtonKind.primary,
              onPressed: () async {
                final n = await askText(context, title: '새 주제 이름', hint: '예: 여행 계획', confirmLabel: '만들기');
                if (n != null && n.trim().isNotEmpty) {
                  s.topics.create(n);
                  c.touch();
                }
              },
            ),
          ],
        ),
        const SizedBox(height: AppSize.gapL),
        if (total == 0)
          EmptyState(
            title: '아직 주제가 없어요',
            message: '이렇게 시작하세요: 대화 기록을 넣으면 자동으로 주제별로 나눠 드려요.',
            actionLabel: '대화 넣기',
            onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportScreen())),
          )
        else if (tree.isEmpty)
          EmptyState(
            title: '아직 나누지 않았어요',
            message: '"다시 정리하기"를 누르면 주제별로 나눠요.',
            actionLabel: '정리하기',
            onAction: () => startClassify(context, c.allIds()),
          )
        else
          for (final (i, (t, depth)) in tree.indexed) ...[
            AppearUp(
              index: i,
              child: Padding(
                padding: EdgeInsets.only(left: 24.0 * depth),
                child: Container(
                  decoration: BoxDecoration(
                    color: wide && _selected.value == t.id ? Color.lerp(p.surface, TopicColors.of(t.id), 0.2) : p.surface,
                    borderRadius: BorderRadius.circular(AppSize.radius),
                    border: p.borderWidth > 1 ? Border.all(color: p.border, width: p.borderWidth) : null,
                    boxShadow: p.borderWidth > 1 ? null : AppShadows.soft(p),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppSize.radius),
                      onTap: () => wide
                          ? _selected.value = t.id
                          : Navigator.of(context).push(MaterialPageRoute(builder: (_) => TopicDetailScreen(topicId: t.id))),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: AppSize.buttonHeight + 8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              if (depth > 0) Icon(Icons.subdirectory_arrow_right_rounded, color: p.textMuted),
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(color: TopicColors.of(t.id), borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.folder_rounded, color: Colors.white, size: 26),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(t.name, style: tt.titleMedium)),
                              StatusBadge(kind: StatusKind.progress, text: '${t.count}개'),
                              IconButton(
                                tooltip: '주제 관리',
                                iconSize: 30,
                                icon: Icon(Icons.more_vert_rounded, color: p.text),
                                onPressed: () => _menu(context, t),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSize.gapS),
          ],
      ],
    );
    if (!wide) return AppPage(title: '주제별 보기', isHome: asTab, body: listColumn);
    // 넓은 화면: 왼쪽 주제 폴더 + 가운데 목록(+ 오른쪽 본문)
    return AppPage(
      title: '주제별 보기',
      isHome: true,
      scroll: false,
      body: ValueListenableBuilder<int?>(
        valueListenable: _selected,
        builder: (context, sel, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 380,
              child: SingleChildScrollView(
                key: const PageStorageKey<String>('topics-list'),
                padding: const EdgeInsets.only(bottom: AppSize.gapXxl, right: AppSize.gapS),
                child: listColumn,
              ),
            ),
            VerticalDivider(width: 1, color: p.border),
            Expanded(
              child: sel == null || s.topics.byId(sel) == null
                  ? const Center(
                      child: EmptyState(title: '왼쪽에서 주제를 고르세요', message: '고른 주제의 대화가 여기에 보여요.'),
                    )
                  : TopicDetailScreen(key: ValueKey(sel), topicId: sel, embedded: true),
            ),
          ],
        ),
      ),
    );
  }

  static final _selected = ValueNotifier<int?>(null);
}

/// 주제 하나 안의 대화 목록. "나누기"로 골라서 새 주제를 만들 수 있음.
class TopicDetailScreen extends StatefulWidget {
  final int topicId;
  final bool embedded;
  const TopicDetailScreen({super.key, required this.topicId, this.embedded = false});
  @override
  State<TopicDetailScreen> createState() => _TopicDetailScreenState();
}

class _TopicDetailScreenState extends State<TopicDetailScreen> {
  static const pageSize = 30;
  int shown = pageSize;
  bool selecting = false;
  final selected = <int>{};

  Future<void> _split() async {
    final c = context.read<AppController>();
    final s = c.session!;
    if (selected.isEmpty) {
      showNotice(context, '새 주제로 나눌 대화를 먼저 골라 주세요.', kind: StatusKind.check);
      return;
    }
    final n = await askText(context, title: '새 주제 이름', message: '고른 ${selected.length}개 대화를 새 주제로 나눠요.', confirmLabel: '나누기');
    if (n == null || n.trim().isEmpty) return;
    s.topics.split(widget.topicId, n, selected.toList());
    for (final id in selected) {
      await s.classifier.userMove(id, s.topics.byName(n)!.id);
    }
    setState(() {
      selecting = false;
      selected.clear();
    });
    c.touch();
    if (mounted) showNotice(context, '"$n" 주제로 나눴어요.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final s = c.session!;
    final topic = s.topics.byId(widget.topicId);
    if (topic == null) {
      return const AppPage(
        title: '주제',
        body: EmptyState(mood: MascotMood.warning, title: '주제를 찾을 수 없어요', message: '합쳐졌거나 지워졌을 수 있어요.'),
      );
    }
    final total = s.store.count(topicId: topic.id);
    final list = s.store.list(topicId: topic.id, limit: shown);
    final tt = Theme.of(context).textTheme;
    final listColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('대화 $total개', style: tt.bodySmall),
        const SizedBox(height: AppSize.gapM),
        Wrap(
          spacing: AppSize.gapS,
          runSpacing: AppSize.gapS,
          children: [
            BigButton(
              label: '정한 내용 보기',
              image: AppIcons3d.memo,
              expand: false,
              kind: ButtonKind.accent,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TopicDigestScreen(topicId: topic.id))),
            ),
            BigButton(
              label: selecting ? '고른 대화 나누기 (${selected.length})' : '나누기',
              icon: Icons.call_split_rounded,
              expand: false,
              kind: selecting ? ButtonKind.success : ButtonKind.primary,
              onPressed: selecting ? _split : () => setState(() => selecting = true),
            ),
            if (selecting)
              BigButton(
                label: '그만두기',
                icon: Icons.close_rounded,
                expand: false,
                kind: ButtonKind.quiet,
                onPressed: () => setState(() {
                  selecting = false;
                  selected.clear();
                }),
              ),
          ],
        ),
        const SizedBox(height: AppSize.gapM),
        VoiceTextField(
          hint: '이 주제 안에서 찾기',
          onSubmit: (t) {
            // 주제 안 검색: 일반 검색 결과에서 이 주제만
            final ids = s.store.list(topicId: topic.id, limit: 100000).map((e) => e.id).toSet();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _TopicSearchResults(text: t, ids: ids),
              ),
            );
          },
        ),
        const SizedBox(height: AppSize.gapM),
        for (final (i, conv) in list.indexed) ...[
          AppearUp(
            index: i % pageSize,
            child: ConversationTile(
              c: conv,
              leading: selecting
                  ? Checkbox(
                      value: selected.contains(conv.id),
                      onChanged: (v) => setState(() => v == true ? selected.add(conv.id) : selected.remove(conv.id)),
                    )
                  : null,
              onOpen: selecting
                  ? () => setState(() => selected.contains(conv.id) ? selected.remove(conv.id) : selected.add(conv.id))
                  : () => _openConv(conv.id),
              selected: openConv == conv.id,
            ),
          ),
          const SizedBox(height: AppSize.gapM),
        ],
        if (list.length < total)
          BigButton(label: '더 보기', icon: Icons.expand_more_rounded, onPressed: () => setState(() => shown += pageSize)),
      ],
    );
    final p = AppTheme.of(context).palette;
    if (!widget.embedded) return AppPage(title: topic.name, body: listColumn);
    final three = MediaQuery.sizeOf(context).width >= 1400;
    final listPane = Material(
      color: p.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSize.pagePadding, AppSize.gapM, AppSize.pagePadding, 0),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(color: TopicColors.of(topic.id), shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(header: true, child: Text(topic.name, style: Theme.of(context).textTheme.titleLarge)),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              key: PageStorageKey<String>('topic-${topic.id}'),
              padding: const EdgeInsets.fromLTRB(AppSize.pagePadding, AppSize.gapS, AppSize.pagePadding, AppSize.gapXxl),
              child: listColumn,
            ),
          ),
        ],
      ),
    );
    if (!three) return listPane;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 440, child: listPane),
        VerticalDivider(width: 1, color: p.border),
        Expanded(
          child: openConv == null
              ? const Center(
                  child: EmptyState(title: '대화를 고르세요', message: '고른 대화의 전체 내용이 여기에 보여요.'),
                )
              : ConversationScreen(key: ValueKey(openConv), id: openConv!, embedded: true, onClosed: () => setState(() => openConv = null)),
        ),
      ],
    );
  }

  int? openConv;

  void _openConv(int id) {
    if (widget.embedded && MediaQuery.sizeOf(context).width >= 1400) {
      setState(() => openConv = id);
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConversationScreen(id: id)));
    }
  }
}

class _TopicSearchResults extends StatefulWidget {
  final String text;
  final Set<int> ids;
  const _TopicSearchResults({required this.text, required this.ids});
  @override
  State<_TopicSearchResults> createState() => _TopicSearchResultsState();
}

class _TopicSearchResultsState extends State<_TopicSearchResults> {
  List<ConversationSummary>? results;
  List<String> words = const [];

  @override
  void initState() {
    super.initState();
    final s = context.read<AppController>().session!;
    final q = parseQuery(widget.text, s.settings);
    words = s.search.highlightWords(q);
    s.search.search(q, limit: 200).then((page) {
      if (mounted) {
        setState(() => results = page.hits.where((h) => widget.ids.contains(h.conversation.id)).map((h) => h.conversation).toList());
      }
    });
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: '"${widget.text}" 찾기',
    body: results == null
        ? const Center(child: CircularProgressIndicator())
        : results!.isEmpty
        ? const EmptyState(mood: MascotMood.warning, title: '이 주제에는 없어요', message: '다른 낱말로 해 보세요.')
        : Column(
            children: [
              for (final r in results!) ...[
                ConversationTile(
                  c: r,
                  highlight: words,
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ConversationScreen(id: r.id, highlight: words),
                    ),
                  ),
                ),
                const SizedBox(height: AppSize.gapM),
              ],
            ],
          ),
  );
}
