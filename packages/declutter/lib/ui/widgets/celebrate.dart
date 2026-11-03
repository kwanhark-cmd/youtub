import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme/app_theme.dart';
import 'common.dart';

/// 분류 확정·판매·폐기 완료 때 마스코트 축하 + 체크 애니메이션.
/// "움직임 줄이기"가 켜지면 애니메이션 없이 바로 사라집니다.
Future<void> celebrate(BuildContext context, {Decision? decision, String message = '잘했어요!'}) async {
  final motion = context.motion;
  if (motion.reduce) return;
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  final color = decisionColor(context, decision);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => IgnorePointer(
      child: _CelebrateView(color: color, message: message, duration: motion.celebrate, onDone: () => entry.remove()),
    ),
  );
  overlay.insert(entry);
}

class _CelebrateView extends StatefulWidget {
  final Color color;
  final String message;
  final Duration duration;
  final VoidCallback onDone;
  const _CelebrateView({required this.color, required this.message, required this.duration, required this.onDone});
  @override
  State<_CelebrateView> createState() => _CelebrateViewState();
}

class _CelebrateViewState extends State<_CelebrateView> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: widget.duration)..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final t = c.value;
      final pop = Curves.elasticOut.transform((t * 1.6).clamp(0, 1));
      final fade = t < 0.75 ? 1.0 : 1 - (t - 0.75) / 0.25;
      return Opacity(
        opacity: fade.clamp(0, 1),
        child: Container(
          color: widget.color.withValues(alpha: 0.18 * fade),
          alignment: Alignment.center,
          child: Transform.scale(
            scale: 0.4 + 0.6 * pop,
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      const Mascot(MascotMood.celebrate, size: 150),
                      Transform.rotate(angle: (1 - pop) * 1.5, child: const Emoji3D('check', size: 64)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(24)),
                    child: Text(
                      widget.message,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
