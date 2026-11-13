import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 메타지우개 플러스의 잘 보이는 테마. 모든 화면이 이 한 곳의 값을 쓴다
/// (화면마다 따로 글자 크기·색을 정하지 않는다). test/theme_test.dart 가 규칙을 지킨다.
///
/// - 단추 높이 52 이상, 단추 글자 17 굵게, 누르는 자리 48 이상
/// - 채운 단추 글자/바탕 명암비 7:1 이상 (눌렀을 때도), 테두리 단추는 2px 진한 테두리
/// - 본문 16 이상, 흐린 회색 대신 바탕과 7:1 이상
/// - 지우기 같은 되돌릴 수 없는 일은 [MetaTheme.danger] (분명한 빨강)
/// - 눌렀을 때·초점이 갔을 때 바탕색·테두리가 눈에 띄게 바뀐다
class MetaTheme {
  static const double buttonHeight = 52;
  static const double minTouch = 48;
  static const double labelSize = 17;
  static const double minBodySize = 16;
  static const double minContrast = 7;
  static const double outlineWidth = 2;
  static const double focusWidth = 3;
  static const double pressedAlpha = 0.32;

  static const TextStyle labelStyle = TextStyle(fontSize: labelSize, fontWeight: FontWeight.w700, height: 1.25);

  /// 두 색의 명암비 (WCAG 2)
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// [color] 를 [against] 모두와 [ratio] 이상이 될 때까지 어둡게(맞댄 색이 밝으면) 또는 밝게 한다.
  static Color ensure(Color color, List<Color> against, {double ratio = minContrast}) {
    final towards = against.first.computeLuminance() > 0.18 ? Colors.black : Colors.white;
    var c = color;
    for (var i = 1; i <= 100 && against.any((b) => contrast(c, b) < ratio); i++) {
      c = Color.lerp(color, towards, i / 100)!;
    }
    return c;
  }

  /// 글자가 올라가는 바탕색들
  static List<Color> grounds(ColorScheme s) => [
        s.surface,
        s.surfaceContainerLowest,
        s.surfaceContainerLow,
        s.surfaceContainer,
        s.surfaceContainerHigh,
        s.surfaceContainerHighest,
      ];

  static ColorScheme scheme() {
    var s = ColorScheme.fromSeed(seedColor: const Color(0xFF2F6BFF))
        // 기본 파랑을 검게 섞으면 잿빛이 되므로 짙고 선명한 파랑에서 시작한다.
        .copyWith(primary: const Color(0xFF1546C8), onPrimary: Colors.white);
    final g = grounds(s);
    final primary = ensure(ensure(s.primary, [s.onPrimary]), g, ratio: 9);
    s = s.copyWith(
      primary: primary,
      error: ensure(s.error, [s.onError, ...g], ratio: 7.5),
      onSurface: ensure(s.onSurface, g),
      onSurfaceVariant: ensure(s.onSurfaceVariant, g),
      outline: ensure(s.outline, g, ratio: 4.5),
      onPrimaryContainer: ensure(s.onPrimaryContainer, [s.primaryContainer]),
      onSecondaryContainer: ensure(s.onSecondaryContainer, [s.secondaryContainer]),
      onTertiaryContainer: ensure(s.onTertiaryContainer, [s.tertiaryContainer]),
      onErrorContainer: ensure(s.onErrorContainer, [s.errorContainer]),
    );
    return s;
  }

  /// 채운 단추를 눌렀을 때 덮는 색: 눌러도 7:1 이 남으면서 바탕이 가장 크게 바뀌는 검정·흰색.
  static Color pressedOverlay(Color fg, Color bg) {
    Color? best;
    var bestVis = 0.0;
    for (final c in [Colors.black, Colors.white]) {
      for (final a in [pressedAlpha, 0.24, 0.16]) {
        final o = c.withValues(alpha: a);
        final down = Color.alphaBlend(o, bg);
        if (contrast(fg, down) < minContrast) continue;
        final vis = contrast(down, bg);
        if (vis > bestVis) (best, bestVis) = (o, vis);
        break;
      }
    }
    return best ?? (fg.computeLuminance() > 0.18 ? Colors.black : Colors.white).withValues(alpha: pressedAlpha);
  }

  /// 테두리·글자 단추를 눌렀을 때 물들이는 진하기 (모든 바탕 위에서 글자 7:1 유지)
  static double tintAlpha(Color tint, List<Color> grounds) {
    for (final a in [0.14, 0.12, 0.10]) {
      if (grounds.every((g) => contrast(tint, Color.alphaBlend(tint.withValues(alpha: a), g)) >= minContrast)) return a;
    }
    return 0.08;
  }

  static WidgetStateProperty<Color?> _overlay(Color pressed, Color tint) => WidgetStateProperty.resolveWith((st) {
        if (st.contains(WidgetState.pressed)) return pressed;
        if (st.contains(WidgetState.focused)) return tint.withValues(alpha: 0.10);
        if (st.contains(WidgetState.hovered)) return tint.withValues(alpha: 0.08);
        return null;
      });

  static ButtonStyle filledStyle(ColorScheme s, {required Color bg, required Color fg}) => ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, buttonHeight)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
        textStyle: const WidgetStatePropertyAll(labelStyle),
        backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled) ? null : bg),
        foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled) ? null : fg),
        iconColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled) ? null : fg),
        overlayColor: _overlay(pressedOverlay(fg, bg), fg),
        side: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.focused) ? BorderSide(color: s.onSurface, width: focusWidth) : null),
      );

  /// 되돌릴 수 없는 일(지우기·삭제) 단추의 빨강 + 흰 글자
  static Color dangerColor() => ensure(const Color(0xFFD32F2F), [Colors.white], ratio: 7.5);
  static ButtonStyle danger(ColorScheme s) => filledStyle(s, bg: dangerColor(), fg: Colors.white);

  static ThemeData build() {
    final s = scheme();
    final base = ThemeData(useMaterial3: true, colorScheme: s);
    final t = base.textTheme;
    final ink = s.onSurface;
    final tint = s.primary;
    final tintA = tintAlpha(tint, grounds(s));
    final textOverlay = _overlay(tint.withValues(alpha: tintA), tint);
    WidgetStateProperty<Color?> only(Color c) =>
        WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled) ? null : c);
    return base.copyWith(
      textTheme: t.copyWith(
        bodyLarge: t.bodyLarge?.copyWith(fontSize: 17, height: 1.5, color: ink),
        bodyMedium: t.bodyMedium?.copyWith(fontSize: minBodySize, height: 1.5, color: ink),
        bodySmall: t.bodySmall?.copyWith(fontSize: minBodySize, height: 1.45, color: ink),
        titleMedium: t.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w700, color: ink),
        labelLarge: t.labelLarge?.copyWith(fontSize: labelSize, fontWeight: FontWeight.w700),
      ),
      filledButtonTheme: FilledButtonThemeData(style: filledStyle(s, bg: s.primary, fg: s.onPrimary)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: filledStyle(s, bg: s.primary, fg: s.onPrimary)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, buttonHeight)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
          textStyle: const WidgetStatePropertyAll(labelStyle),
          foregroundColor: only(tint),
          iconColor: only(tint),
          overlayColor: textOverlay,
          side: WidgetStateProperty.resolveWith((st) {
            if (st.contains(WidgetState.disabled)) return BorderSide(color: ink.withValues(alpha: 0.38), width: outlineWidth);
            return BorderSide(color: tint, width: st.contains(WidgetState.focused) ? focusWidth : outlineWidth);
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(minTouch, buttonHeight)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
          textStyle: const WidgetStatePropertyAll(labelStyle),
          foregroundColor: only(tint),
          iconColor: only(tint),
          overlayColor: textOverlay,
          side: WidgetStateProperty.resolveWith(
              (st) => st.contains(WidgetState.focused) ? BorderSide(color: tint, width: focusWidth) : null),
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(style: ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(minTouch, minTouch)))),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          // 나뉜 단추는 minimumSize 를 쓰지 않아 위아래 여백으로 높이 52 를 만든다 (글자 줄 21 + 16 + 16).
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6, vertical: 16)),
          textStyle: const WidgetStatePropertyAll(labelStyle),
          backgroundColor: WidgetStateProperty.resolveWith(
              (st) => st.contains(WidgetState.selected) && !st.contains(WidgetState.disabled) ? s.primary : null),
          foregroundColor: WidgetStateProperty.resolveWith((st) {
            if (st.contains(WidgetState.disabled)) return null;
            return st.contains(WidgetState.selected) ? s.onPrimary : ink;
          }),
          iconColor: WidgetStateProperty.resolveWith((st) {
            if (st.contains(WidgetState.disabled)) return null;
            return st.contains(WidgetState.selected) ? s.onPrimary : ink;
          }),
          overlayColor: WidgetStateProperty.resolveWith((st) {
            final sel = st.contains(WidgetState.selected);
            if (st.contains(WidgetState.pressed)) return sel ? pressedOverlay(s.onPrimary, s.primary) : tint.withValues(alpha: tintA);
            if (st.contains(WidgetState.focused) || st.contains(WidgetState.hovered)) {
              return (sel ? s.onPrimary : tint).withValues(alpha: 0.10);
            }
            return null;
          }),
          side: WidgetStateProperty.resolveWith((st) => BorderSide(
                color: st.contains(WidgetState.disabled) ? ink.withValues(alpha: 0.38) : tint,
                width: st.contains(WidgetState.focused) ? focusWidth : outlineWidth,
              )),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: tint,
        unselectedLabelColor: ink,
        indicatorColor: tint,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: UnderlineTabIndicator(borderSide: BorderSide(color: tint, width: 4)),
        dividerColor: s.outline,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        overlayColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.pressed) ? tint.withValues(alpha: tintA) : null),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: t.bodyLarge?.copyWith(fontSize: 17, height: 1.4, color: ink),
        subtitleTextStyle: t.bodyMedium?.copyWith(fontSize: minBodySize, height: 1.45, color: s.onSurfaceVariant),
        iconColor: s.onSurfaceVariant,
      ),
      checkboxTheme: CheckboxThemeData(side: BorderSide(color: ink, width: outlineWidth)),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: TextStyle(fontSize: minBodySize, color: s.onSurfaceVariant),
        hintStyle: TextStyle(fontSize: minBodySize, color: s.onSurfaceVariant),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: s.outline, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: tint, width: focusWidth)),
      ),
    );
  }
}
