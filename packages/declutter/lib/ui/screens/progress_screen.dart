import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'item_list_screen.dart';
import 'timelapse_screen.dart';
import '../../data/models.dart';

/// 진행 현황: 큰 숫자와 진행 막대, 음성으로 듣기
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.palette;
    final st = s.stats;
    if (st == null) return const AppPage(title: '진행 현황', body: SizedBox());
    Widget number(String label, String value, Color color, String emoji, VoidCallback? tap) => Pressable(
      onTap: tap,
      semanticLabel: '$label $value',
      builder: (context, pressed) => Container(
        padding: const EdgeInsets.all(AppSizes.gap),
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withValues(alpha: 0.14), p.surface),
          borderRadius: BorderRadius.circular(AppSizes.radius),
          boxShadow: AppShadows.soft(p),
        ),
        child: Row(
          children: [
            Emoji3D(emoji, size: 44),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
            Flexible(
              child: Text(value, textAlign: TextAlign.end, style: Theme.of(context).textTheme.displaySmall),
            ),
          ],
        ),
      ),
    );
    final ratio = st.emptiedRatio;
    return AppPage(
      title: '진행 현황',
      body: ListView(
        key: const PageStorageKey('progress_1'),
        padding: const EdgeInsets.all(AppSizes.page),
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('비우기 진행', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '${(ratio * 100).round()}%',
                  style: TextStyle(fontSize: 48, fontWeight: FontWeight.w700, color: p.progress),
                ),
                BigProgress(ratio, label: '비우기 진행'),
                const SizedBox(height: 6),
                Text('판매·폐기로 정한 ${st.sell + st.discard}개 중 ${st.done}개를 비웠어요', style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
          BigButton(label: '음성으로 듣기', emoji: 'speaker', color: p.progress, onTap: () => s.say(s.progressSpeech())),
          const SizedBox(height: AppSizes.gap),
          number('전체 물건', '${st.total}개', p.primary, 'package', () => go(context, const ItemListScreen())),
          const SizedBox(height: AppSizes.gap),
          number('아직 안 정함', '${st.undecided}개', p.attention, 'hourglass', () => go(context, const ItemListScreen(undecided: true))),
          const SizedBox(height: AppSizes.gap),
          number('지금 쓰는 것', '${st.use}개', p.use, 'use', () => go(context, const ItemListScreen(initial: Decision.use))),
          const SizedBox(height: AppSizes.gap),
          number('판매 완료', '${st.sold} / ${st.sell}개', p.sell, 'sell', () => go(context, const ItemListScreen(initial: Decision.sell))),
          const SizedBox(height: AppSizes.gap),
          number('폐기 완료', '${st.discarded} / ${st.discard}개', p.discard, 'discard', () => go(context, const ItemListScreen(initial: Decision.discard))),
          const SizedBox(height: AppSizes.gap),
          number('판매 수입', won(st.income), p.sell, 'party', null),
          const SizedBox(height: AppSizes.gap),
          number('팔 물건 예상 가치', won(st.estimatedValue), p.accent, 'chart', null),
          const SizedBox(height: AppSizes.gap),
          BigButton(label: '집 비우기 타임랩스', emoji: 'video', color: p.accent, onTap: () => go(context, const TimelapseScreen())),
        ],
      ),
    );
  }
}
