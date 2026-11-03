import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/celebrate.dart';
import '../keys.dart';
import '../widgets/common.dart';
import '../widgets/status_chips.dart';
import '../../core/format.dart';
import 'timelapse_screen.dart';
import 'import_screen.dart';
import 'classify_screen.dart';
import 'discard_screen.dart';
import 'item_detail_screen.dart';
import 'item_list_screen.dart';
import 'notices_screen.dart';
import 'progress_screen.dart';
import 'register_screen.dart';
import 'sell_screen.dart';
import 'settings_screen.dart';

void go(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

/// 결정하고 축하하고 되돌리기를 보여 주는 공용 동작
Future<void> decideWithUndo(BuildContext context, Item item, Decision d) async {
  final s = context.read<AppState>();
  final before = await s.decide(item, d);
  if (!context.mounted) return;
  celebrate(context, decision: d, message: '${d.label}(으)로 정했어요');
  toast(context, '"${item.name}" → ${d.label}', actionLabel: '되돌리기', onAction: () => s.restore(before));
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showMissed());
  }

  /// 앱을 열면 밀린 알림(1년 이동 등)을 먼저 보여 줌
  void _showMissed() {
    final s = context.read<AppState>();
    // 오늘 아침 알림이 새로 왔으면 음성으로도 안내
    if (s.unread.any((n) => n.kind == 'daily')) s.say(s.todaySpeech());
    final important = s.unread.where((n) => n.kind == 'one_year_moved' || n.kind == 'one_year_warn').toList();
    if (important.isEmpty) return;
    showMessage(
      important.first.title,
      actionLabel: '알림 보기',
      onAction: () => navKey.currentState?.push(MaterialPageRoute(builder: (_) => const NoticesScreen())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.palette;
    final st = s.stats;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSizes.page,
        title: Row(
          children: [
            const AppIconView(size: 40),
            const SizedBox(width: 10),
            Flexible(child: Text(s.global.appName, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          if (s.hasUpdate)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ActionChip(
                backgroundColor: p.attention,
                label: Text(
                  '새 버전 있어요',
                  style: TextStyle(color: p.onAttention, fontWeight: FontWeight.w700),
                ),
                onPressed: () => go(context, const SettingsScreen()),
              ),
            ),
          IconButton(
            tooltip: '알림',
            iconSize: 30,
            onPressed: () => go(context, const NoticesScreen()),
            icon: Badge(isLabelVisible: s.unread.isNotEmpty, label: Text('${s.unread.length}'), child: const Icon(Icons.notifications_rounded)),
          ),
          IconButton(tooltip: '설정', iconSize: 30, onPressed: () => go(context, const SettingsScreen()), icon: const Icon(Icons.settings_rounded)),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            // 넓은 화면(컴퓨터)에서는 가운데 720px 폭으로 (사진이 너무 커지지 않게)
            final side = box.maxWidth > 752 ? (box.maxWidth - 720) / 2 : AppSizes.page;
            return ListView(
              key: const PageStorageKey('home_1'),
              padding: EdgeInsets.fromLTRB(side, 4, side, AppSizes.cardGap),
              children: [
                if (s.unread.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.gap),
                    child: BigButton(
                      label: '밀린 알림 ${s.unread.length}개 보기',
                      emoji: 'bell',
                      color: p.attention,
                      textColor: p.onAttention,
                      onTap: () => go(context, const NoticesScreen()),
                    ),
                  ),
                const FirstTimeTip(id: 'home', text: '맨 위 "오늘 할 일"에서 하루에 물건 하나만 정하면 돼요. 아래 큰 동그라미 버튼으로 물건을 찍어 등록해요.'),
                // 1) 주인공: 오늘 할 일
                TodayHero(item: s.today),
                const SizedBox(height: AppSizes.cardGap),
                // 2) 숫자 띠
                StatStrip(
                  stats: [('${st?.done ?? 0}개', '비운 물건'), (won(st?.income ?? 0), '판매 수입'), ('${st?.undecided ?? 0}개', '아직 안 정함')],
                  onTap: () => go(context, const ProgressScreen()),
                ),
                const SizedBox(height: AppSizes.cardGap),
                // 3) 분류별 타일 3개 (색이 모두 다름)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: CategoryTile(
                        decision: Decision.use,
                        count: '${st?.use ?? 0}',
                        sub: '두고 쓸 물건',
                        onTap: () => go(context, const ItemListScreen(initial: Decision.use)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CategoryTile(decision: Decision.sell, count: '${st?.sell ?? 0}', sub: '판매글 만들기', onTap: () => go(context, const SellScreen())),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CategoryTile(
                        decision: Decision.discard,
                        count: '${st?.discard ?? 0}',
                        sub: '버리는 방법',
                        onTap: () => go(context, const DiscardScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.cardGap),
                // 4) 보조 행동 (작게)
                if ((st?.undecided ?? 0) > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.gap),
                    child: BigButton(
                      label: '밀어서 정리하기 (${st!.undecided}개 남음)',
                      emoji: 'clipboard',
                      color: p.progress,
                      onTap: () => go(context, const ClassifyScreen()),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _link(context, 'package', '모든 물건 ${st?.total ?? 0}개', const ItemListScreen()),
                    _link(context, 'chart', '진행 현황', const ProgressScreen()),
                    _link(context, 'video', '타임랩스', const TimelapseScreen()),
                    _link(context, 'speech', '정리 글 가져오기', const ImportScreen()),
                    _link(context, 'camera', '물건 등록', const RegisterScreen()),
                  ],
                ),
                const SizedBox(height: AppSizes.cardGap),
                StatusChips(onTap: () => go(context, const SettingsScreen())),
              ],
            );
          },
        ),
      ),
      // 촬영 버튼은 화면 아래 가운데 고정 띠에 (내용을 가리지 않음)
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(color: p.surface, boxShadow: AppShadows.soft(p)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [CaptureButton(emoji: 'camera', label: '찍어서 등록', onTap: () => go(context, const RegisterScreen(autoStart: true)))],
            ),
          ),
        ),
      ),
    );
  }

  Widget _link(BuildContext context, String emoji, String label, Widget page) {
    final p = context.palette;
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () => go(context, page),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.touchMin),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Emoji3D(emoji, size: 26),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 오늘 할 일 (주인공 카드): 화면 폭 전체 큰 사진 + 큰 분류 버튼 3개
class TodayHero extends StatelessWidget {
  final Item? item;
  const TodayHero({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.read<AppState>();
    final t = Theme.of(context).textTheme;
    final it = item;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppSizes.radius + 6), boxShadow: AppShadows.raised(p)),
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius + 6),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: p.attention,
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
              child: Row(
                children: [
                  const Emoji3D('calendar', size: 32),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('오늘 할 일', style: t.titleLarge?.copyWith(color: p.onAttention)),
                  ),
                  IconButton(
                    tooltip: '읽어 주기',
                    iconSize: 30,
                    color: p.onAttention,
                    icon: const Icon(Icons.volume_up_rounded),
                    onPressed: () => s.say(s.todaySpeech()),
                  ),
                ],
              ),
            ),
            if (it == null)
              EmptyState(
                message: s.items.isEmpty ? '첫 물건을 찍어 보세요' : '정할 물건을 다 정했어요! 새 물건을 등록해 보세요.',
                mood: s.items.isEmpty ? MascotMood.hello : MascotMood.celebrate,
                buttonLabel: '물건 찍기',
                onButton: () => go(context, const RegisterScreen(autoStart: true)),
              )
            else ...[
              GestureDetector(
                onTap: () => go(context, ItemDetailScreen(itemId: it.id!)),
                child: AspectRatio(aspectRatio: 4 / 3, child: ItemPhoto(it, full: true)),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSizes.gap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('오늘은 이 물건 하나만 정해 보세요', style: t.bodySmall),
                    Text(it.name, style: t.headlineMedium),
                    if (it.aiSuggestion != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Emoji3D('idea', size: 24),
                            Text('추천', style: t.bodySmall),
                            decisionChip(context, it.aiSuggestion),
                            if (it.aiReason.isNotEmpty) Text(it.aiReason, style: t.bodySmall),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppSizes.gap),
                    DecisionButtons(onPick: (d) => decideWithUndo(context, it, d)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
