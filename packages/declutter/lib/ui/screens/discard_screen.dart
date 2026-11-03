import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../services/disposal_guide.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/celebrate.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// 폐기 도우미 목록
class DiscardScreen extends StatelessWidget {
  const DiscardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.palette;
    final list = s.items.where((i) => i.decision == Decision.discard).toList()
      ..sort((a, b) => (a.discardDoneAt == null ? 0 : 1).compareTo(b.discardDoneAt == null ? 0 : 1));
    return AppPage(
      title: '폐기 도우미',
      body: ItemGrid(
        storageKey: 'discard_1',
        items: list,
        onTap: (it) => go(context, DiscardDetailScreen(itemId: it.id!)),
        header: Column(
          children: [
            if (s.user.regionLabel.isEmpty)
              Panel(
                border: p.attention,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('사는 지역을 알려 주시면 대형폐기물 신고 방법을 더 정확히 안내해요.', style: TextStyle(fontSize: 17)),
                    const SizedBox(height: 8),
                    BigButton(label: '지역 정하기', emoji: 'home', color: p.primary, onTap: () => go(context, const SettingsScreen())),
                  ],
                ),
              ),
            if (list.isEmpty) const EmptyState(message: '폐기로 정한 물건이 아직 없어요.', mood: MascotMood.thinking),
          ],
        ),
      ),
    );
  }
}

class DiscardDetailScreen extends StatefulWidget {
  final int itemId;
  const DiscardDetailScreen({super.key, required this.itemId});
  @override
  State<DiscardDetailScreen> createState() => _DiscardDetailScreenState();
}

class _DiscardDetailScreenState extends State<DiscardDetailScreen> {
  Item? item;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    final it = await s.repo.item(s.uid, widget.itemId);
    if (mounted) setState(() => item = it);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final it = item;
    if (it == null) {
      return const AppPage(
        title: '폐기',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final s = context.read<AppState>();
    final a = disposalAdviceFor(it, region: s.user.regionLabel);
    return AppPage(
      title: '폐기: ${it.name}',
      body: ListView(
        key: const PageStorageKey('discard_2'),
        padding: const EdgeInsets.all(AppSizes.page),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.radius),
            child: SizedBox(height: 180, child: ItemPhoto(it, height: 180, full: true)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => s.say('${it.name} 버리는 방법이에요. ${a.howTo} ${a.bulkySteps ?? ''} ${a.feeText ?? ''}'),
              icon: const Icon(Icons.volume_up_rounded, size: 28),
              label: const Text('읽어 주기'),
            ),
          ),
          const SectionTitle('버리는 방법'),
          Panel(child: Text(a.howTo, style: const TextStyle(fontSize: 17, height: 1.5))),
          if (a.bulky) ...[
            const SectionTitle('대형폐기물 신고'),
            Panel(
              border: p.attention,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StepList(splitSteps(a.bulkySteps!), color: p.discard),
                  const SizedBox(height: 8),
                  Text(a.feeText!, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
          const SectionTitle('무료 나눔·기부'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final g in a.giveAway)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('· $g', style: const TextStyle(fontSize: 17)),
                  ),
              ],
            ),
          ),
          const SectionTitle('디지털로 남기고 버리기'),
          Text(a.memory ? '추억이 담긴 물건이네요. 사진과 사연만 남기고 실물은 비워 보세요.' : '사진과 사연을 남겨 두면 버려도 기억은 남아요.', style: const TextStyle(fontSize: 17)),
          const SizedBox(height: 8),
          BigButton(
            label: it.digitalKeep ? '✓ 디지털로 남겼어요 (다시 저장)' : '사진·사연 남기고 버리기',
            emoji: 'memory',
            color: p.progress,
            onTap: () async {
              if (it.story.isEmpty) {
                final t = await listenOrType(context, title: '이 물건의 사연', hint: '기억하고 싶은 이야기를 말해 주세요', lines: 4);
                if (t != null) it.story = t.trim();
              }
              final dir = await s.keepDigitallyAndDiscard(it);
              if (context.mounted) toast(context, '3번 앱용 폴더에 저장했어요: ${dir.path.split(RegExp(r'[\\/]')).last}');
              _load();
            },
          ),
          const SectionTitle('다 버렸나요?'),
          BigButton(
            label: it.discardDoneAt == null ? '폐기 완료!' : '✓ 폐기 완료 (취소하기)',
            emoji: 'check',
            color: it.discardDoneAt == null ? p.discard : p.muted,
            onTap: () async {
              final done = it.discardDoneAt == null;
              if (done) {
                final ok = await confirmOnce(context, title: '폐기 완료', message: '"${it.name}"을(를) 다 버렸나요?', okLabel: '네, 버렸어요', danger: true);
                if (!ok) return;
              }
              await s.markDiscardDone(it, done: done);
              if (!context.mounted) return;
              if (done) {
                celebrate(context, decision: Decision.discard, message: '비우기 성공!');
                s.say('${it.name} 비우기 성공! 잘했어요.');
              }
              _load();
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
