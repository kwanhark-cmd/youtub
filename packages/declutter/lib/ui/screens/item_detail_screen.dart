import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'discard_screen.dart';
import 'home_screen.dart';
import 'sell_screen.dart';

/// 물건 자세히: 고치기, 분류 바꾸기, 사연 남기기, 지우기
class ItemDetailScreen extends StatefulWidget {
  final int itemId;
  const ItemDetailScreen({super.key, required this.itemId});
  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  Item? item;
  final name = TextEditingController();
  final kind = TextEditingController();
  final cond = TextEditingController();
  final room = TextEditingController();
  final spot = TextEditingController();
  final tags = TextEditingController();
  final desc = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    final it = await s.repo.item(s.uid, widget.itemId);
    if (!mounted) return;
    setState(() {
      item = it;
      if (it != null) {
        name.text = it.name;
        kind.text = it.kind;
        cond.text = it.condition;
        room.text = it.room;
        spot.text = it.spot;
        tags.text = it.tags;
        desc.text = it.description;
      }
    });
  }

  Future<void> _save({bool quiet = false}) async {
    final it = item!;
    it.name = name.text.trim().isEmpty ? it.name : name.text.trim();
    it.kind = kind.text.trim();
    it.condition = cond.text.trim();
    it.room = room.text.trim();
    it.spot = spot.text.trim();
    it.tags = tags.text.trim();
    it.description = desc.text.trim();
    await context.read<AppState>().saveItem(it);
    if (mounted && !quiet) toast(context, '저장했어요');
  }

  Future<void> _story() async {
    final it = item!;
    final t = await listenOrType(context, title: '이 물건에 얽힌 이야기', hint: '예: 결혼 10주년에 남편이 사 준 커피 머신', initial: it.story, lines: 4);
    if (t == null || !mounted) return;
    final dir = await context.read<AppState>().saveStory(it, t.trim());
    if (mounted) toast(context, '사연을 저장했어요. (1번 앱용 폴더: ${dir.path.split(RegExp(r'[\\/]')).reversed.take(2).toList().reversed.join('/')})');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final it = item;
    if (it == null) {
      return const AppPage(
        title: '물건',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final s = context.read<AppState>();
    return AppPage(
      title: it.name,
      body: ListView(
        key: const PageStorageKey('item_detail_1'),
        padding: const EdgeInsets.all(AppSizes.page),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.radius),
            child: SizedBox(height: 240, child: ItemPhoto(it, height: 240, full: true)),
          ),
          const SizedBox(height: AppSizes.gap),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              decisionChip(context, it.decision),
              if (it.saleStatus != null) Chip3(it.saleStatus!.label, p.progress),
              Chip3('등록 ${dateKo(it.createdAt)}', p.muted),
            ],
          ),
          if (it.aiSuggestion != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('추천: ${it.aiSuggestion!.label} — ${it.aiReason}', style: const TextStyle(fontSize: 16)),
            ),
          if (it.movedFromSaleAt != null)
            Panel(
              border: p.attention,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('1년 동안 안 팔려 폐기 목록으로 옮겨졌어요.', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  BigButton(
                    label: '판매로 되돌리기',
                    emoji: 'sell',
                    color: p.sell,
                    onTap: () async {
                      await s.sales.undoMoveToDiscard(it);
                      await s.refresh();
                      _load();
                    },
                  ),
                ],
              ),
            ),
          const SectionTitle('분류 바꾸기'),
          DecisionButtons(
            onPick: (d) async {
              await _save(quiet: true);
              if (!context.mounted) return;
              await decideWithUndo(context, it, d);
              _load();
            },
          ),
          if (it.decision == Decision.sell) ...[
            const SizedBox(height: 8),
            BigButton(
              label: '판매 도우미 열기',
              emoji: 'sell',
              color: p.sell,
              onTap: () => go(context, SellDetailScreen(itemId: it.id!)),
            ),
          ],
          if (it.decision == Decision.discard) ...[
            const SizedBox(height: 8),
            BigButton(
              label: '폐기 도우미 열기',
              emoji: 'recycle',
              color: p.discard,
              onTap: () => go(context, DiscardDetailScreen(itemId: it.id!)),
            ),
          ],
          const SectionTitle('사연 남기기'),
          if (it.story.isNotEmpty) Panel(child: Text(it.story, style: const TextStyle(fontSize: 17))),
          BigButton(label: it.story.isEmpty ? '말로 사연 남기기' : '사연 다시 남기기', emoji: 'mic', color: p.progress, onTap: _story),
          const SectionTitle('정보 고치기'),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: '이름'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: kind,
            decoration: const InputDecoration(labelText: '종류'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: cond,
            decoration: const InputDecoration(labelText: '상태'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: room,
            decoration: const InputDecoration(labelText: '방'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: spot,
            decoration: const InputDecoration(labelText: '자리'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: tags,
            decoration: const InputDecoration(labelText: '꼬리표 (쉼표로 구분)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: desc,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: '설명'),
          ),
          const SizedBox(height: 8),
          BigButton(
            label: '말로 설명 더하기',
            emoji: 'mic',
            color: p.progress,
            onTap: () async {
              final t = await listenOrType(context, title: '설명', initial: desc.text);
              if (t != null) setState(() => desc.text = t);
            },
          ),
          const SizedBox(height: AppSizes.gap),
          BigButton(label: '저장', emoji: 'check', color: p.primary, onTap: _save),
          const SizedBox(height: AppSizes.gapLarge),
          BigButton(
            label: '이 물건 지우기',
            icon: Icons.delete_forever_rounded,
            color: p.discard,
            onTap: () async {
              final ok = await confirmTwice(
                context,
                title: '물건 지우기',
                first: '"${it.name}"을(를) 목록에서 지울까요? (폐기 분류와는 달라요)',
                second: '지우면 되돌릴 수 없어요.',
                okLabel: '지우기',
              );
              if (!ok || !context.mounted) return;
              await s.deleteItem(it);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
