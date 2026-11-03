import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// 누르면 살짝 눌리고 튀어오르는 입체 표면. 진동·소리 피드백(설정에서 켜고 끔).
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final BorderRadius borderRadius;
  final bool raised;
  final String? semanticLabel;
  final Gradient? gradient;
  final BorderSide? border;

  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    required this.color,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppSize.radius)),
    this.raised = true,
    this.semanticLabel,
    this.gradient,
    this.border,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void feedback(BuildContext context) {
    final s = context.read<AppController?>()?.settings;
    if (s == null || s.haptics) HapticFeedback.lightImpact();
    if (s == null || s.sounds) SystemSound.play(SystemSoundType.click);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final p = theme.palette;
    final enabled = widget.onTap != null;
    final dur = theme.motion(context, AppMotion.fast);
    final base = enabled ? widget.color : Color.lerp(widget.color, p.surfaceAlt, 0.55)!;
    final top = Color.lerp(base, Colors.white, 0.14)!;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: enabled
            ? () {
                feedback(context);
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1.0,
          duration: dur,
          curve: _down ? Curves.easeOut : AppMotion.bounce,
          child: AnimatedContainer(
            duration: dur,
            transform: Matrix4.translationValues(0, _down && widget.raised ? AppSize.depth - 2 : 0, 0),
            decoration: BoxDecoration(
              color: base,
              gradient:
                  widget.gradient ??
                  (widget.raised ? LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, base]) : null),
              borderRadius: widget.borderRadius,
              border: widget.border != null ? Border.fromBorderSide(widget.border!) : null,
              boxShadow: widget.raised && enabled ? AppShadows.raised(p, pressed: _down) : null,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: FocusableActionDetector(
                enabled: enabled,
                mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
                actions: {
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      widget.onTap?.call();
                      return null;
                    },
                  ),
                },
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
