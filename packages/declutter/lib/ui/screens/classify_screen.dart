import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../services/knowledge.dart';
import '../../services/voice_commands.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../keys.dart';
import '../widgets/celebrate.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'register_screen.dart';

/// 정리하기: 사진 한 장 크게 + 밀어서 분류
/// 왼쪽 = 폐기, 오른쪽 = 판매, 위 = 지금 쓰는 것. 버튼·음성도 가능.
class ClassifyScreen extends StatefulWidget {
  const ClassifyScreen({super.key});
  @override
  State<ClassifyScreen> createState() => _ClassifyScreenState();
}

class _ClassifyScreenState extends State<ClassifyScreen> with SingleTickerProviderStateMixin {
  Offset drag = Offset.zero;
  Decision? flying;
  late final AnimationController fly = AnimationController(vsync: this);
  bool asking = false;

  @override
  void dispose() {
    fly.dispose();
    super.dispose();
  }

  Decision? _dirOf(Offset o) {
    if (o.dy < -90 && o.dy.abs() > o.dx.abs()) return Decision.use;
    if (o.dx > 90) return Decision.sell;
    if (o.dx < -90) return Decision.discard;
    return null;
  }

  Future<void> _decide(Item item, Decision d) async {
    final motion = context.motion;
    setState(() => flying = d);
    fly.duration = motion.normal;
    if (motion.normal > Duration.zero) await fly.forward(from: 0);
    if (!mounted) return;
    await decideWithUndo(context, item, d);
    setState(() {
      flying = null;
      drag = Offset.zero;
      fly.value = 0;
    });
  }

  Future<void> _voice(Item item) async {
    final said = await listenOrType(context, title: '말로 정하기', hint: '"이건 판매", "이건 폐기", "지금 쓰는 것"', lines: 1);
    if (said == null || !mounted) return;
    final c = parseVoiceCommand(said);
    final s = context.read<AppState>();
    switch (c.kind) {
      case VoiceCommandKind.decide:
        final d = c.decision!;
        final ok =
            !c.needsConfirm ||
            await confirmOnce(context, title: '${d.label}(으)로 정할까요?', message: '"${item.name}"을(를) ${d.label}(으)로 정해요.', okLabel: '네, ${d.label}');
        if (ok && mounted) await _decide(item, d);
      case VoiceCommandKind.readToday:
        await s.say(s.todaySpeech());
      case VoiceCommandKind.readProgress:
        await s.say(s.progressSpeech());
      case VoiceCommandKind.unknown:
        if (mounted) toast(context, '"$said" — 알아듣지 못했어요. "판매", "폐기", "지금 쓰는 것" 중 하나로 말해 주세요.');
    }
  }

  Future<void> _help(Item item) async {
    final answers = <bool>[];
    for (final q in helpQuestions) {
      final live = liveContext(mounted ? context : null);
      if (live == null) return;
      final a = await showDialog<bool>(
        context: live,
        builder: (ctx) => AlertDialog(
          title: const Text('결정 도우미'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Mascot(MascotMood.thinking, size: 90),
              const SizedBox(height: 8),
              Text(q.text, style: const TextStyle(fontSize: 20), textAlign: TextAlign.center),
            ],
          ),
          actionsOverflowDirection: VerticalDirection.up,
          actions: [
            BigButton(label: '아니요', expand: false, color: ctx.palette.muted, onTap: () => Navigator.pop(ctx, false)),
            BigButton(label: '예', expand: false, onTap: () => Navigator.pop(ctx, true)),
          ],
        ),
      );
      if (a == null) return;
      answers.add(a);
    }
    final d = decideFromAnswers(answers);
    if (!mounted) return;
    final ok = await confirmOnce(context, title: '추천: ${d.label}', message: '답을 보니 "${d.label}"이(가) 좋겠어요. 이대로 정할까요?', okLabel: '네, ${d.label}');
    if (ok && mounted) await _decide(item, d);
  }

  Future<void> _askAi(Item item) async {
    final s = context.read<AppState>();
    setState(() => asking = true);
    final r = await s.ai.suggest(s.uid, s.user, item);
    item.aiSuggestion = r.value.decision;
    item.aiReason = r.value.reason;
    await s.saveItem(item);
    if (!mounted) return;
    setState(() => asking = false);
    if (r.message != null) toast(context, r.message!);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.palette;
    final list = s.items.where((i) => i.decision == null).toList().reversed.toList();
    if (list.isEmpty) {
      return AppPage(
        title: '정리하기',
        body: Center(
          child: SingleChildScrollView(
            child: EmptyState(
              message: s.items.isEmpty ? '아직 물건이 없어요. 첫 물건을 찍어 보세요.' : '모두 정했어요! 정말 잘했어요.',
              mood: s.items.isEmpty ? MascotMood.hello : MascotMood.celebrate,
              buttonLabel: '물건 찍으러 가기',
              onButton: () => go(context, const RegisterScreen()),
            ),
          ),
        ),
      );
    }
    final item = list.first;
    final hint = flying ?? _dirOf(drag);
    return AppPage(
      title: '정리하기 (${list.length}개 남음)',
      body: LayoutBuilder(
        builder: (context, c) {
          final cardH = max(220.0, min(c.maxHeight * 0.45, 420.0));
          return ListView(
            key: const PageStorageKey('classify_1'),
            padding: const EdgeInsets.all(AppSizes.page),
            children: [
              const FirstTimeTip(id: 'swipe', text: '사진을 왼쪽으로 밀면 폐기, 오른쪽은 판매, 위로 밀면 지금 쓰는 것이에요. 아래 버튼을 눌러도 돼요.'),
              _arrows(p),
              const SizedBox(height: 8),
              GestureDetector(
                onPanUpdate: (d) => setState(() => drag += d.delta),
                onPanEnd: (_) {
                  final d = _dirOf(drag);
                  if (d == null) {
                    setState(() => drag = Offset.zero);
                  } else {
                    _decide(item, d);
                  }
                },
                child: AnimatedBuilder(
                  animation: fly,
                  builder: (context, child) {
                    var o = drag;
                    if (flying != null) {
                      final t = Curves.easeIn.transform(fly.value);
                      final target = switch (flying!) {
                        Decision.use => const Offset(0, -900),
                        Decision.sell => const Offset(900, 0),
                        Decision.discard => const Offset(-900, 0),
                      };
                      o = Offset.lerp(drag, target, t)!;
                    }
                    return Transform.translate(
                      offset: o,
                      child: Transform.rotate(angle: o.dx / 1400, child: child),
                    );
                  },
                  child: _card(item, cardH, hint, p),
                ),
              ),
              const SizedBox(height: AppSizes.gap),
              DecisionButtons(onPick: (d) => _decide(item, d)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: BigButton(label: '말로 정하기', emoji: 'mic', color: p.progress, onTap: () => _voice(item)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BigButton(label: '잘 모르겠어요', emoji: 'idea', color: p.accent, onTap: () => _help(item)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (item.aiSuggestion == null)
                BigButton(label: asking ? '추천 받는 중…' : 'AI 추천 받기', emoji: 'speech', color: p.primary, onTap: asking ? null : () => _askAi(item)),
            ],
          );
        },
      ),
    );
  }

  Widget _arrows(AppPalette p) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    spacing: 8,
    runSpacing: 4,
    children: [Chip3('← 폐기', p.discard), Chip3('↑ 지금 쓰는 것', p.use), Chip3('판매 →', p.sell)],
  );

  Widget _card(Item item, double h, Decision? hint, AppPalette p) {
    final color = hint == null ? p.border : decisionColor(context, hint);
    return AnimatedContainer(
      duration: context.motion.fast,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: hint == null ? null : Border.all(color: color, width: 6),
        boxShadow: AppShadows.raised(p),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              SizedBox(
                height: h,
                child: ItemPhoto(item, height: h, full: true),
              ),
              if (hint != null)
                Positioned.fill(
                  child: Container(
                    color: color.withValues(alpha: flying != null ? 0.7 : 0.35),
                    alignment: Alignment.center,
                    child: Chip3(hint.label, color),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(AppSizes.gap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: Theme.of(context).textTheme.headlineMedium),
                if (item.condition.isNotEmpty || item.description.isNotEmpty)
                  Text([item.condition, item.description].where((t) => t.isNotEmpty).join(' · '), style: const TextStyle(fontSize: 17)),
                if (item.aiSuggestion != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Emoji3D('idea', size: 28),
                      const Text('추천:', style: TextStyle(fontSize: 17)),
                      decisionChip(context, item.aiSuggestion),
                    ],
                  ),
                  if (item.aiReason.isNotEmpty) Text(item.aiReason, style: TextStyle(color: p.muted, fontSize: 16)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 테스트·외부에서 쓰는 축하 함수 노출
Future<void> celebrateDecision(BuildContext context, Decision d) => celebrate(context, decision: d);
