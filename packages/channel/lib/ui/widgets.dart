import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/strings.dart';
import '../features/settings/app_look.dart';
import 'theme.dart';

/// 앱 전체 화면 길잡이 열쇠. 원래 화면이 사라졌을 때 살아 있는 화면으로 창을 띄우는 데 쓴다.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// 살아 있는 context 를 돌려준다. [c] 가 사라졌으면 앱 맨 위 화면, 그것도 없으면 null.
BuildContext? alive(BuildContext? c) {
  if (c != null && c.mounted) return c;
  return appNavigatorKey.currentState?.overlay?.context;
}

/// 화면 공통 기능에서 쓰는 연결점 (로그인하면 채워짐).
class UiHooks {
  /// 실패 창을 띄울 때마다 원인을 남기는 로그.
  static void Function(String message)? logError;

  /// "문제 신고 파일 만들기" — 만든 파일 경로를 돌려준다.
  static Future<String?> Function()? makeReport;
}

/// 진동·소리 피드백 설정 (로그인한 사용자 설정을 따라 바뀜).
class UiPrefs {
  static bool haptics = true;
  static bool sound = false;

  static void tap() {
    if (haptics) HapticFeedback.selectionClick();
    if (sound) SystemSound.play(SystemSoundType.click);
  }
}

/// 누르면 살짝 눌리고(두께가 줄고) 떼면 튀어 오르는 입체 효과.
class Press3D extends StatefulWidget {
  const Press3D({
    super.key,
    required this.child,
    required this.onTap,
    required this.color,
    this.radius = AppTokens.radius,
    this.depth = AppTokens.depth,
    this.semanticLabel,
    this.border,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final double radius;
  final double depth;
  final String? semanticLabel;
  final BorderSide? border;

  @override
  State<Press3D> createState() => _Press3DState();
}

class _Press3DState extends State<Press3D> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = widget.onTap != null;
    final base = enabled ? widget.color : Color.alphaBlend(t.background.withValues(alpha: 0.55), widget.color);
    final edge = AppTokens.darker(base, t.highContrast ? 0.35 : 0.16);
    final depth = enabled ? widget.depth : 1.0;
    final shift = _down ? depth - 1 : 0.0;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: t.fast,
          curve: _down ? Curves.easeOut : Curves.elasticOut,
          child: AnimatedContainer(
            duration: t.fast,
            margin: EdgeInsets.only(top: shift, bottom: depth - shift),
            decoration: BoxDecoration(
              color: edge,
              borderRadius: BorderRadius.circular(widget.radius),
              boxShadow: enabled ? (_down ? t.pressedShadow() : t.raised()) : null,
            ),
            child: Transform.translate(
              offset: Offset(0, -(depth - shift)),
              child: Material(
                color: base,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(widget.radius),
                  side: widget.border ?? (t.highContrast ? BorderSide(color: t.border, width: 2) : BorderSide.none),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: enabled
                      ? () {
                          UiPrefs.tap();
                          widget.onTap!();
                        }
                      : null,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 3D 그림 아이콘 (assets/icons3d). 그림이 없으면 일반 아이콘으로 대신한다.
class Icon3D extends StatelessWidget {
  const Icon3D(this.name, {super.key, this.size = AppTokens.icon3dM, this.fallback = Icons.circle});
  final String name;
  final double size;
  final IconData fallback;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image.asset(
      'assets/icons3d/$name.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => Icon(fallback, size: size * 0.8, color: context.tokens.primary),
    ),
  );
}

/// 상태 배지: 색 + 아이콘 + 글자 (색만으로 뜻을 전하지 않음).
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, this.label, {super.key, this.shake = false, this.colors});
  final Status status;
  final String label;
  final bool shake;

  /// (바탕, 글자) — 같은 상태 색 카드 위에 놓일 때 뒤집어 쓰기
  final (Color, Color)? colors;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = colors?.$2 ?? t.onStatusFor(status);
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.gapS + 2, vertical: AppTokens.gapXs),
      decoration: BoxDecoration(
        color: colors?.$1 ?? t.statusColor(status),
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppTokens.statusIcon(status), size: 18, color: fg),
          const SizedBox(width: AppTokens.gapXs),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: AppTokens.fontSmall),
            ),
          ),
        ],
      ),
    );
    return shake ? ShakeOnce(child: badge) : badge;
  }
}

/// 왼쪽에 상태 색 띠가 있는 평면 카드 (긴 목록용, 그림자 가볍게).
class StripeCard extends StatelessWidget {
  const StripeCard({super.key, required this.status, required this.child, this.onTap, this.thick = false});
  final Status? status;
  final Widget child;
  final VoidCallback? onTap;

  /// 테두리 전체를 상태 색으로 (채널 카드).
  final bool thick;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = status == null ? t.border : t.statusColor(status!);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppTokens.gapS - 2),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: thick
            ? Border.all(color: c, width: 3)
            : (t.highContrast ? Border.all(color: t.border, width: 2) : null),
        boxShadow: t.flat(),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  UiPrefs.tap();
                  onTap!();
                },
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 8, color: c),
                Expanded(
                  child: Padding(padding: const EdgeInsets.all(AppTokens.gapM), child: child),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 메인 화면의 큰 3D 타일: 3D 아이콘 + 짧은 이름 + 한 줄 설명 (+ 배지).
class Tile3D extends StatelessWidget {
  const Tile3D({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.fallback = Icons.apps,
  });
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? badge;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Press3D(
      color: t.card,
      onTap: onTap,
      semanticLabel: '$title. $subtitle',
      border: BorderSide(color: t.highContrast ? t.border : t.tonal, width: t.highContrast ? 2 : 1.5),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.gapL),
        child: Row(
          children: [
            Icon3D(icon, size: AppTokens.icon3dL, fallback: fallback),
            const SizedBox(width: AppTokens.gapM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: AppTokens.fontSection, fontWeight: FontWeight.w800, color: t.text),
                  ),
                  const SizedBox(height: AppTokens.gapXs),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: AppTokens.fontSmall, color: t.textSoft),
                  ),
                  if (badge != null) ...[const SizedBox(height: AppTokens.gapS), badge!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 원형 게이지 (남은 한도, AI 비용).
class RingGauge extends StatelessWidget {
  const RingGauge({super.key, required this.value, required this.label, required this.center, required this.status});
  final double value; // 0~1
  final String label;
  final String center;
  final Status status;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = value.clamp(0.0, 1.0);
    return Semantics(
      label: '$label $center',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: v),
              duration: t.normal,
              curve: Curves.easeOutCubic,
              builder: (_, x, _) => CustomPaint(
                painter: _RingPainter(x, t.statusColor(status), t.tonal),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: FittedBox(
                      child: Text(
                        center,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: t.text),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.gapS),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, color: t.text),
          ),
          const SizedBox(height: AppTokens.gapXs),
          StatusBadge(status, _statusWord(status)),
        ],
      ),
    );
  }

  static String _statusWord(Status s) => switch (s) {
    Status.done => S.uiOk,
    Status.progress => S.uiProgress,
    Status.check => S.uiLow,
    Status.problem => S.uiEmptyGauge,
  };
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color, this.track);
  final double v;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 9;
    final bg = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16;
    canvas.drawCircle(c, r, bg);
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 16;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * v, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color;
}

enum MascotMood { hello, working, done, warning, celebrate }

/// 앱 전용 비서 마스코트. assets/icons3d/mascot_<표정>.png 를 쓰고, 없으면 직접 그린다.
class Mascot extends StatelessWidget {
  const Mascot(this.mood, {super.key, this.size = 96});
  final MascotMood mood;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image.asset(
      'assets/icons3d/mascot_${mood.name}.png',
      width: size,
      height: size,
      errorBuilder: (_, _, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: MascotPainter(mood)),
      ),
    ),
  );
}

/// 마스코트 그림 (그라데이션·하이라이트·그림자로 입체감).
class MascotPainter extends CustomPainter {
  MascotPainter(this.mood);
  final MascotMood mood;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final body = mood == MascotMood.warning ? const Color(0xFFF59E0B) : const Color(0xFF4F63D9);
    // 바닥 그림자
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * .5, h * .93), width: w * .62, height: h * .09),
      Paint()..color = const Color(0x33000000),
    );
    // 안테나
    canvas.drawLine(
      Offset(w * .5, h * .2),
      Offset(w * .5, h * .08),
      Paint()
        ..color = AppTokens.darker(body, .1)
        ..strokeWidth = w * .035
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(w * .5, h * .075),
      w * .055,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFFFFE08A), Color(0xFFF97316)])
            .createShader(Rect.fromCircle(center: Offset(w * .48, h * .06), radius: w * .06)),
    );
    // 머리 (입체 그라데이션)
    final head = RRect.fromRectAndRadius(Rect.fromLTWH(w * .14, h * .18, w * .72, h * .66), Radius.circular(w * .26));
    canvas.drawRRect(
      head,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.35, -.5),
          radius: 1.1,
          colors: [Color.lerp(body, Colors.white, .45)!, body, AppTokens.darker(body, .18)],
          stops: const [0, .55, 1],
        ).createShader(head.outerRect),
    );
    // 헤드셋
    final hs = Paint()
      ..color = const Color(0xFF263238)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .045
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromLTWH(w * .1, h * .12, w * .8, h * .62), math.pi * 1.05, math.pi * .9, false, hs);
    for (final x in [w * .11, w * .89]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, h * .48), width: w * .12, height: h * .2),
          Radius.circular(w * .05),
        ),
        Paint()..color = const Color(0xFF37474F),
      );
    }
    canvas.drawLine(
      Offset(w * .89, h * .56),
      Offset(w * .66, h * .74),
      Paint()
        ..color = const Color(0xFF37474F)
        ..strokeWidth = w * .03
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(w * .64, h * .75), w * .035, Paint()..color = const Color(0xFF263238));
    // 얼굴 화면
    final face = RRect.fromRectAndRadius(Rect.fromLTWH(w * .25, h * .32, w * .5, h * .36), Radius.circular(w * .16));
    canvas.drawRRect(face, Paint()..color = const Color(0xFF1E2140));
    // 하이라이트
    canvas.drawOval(Rect.fromLTWH(w * .24, h * .2, w * .26, h * .1), Paint()..color = const Color(0x55FFFFFF));
    final eye = Paint()
      ..color = const Color(0xFF7DF9FF)
      ..strokeWidth = w * .04
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final ly = Offset(w * .4, h * .47), ry = Offset(w * .6, h * .47);
    switch (mood) {
      case MascotMood.hello:
      case MascotMood.celebrate:
        // 웃는 눈 ^^
        for (final c in [ly, ry]) {
          canvas.drawArc(Rect.fromCenter(center: c, width: w * .1, height: h * .08), math.pi, math.pi, false, eye);
        }
      case MascotMood.working:
        for (final c in [ly, ry]) {
          canvas.drawLine(c.translate(-w * .035, 0), c.translate(w * .035, 0), eye);
        }
      case MascotMood.done:
        for (final c in [ly, ry]) {
          canvas.drawCircle(c, w * .028, Paint()..color = const Color(0xFF7DF9FF));
        }
      case MascotMood.warning:
        for (final c in [ly, ry]) {
          canvas.drawCircle(c, w * .03, Paint()..color = const Color(0xFFFFE082));
        }
        canvas.drawLine(ly.translate(-w * .05, -h * .05), ly.translate(w * .03, -h * .085), eye);
        canvas.drawLine(ry.translate(w * .05, -h * .05), ry.translate(-w * .03, -h * .085), eye);
    }
    // 입
    final mouth = Paint()
      ..color = mood == MascotMood.warning ? const Color(0xFFFFE082) : const Color(0xFF7DF9FF)
      ..strokeWidth = w * .03
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final m = Rect.fromCenter(center: Offset(w * .5, h * .56), width: w * .16, height: h * .08);
    if (mood == MascotMood.warning) {
      canvas.drawLine(m.centerLeft.translate(0, h * .02), m.centerRight.translate(0, h * .02), mouth);
    } else if (mood == MascotMood.working) {
      canvas.drawCircle(m.center.translate(0, h * .01), w * .02, mouth);
    } else {
      canvas.drawArc(m, 0, math.pi, false, mouth);
    }
    // 표정별 소품
    if (mood == MascotMood.hello) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(w * .9, h * .26), width: w * .14, height: h * .18),
        Paint()..color = Color.lerp(body, Colors.white, .3)!,
      );
    } else if (mood == MascotMood.celebrate) {
      final rnd = math.Random(3);
      const colors = [Color(0xFFF43F5E), Color(0xFFFACC15), Color(0xFF22C55E), Color(0xFF38BDF8)];
      for (var i = 0; i < 14; i++) {
        canvas.drawCircle(
          Offset(rnd.nextDouble() * w, rnd.nextDouble() * h * .35),
          w * .022,
          Paint()..color = colors[i % colors.length],
        );
      }
    } else if (mood == MascotMood.done) {
      final c = Offset(w * .84, h * .78);
      canvas.drawCircle(c, w * .1, Paint()..color = const Color(0xFF15803D));
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - w * .045, c.dy)
          ..lineTo(c.dx - w * .01, c.dy + h * .035)
          ..lineTo(c.dx + w * .05, c.dy - h * .035),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .028
          ..strokeCap = StrokeCap.round,
      );
    } else if (mood == MascotMood.working) {
      canvas.drawCircle(
        Offset(w * .86, h * .8),
        w * .08,
        Paint()
          ..color = const Color(0xFF1D4ED8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .03,
      );
    }
  }

  @override
  bool shouldRepaint(MascotPainter o) => o.mood != mood;
}

/// 목록 항목이 순서대로 살짝 올라오며 나타나는 효과 (한 번만, 움직임 줄이기면 바로 표시).
class Appear extends StatelessWidget {
  const Appear({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // 처음 몇 개만 움직인다 (긴 목록은 바로 그려서 가볍게).
    if (t.reduceMotion || index > 5) return child;
    final i = index;
    final total = t.normal + t.stagger * i;
    final start = i == 0 ? 0.0 : (t.stagger * i).inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: c),
      ),
      child: child,
    );
  }
}

/// 새 알림·확인 대기에 쓰는 작은 흔들림 (한 번만).
class ShakeOnce extends StatelessWidget {
  const ShakeOnce({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (t.reduceMotion) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: t.slow,
      builder: (_, v, c) => Transform.rotate(angle: math.sin(v * math.pi * 6) * (1 - v) * 0.12, child: c),
      child: child,
    );
  }
}

/// 빈 화면: "아직 없어요 — 이렇게 시작하세요" + 큰 시작 버튼.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon = 'sparkles',
    this.actionLabel,
    this.onAction,
    this.actionKey,
  });
  final String message;
  final String icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.gapXl, horizontal: AppTokens.gapL),
      child: Column(
        children: [
          Icon3D(icon, size: AppTokens.icon3dL + 24),
          const SizedBox(height: AppTokens.gapM),
          Text(
            S.uiEmptyTitle,
            style: TextStyle(fontSize: AppTokens.fontSection, fontWeight: FontWeight.w800, color: t.text),
          ),
          const SizedBox(height: AppTokens.gapS),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppTokens.fontBody, color: t.textSoft),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppTokens.gapL),
            Press3D(
              key: actionKey,
              color: t.accent,
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.gapXl, vertical: AppTokens.gapL),
                child: Text(
                  actionLabel!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.onAccent, fontSize: AppTokens.fontButton, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 처음 쓰는 기능 말풍선 안내 (한 번만 보임, 설정에서 다시 보기 가능).
class TipBanner extends StatefulWidget {
  const TipBanner({super.key, required this.text, required this.seen, required this.onSeen});
  final String text;
  final bool seen;
  final VoidCallback onSeen;

  @override
  State<TipBanner> createState() => _TipBannerState();
}

class _TipBannerState extends State<TipBanner> {
  late bool hidden = widget.seen;

  @override
  Widget build(BuildContext context) {
    if (hidden) return const SizedBox.shrink();
    final t = context.tokens;
    return Appear(
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTokens.gapL),
        padding: const EdgeInsets.all(AppTokens.gapL),
        decoration: BoxDecoration(
          color: t.tileBg(Hue.slate),
          borderRadius: BorderRadius.circular(AppTokens.radius),
          border: t.highContrast ? Border.all(color: t.border, width: 2) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon3D('idea', size: AppTokens.icon3dS),
                const SizedBox(width: AppTokens.gapS),
                Expanded(
                  child: Text(
                    widget.text,
                    style: TextStyle(color: t.onTile(Hue.slate), fontSize: AppTokens.fontBody),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.gapS),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: t.onTile(Hue.slate),
                  foregroundColor: t.tileBg(Hue.slate),
                ),
                onPressed: () {
                  widget.onSeen();
                  setState(() => hidden = true);
                },
                child: const Text(S.uiTipOk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 완료 알림: 마스코트 축하 + 움직이는 체크 (화면을 막지 않는 아래쪽 알림).
void celebrate(BuildContext callerContext, String message, {SnackBarAction? action}) {
  final context = alive(callerContext);
  if (context == null) return;
  final t = context.tokens;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        backgroundColor: t.success,
        action: action,
        content: Row(
          children: [
            const Mascot(MascotMood.celebrate, size: 48),
            const SizedBox(width: AppTokens.gapS),
            _AnimatedCheck(color: t.onStatusFor(Status.done), reduce: t.reduceMotion),
            const SizedBox(width: AppTokens.gapS),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: t.onStatusFor(Status.done),
                  fontSize: AppTokens.fontBody,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}

class _AnimatedCheck extends StatelessWidget {
  const _AnimatedCheck({required this.color, required this.reduce});
  final Color color;
  final bool reduce;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: reduce ? 1 : 0, end: 1),
    duration: reduce ? Duration.zero : const Duration(milliseconds: 450),
    curve: Curves.easeOutBack,
    builder: (_, v, _) => Transform.scale(
      scale: v,
      child: Icon(Icons.check_circle, color: color, size: 30),
    ),
  );
}

/// 하위 화면 위쪽 막대: 같은 자리에 "뒤로"(왼쪽)·"처음 화면"(오른쪽) 버튼, 큰 제목.
PreferredSizeWidget pageBar(BuildContext context, String title, {List<Widget> actions = const []}) => AppBar(
  title: Text(title),
  actions: [
    ...actions,
    IconButton(
      key: const Key('go-home'),
      tooltip: S.uiHome,
      icon: const Icon(Icons.home_rounded),
      onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
    ),
    const SizedBox(width: AppTokens.gapS),
  ],
);

/// 숫자·정보 표시용 옅은 칩 (상태 색이 아님).
class InfoChip extends StatelessWidget {
  const InfoChip(this.icon, this.label, {super.key});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.gapS + 2, vertical: AppTokens.gapXs),
      decoration: BoxDecoration(
        color: t.tonal,
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        border: t.highContrast ? Border.all(color: t.border, width: 2) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: t.onTonal),
          const SizedBox(width: AppTokens.gapXs),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: t.onTonal, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// 목록 한 줄 카드: 3D 아이콘 + 제목 + 설명 (+ 배지) + 오른쪽 화살표 또는 버튼.
class ListCard extends StatelessWidget {
  const ListCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.badge,
    this.onTap,
    this.trailing,
    this.status,
  });
  final String icon;
  final String title;
  final String? subtitle;
  final Widget? badge;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Status? status;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return StripeCard(
      status: status,
      onTap: onTap,
      child: Row(
        children: [
          Icon3D(icon, size: AppTokens.icon3dS + 8),
          const SizedBox(width: AppTokens.gapM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: AppTokens.fontBody),
                ),
                if (subtitle != null) Text(subtitle!, style: TextStyle(color: t.textSoft)),
                if (badge != null) ...[const SizedBox(height: AppTokens.gapXs), badge!],
              ],
            ),
          ),
          trailing ??
              (onTap != null ? Icon(Icons.chevron_right, color: t.textSoft, size: AppTokens.iconM) : const SizedBox()),
        ],
      ),
    );
  }
}

/// 여러 개 중 하나 고르기: 화면이 좁거나 글씨가 커도 줄바꿈되는 큰 버튼들. 고른 것은 주요색 + 체크.
class ChoiceWrap<T> extends StatelessWidget {
  const ChoiceWrap({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Wrap(
      spacing: AppTokens.gapS,
      runSpacing: AppTokens.gapS,
      children: [
        for (final (v, label) in options)
          Press3D(
            key: ValueKey('choice-$v'),
            color: v == value ? t.primary : t.tonal,
            depth: 3,
            semanticLabel: label,
            onTap: () => onChanged(v),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTokens.buttonHeight - 4, minWidth: 88),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.gapL, vertical: AppTokens.gapS),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (v == value) ...[Icon(Icons.check, color: t.onPrimary), const SizedBox(width: AppTokens.gapXs)],
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: v == value ? t.onPrimary : t.onTonal,
                          fontWeight: FontWeight.w800,
                          fontSize: AppTokens.fontButton,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 채운 카드: 바탕보다 한 단계 밝은 색 + 부드러운 그림자. 테두리는 쓰지 않음 (선택·상태 표시에만).
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTokens.gapL + 4),
    this.color,
    this.onTap,
    this.border,
    this.margin = const EdgeInsets.only(bottom: AppTokens.cardGap),
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;
  final BorderSide? border;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = border ?? (t.highContrast ? BorderSide(color: t.border, width: 2) : BorderSide.none);
    return Container(
      margin: margin,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppTokens.radiusCard), boxShadow: t.soft()),
      child: Material(
        color: color ?? t.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusCard), side: side),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  UiPrefs.tap();
                  onTap!();
                },
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// 영역 색 타일 (홈의 중간 크기, 2열): 큰 3D 아이콘 + 이름 + 큰 숫자(있으면) + 설명/배지.
class HueTile extends StatelessWidget {
  const HueTile({
    super.key,
    required this.hue,
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
    this.caption,
    this.badge,
    this.fallback = Icons.apps,
    this.compact = false,
  });
  final Hue hue;
  final String icon;
  final String title;
  final VoidCallback onTap;

  /// 큰 숫자 (숫자 카드). 없으면 설명만.
  final String? value;
  final String? caption;
  final Widget? badge;
  final IconData fallback;

  /// 작은 타일 (한 줄 높이)
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = t.onTile(hue);
    final semantic = [title, ?value, ?caption].join('. ');
    final iconSize = compact ? AppTokens.icon3dS + 4 : AppTokens.icon3dL + 8;
    final body = compact
        ? Row(
            children: [
              Icon3D(icon, size: iconSize, fallback: fallback),
              const SizedBox(width: AppTokens.gapM),
              Expanded(child: _texts(fg)),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon3D(icon, size: iconSize, fallback: fallback),
              const SizedBox(height: AppTokens.gapM),
              _texts(fg),
            ],
          );
    return Press3D(
      color: t.tileBg(hue),
      onTap: onTap,
      radius: AppTokens.radiusCard,
      semanticLabel: semantic,
      child: Padding(padding: EdgeInsets.all(compact ? AppTokens.gapL : AppTokens.gapL + 4), child: body),
    );
  }

  Widget _texts(Color fg) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: compact ? AppTokens.fontBody + 2 : AppTokens.fontSection,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
      if (value != null)
        Text(
          value!,
          style: TextStyle(fontSize: AppTokens.fontHero, fontWeight: FontWeight.w900, color: fg, height: 1.15),
        ),
      if (caption != null)
        Text(
          caption!,
          style: TextStyle(fontSize: AppTokens.fontSmall, color: fg, fontWeight: FontWeight.w500),
        ),
      if (badge != null) ...[const SizedBox(height: AppTokens.gapS), badge!],
    ],
  );
}

/// 두 개를 나란히 (같은 높이). 화면이 좁거나 글씨가 아주 크면 위아래로.
class TwoUp extends StatelessWidget {
  const TwoUp({
    super.key,
    required this.children,
    this.gap = AppTokens.gapL,
    this.minWidth = 330,
    this.equalHeight = true,
  });

  /// 두 칸 높이 맞추기 (줄어드는 글자가 있는 칸에는 끄기)
  final bool equalHeight;
  final List<Widget> children;
  final double gap;

  /// 이 폭(글씨 배율로 나눈 값)보다 좁으면 위아래로
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    if (children.length == 1) return children.first;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, c) {
        final roomy = c.maxWidth / scale >= minWidth;
        if (!roomy) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
            ],
          );
        }
        final row = Row(
          crossAxisAlignment: equalHeight ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(child: children[i]),
            ],
          ],
        );
        return equalHeight ? IntrinsicHeight(child: row) : row;
      },
    );
  }
}

/// 작은 수치 띠의 한 칸: 이름 + 큰 숫자 + 얇은 막대.
class MeterCell extends StatelessWidget {
  const MeterCell({
    super.key,
    required this.label,
    required this.value,
    required this.of,
    required this.ratio,
    required this.status,
  });
  final String label;
  final String value;
  final String of;
  final double ratio;
  final Status status;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = ratio.clamp(0.0, 1.0);
    return Semantics(
      label: '$label $value $of',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: TextStyle(fontSize: AppTokens.fontSmall, color: t.textSoft, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: AppTokens.gapXs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: TextStyle(fontSize: AppTokens.fontHero, fontWeight: FontWeight.w900, color: t.text),
                    ),
                    TextSpan(
                      text: ' $of',
                      style: TextStyle(fontSize: AppTokens.fontSmall, color: t.textSoft, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTokens.gapS),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: r),
              duration: t.normal,
              curve: Curves.easeOutCubic,
              builder: (_, x, _) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: x,
                  minHeight: 10,
                  color: t.statusColor(status),
                  backgroundColor: t.tonal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 앱 아이콘 그림: 색 바탕 + 흰 원 + 마스코트, 또는 사용자가 고른 그림.
class AppIconView extends StatelessWidget {
  const AppIconView({super.key, required this.look, this.size = 72, this.iconId});
  final AppLook look;
  final double size;

  /// 미리보기용 (지정하면 이 아이콘으로 그림)
  final String? iconId;

  @override
  Widget build(BuildContext context) {
    final id = iconId ?? look.iconId;
    final radius = BorderRadius.circular(size * 0.24);
    if (id == 'custom' && look.hasCustomIcon) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.file(
          File(look.customIconPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => AppIconView(look: look, size: size, iconId: 'blue'),
        ),
      );
    }
    final color = Color(AppLook.iconColors[id] ?? AppLook.iconColors['blue']!);
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: AppIconPainter(color)),
      ),
    );
  }
}

/// 아이콘 그리기 (화면·PNG 파일 공용).
class AppIconPainter extends CustomPainter {
  AppIconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final r = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.width * 0.24));
    canvas.drawRRect(r, Paint()..color = color);
    canvas.drawCircle(Offset(s.width / 2, s.height / 2), s.width * 0.38, Paint()..color = const Color(0xFFFFFFFF));
    canvas.save();
    canvas.translate(s.width * 0.17, s.height * 0.15);
    MascotPainter(MascotMood.hello).paint(canvas, Size(s.width * 0.66, s.height * 0.66));
    canvas.restore();
  }

  @override
  bool shouldRepaint(AppIconPainter old) => old.color != color;
}

/// 아이콘을 PNG 로 (안드로이드 바로가기, 컴퓨터 바로가기용 아이콘 파일).
Future<Uint8List> renderAppIconPng(AppLook look, {int size = 256}) async {
  if (look.iconId == 'custom' && look.hasCustomIcon) return File(look.customIconPath).readAsBytesSync();
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  AppIconPainter(Color(look.iconColor)).paint(canvas, Size(size.toDouble(), size.toDouble()));
  final img = await rec.endRecording().toImage(size, size);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
