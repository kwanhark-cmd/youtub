import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'pressable.dart';

enum ButtonKind { primary, accent, danger, success, info, quiet }

/// 큰 색 버튼(최소 높이 56). 회색 글자 버튼은 쓰지 않습니다.
class BigButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? image;
  final ButtonKind kind;
  final bool expand;

  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.image,
    this.kind = ButtonKind.primary,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context).palette;
    final (bg, fg) = switch (kind) {
      ButtonKind.primary => (p.primary, p.onPrimary),
      ButtonKind.accent => (p.accent, p.onAccent),
      ButtonKind.danger => (p.danger, p.onDanger),
      ButtonKind.success => (p.success, p.onSuccess),
      ButtonKind.info => (p.info, p.onInfo),
      ButtonKind.quiet => (p.surfaceAlt, p.primaryText == p.primary ? p.primary : p.text),
    };
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (image != null) ...[Image.asset(image!, width: 30, height: 30), const SizedBox(width: 10)],
          if (icon != null && image == null) ...[Icon(icon, color: fg, size: AppSize.iconButton), const SizedBox(width: 10)],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge!.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSize.buttonHeight, minWidth: AppSize.minTouch),
      child: Pressable(
        onTap: onPressed,
        color: bg,
        raised: kind != ButtonKind.quiet,
        border: kind == ButtonKind.quiet ? BorderSide(color: p.border, width: p.borderWidth) : null,
        semanticLabel: label,
        child: Center(widthFactor: expand ? null : 1, child: content),
      ),
    );
  }
}

/// 메인 화면 타일: 3D 아이콘 + 이름 + 한 줄 설명.
class HomeTile extends StatelessWidget {
  final String image;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;
  final String? badge;

  const HomeTile({
    super.key,
    required this.image,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.color,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context).palette;
    final tt = Theme.of(context).textTheme;
    return Pressable(
      onTap: onTap,
      color: p.surface,
      borderRadius: BorderRadius.circular(AppSize.radiusCard),
      border: BorderSide(color: p.border, width: p.borderWidth),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(p.surface, color, 0.10)!, p.surface],
      ),
      semanticLabel: '$title. $subtitle',
      child: Padding(
        padding: const EdgeInsets.all(AppSize.gapL),
        child: Row(
          children: [
            Container(
              width: AppSize.iconTile + 8,
              height: AppSize.iconTile + 8,
              decoration: BoxDecoration(color: Color.lerp(p.surface, color, 0.18), borderRadius: BorderRadius.circular(AppSize.radius)),
              alignment: Alignment.center,
              child: Image.asset(image, width: AppSize.iconTile - 8, height: AppSize.iconTile - 8, excludeFromSemantics: true),
            ),
            const SizedBox(width: AppSize.gapL),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: tt.titleLarge),
                  const SizedBox(height: 2),
                  Text(subtitle, style: tt.bodySmall),
                ],
              ),
            ),
            if (badge != null) StatusBadge(kind: StatusKind.check, text: badge!),
            Icon(Icons.chevron_right_rounded, color: p.textMuted, size: 32),
          ],
        ),
      ),
    );
  }
}

/// 상태 배지(색 + 아이콘 + 글자. 색만으로 뜻을 전하지 않음).
class StatusBadge extends StatelessWidget {
  final StatusKind kind;
  final String text;
  const StatusBadge({super.key, required this.kind, required this.text});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = AppTheme.of(context).palette.status(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppSize.radiusSmall)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text, style: Theme.of(context).textTheme.labelMedium!.copyWith(color: fg)),
          ),
        ],
      ),
    );
  }
}

/// 어느 AI 대화인지 표시.
class SourceBadge extends StatelessWidget {
  final AiSource source;
  final bool small;
  const SourceBadge(this.source, {super.key, this.small = false});

  static Color colorOf(AppPalette p, AiSource s) => switch (s) {
    AiSource.claude => p.claude,
    AiSource.chatgpt => p.chatgpt,
    AiSource.gemini => p.gemini,
  };

  static IconData iconOf(AiSource s) => switch (s) {
    AiSource.claude => Icons.auto_awesome_rounded,
    AiSource.chatgpt => Icons.chat_bubble_rounded,
    AiSource.gemini => Icons.diamond_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context).palette;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 3 : 5),
      decoration: BoxDecoration(color: colorOf(p, source), borderRadius: BorderRadius.circular(AppSize.radiusSmall)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconOf(source), size: small ? 14 : 16, color: Colors.white),
          const SizedBox(width: 4),
          Text(source.label, style: Theme.of(context).textTheme.labelMedium!.copyWith(color: Colors.white)),
        ],
      ),
    );
  }
}

enum MascotMood { hello, working, done, warning, celebrate }

/// 비서 마스코트(표정별 그림).
class Mascot extends StatelessWidget {
  final MascotMood mood;
  final double size;
  const Mascot(this.mood, {super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    final label = switch (mood) {
      MascotMood.hello => '인사하는 비서',
      MascotMood.working => '일하는 비서',
      MascotMood.done => '다 끝낸 비서',
      MascotMood.warning => '확인이 필요하다고 알리는 비서',
      MascotMood.celebrate => '축하하는 비서',
    };
    final svg = SvgPicture.asset('assets/mascot/mascot_${mood.name}.svg', width: size, height: size, semanticsLabel: label);
    if (mood != MascotMood.working) return svg;
    return _Bob(child: svg);
  }
}

class _Bob extends StatefulWidget {
  final Widget child;
  const _Bob({required this.child});
  @override
  State<_Bob> createState() => _BobState();
}

class _BobState extends State<_Bob> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = AppTheme.of(context).motion(context, AppMotion.normal) == Duration.zero;
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) => Transform.translate(offset: Offset(0, -4 * Curves.easeInOut.transform(_c.value)), child: child),
    child: widget.child,
  );
}

/// 빈 화면: "아직 없어요 — 이렇게 시작하세요" + 큰 시작 버튼.
class EmptyState extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final MascotMood mood;

  const EmptyState({super.key, required this.title, required this.message, this.actionLabel, this.onAction, this.mood = MascotMood.hello});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(AppSize.gapXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Mascot(mood, size: 120),
          const SizedBox(height: AppSize.gapL),
          Text(title, style: tt.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: AppSize.gapS),
          Text(message, style: tt.bodyLarge, textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSize.gapXl),
            BigButton(label: actionLabel!, onPressed: onAction, kind: ButtonKind.accent, icon: Icons.play_arrow_rounded),
          ],
        ],
      ),
    );
  }
}

/// 제목이 있는 카드 묶음.
class SectionCard extends StatelessWidget {
  final String? title;
  final String? image;
  final List<Widget> children;
  final EdgeInsets padding;
  const SectionCard({super.key, this.title, this.image, required this.children, this.padding = const EdgeInsets.all(AppSize.gapL)});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (image != null) ...[
                    Image.asset(image!, width: 32, height: 32, excludeFromSemantics: true),
                    const SizedBox(width: AppSize.gapS),
                  ],
                  Expanded(child: Text(title!, style: Theme.of(context).textTheme.titleLarge)),
                ],
              ),
              const SizedBox(height: AppSize.gapM),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 켜기/끄기 줄(큰 터치 영역).
class SwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const SwitchRow({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSize.radiusSmall),
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSize.buttonHeight),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: tt.titleMedium),
                      if (subtitle != null) Text(subtitle!, style: tt.bodySmall),
                    ],
                  ),
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// 진행 막대 + 숫자.
class ProgressBar extends StatelessWidget {
  final double? value;
  final String label;
  const ProgressBar({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: value, minHeight: 14),
        ),
        const SizedBox(height: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// 검색어를 노란 배경으로 강조한 글.
class HighlightText extends StatelessWidget {
  final String text;
  final List<String> words;
  final TextStyle? style;
  final int? maxLines;
  const HighlightText(this.text, {super.key, this.words = const [], this.style, this.maxLines});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context).palette;
    final base = style ?? Theme.of(context).textTheme.bodyLarge!;
    final ws = words.where((w) => w.trim().isNotEmpty).map((w) => w.toLowerCase()).toList();
    if (ws.isEmpty) return Text(text, style: base, maxLines: maxLines, overflow: maxLines != null ? TextOverflow.ellipsis : null);
    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var i = 0;
    while (i < text.length) {
      var next = -1;
      var len = 0;
      for (final w in ws) {
        final at = lower.indexOf(w, i);
        if (at >= 0 && (next < 0 || at < next)) {
          next = at;
          len = w.length;
        }
      }
      if (next < 0) {
        spans.add(TextSpan(text: text.substring(i)));
        break;
      }
      if (next > i) spans.add(TextSpan(text: text.substring(i, next)));
      spans.add(
        TextSpan(
          text: text.substring(next, next + len),
          style: TextStyle(backgroundColor: p.highlight, fontWeight: FontWeight.w800, color: p.text),
        ),
      );
      i = next + len;
    }
    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : null,
    );
  }
}

/// 목록 항목이 순서대로 살짝 올라오며 나타나는 효과.
class AppearUp extends StatefulWidget {
  final Widget child;
  final int index;
  const AppearUp({super.key, required this.child, this.index = 0});
  @override
  State<AppearUp> createState() => _AppearUpState();
}

class _AppearUpState extends State<AppearUp> {
  bool _shown = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(AppMotion.stagger * widget.index.clamp(0, 8), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = AppTheme.of(context).motion(context, AppMotion.normal);
    if (d == Duration.zero) return widget.child;
    return AnimatedSlide(
      offset: _shown ? Offset.zero : const Offset(0, 0.08),
      duration: d,
      curve: AppMotion.curve,
      child: AnimatedOpacity(opacity: _shown ? 1 : 0, duration: d, child: widget.child),
    );
  }
}

/// 새 알림을 작게 흔들어 눈에 띄게.
class Wiggle extends StatefulWidget {
  final Widget child;
  const Wiggle({super.key, required this.child});
  @override
  State<Wiggle> createState() => _WiggleState();
}

class _WiggleState extends State<Wiggle> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppTheme.of(context).motion(context, AppMotion.normal) != Duration.zero && !_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) {
      final t = _c.value;
      final angle = math.sin(t * math.pi * 6) * 0.06 * (1 - t);
      return Transform.rotate(angle: angle, child: child);
    },
    child: widget.child,
  );
}

/// 완료 체크가 톡 튀어나오는 효과(움직임 줄이기면 바로 표시).
class CheckPop extends StatelessWidget {
  final double size;
  const CheckPop({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final d = theme.motion(context, AppMotion.slow);
    final icon = Icon(Icons.check_circle_rounded, color: theme.palette.success, size: size, semanticLabel: '완료');
    if (d == Duration.zero) return icon;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: d,
      curve: AppMotion.bounce,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: icon,
    );
  }
}
