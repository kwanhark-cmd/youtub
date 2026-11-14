import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'module_api.dart';
import 'settings.dart';

/// 두 색의 명암비 (WCAG 2). 7 이상이면 가장 엄격한 AAA 기준.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// [color] 를 [against] 의 모든 색과 명암비 [ratio] 이상이 될 때까지 어둡게(맞댄 색이 밝으면) 또는 밝게 한다.
/// 이미 충분하면 그대로 돌려준다.
Color ensureContrast(Color color, List<Color> against, {double ratio = AssistantTheme.minContrast}) {
  final towards = against.first.computeLuminance() > 0.18 ? Colors.black : Colors.white;
  var c = color;
  for (var i = 1; i <= 100 && against.any((b) => contrastRatio(c, b) < ratio); i++) {
    c = Color.lerp(color, towards, i / 100)!;
  }
  return c;
}

/// 글자 위계 4단계 + 간격 1.5배. 모든 화면이 이 값을 쓴다.
///
/// 잘 보이게 하는 규칙 (모든 테마·글씨 크기 공통, test/theme_test.dart 가 지킨다):
/// - 단추 높이 52 이상, 단추 글자 17 굵게, 누르는 자리 48 이상
/// - 채운 단추 글자/바탕 명암비 7 이상 (눌렀을 때도), 테두리 단추는 2px 진한 테두리
/// - 본문 16 이상, 중요한 글은 흐린 회색 대신 명암비 7 이상
/// - 지우기 같은 되돌릴 수 없는 일은 [danger] (분명한 빨강)
/// - 눌렀을 때·초점이 갔을 때 바탕색·테두리가 눈에 띄게 바뀐다
class AssistantTheme {
  static const double gap = 12 * 1.5;
  static const double radius = 22;

  static const double buttonHeight = 52;
  static const double minTouch = 48;
  static const double labelSize = 17;
  static const double minBodySize = 16;
  static const double minContrast = 7;
  static const double outlineWidth = 2;
  static const double focusWidth = 3;

  /// 눌렀을 때 덮는 색의 진하기
  static const double pressedAlpha = 0.32;
  static const double pressedTintAlpha = 0.14;

  static const TextStyle labelStyle = TextStyle(fontSize: labelSize, fontWeight: FontWeight.w700, height: 1.25);

  /// 화면 바탕으로 쓰는 색 (스캐폴드)
  static Color scaffoldColor(ColorScheme s, {required bool highContrast}) =>
      highContrast ? s.surface : (s.brightness == Brightness.dark ? const Color(0xFF121318) : const Color(0xFFF4F5F9));

  /// 글자가 올라가는 모든 바탕색
  static List<Color> grounds(ColorScheme s, {required bool highContrast}) => [
        scaffoldColor(s, highContrast: highContrast),
        s.surface,
        s.surfaceContainerLowest,
        s.surfaceContainerLow,
        s.surfaceContainer,
        s.surfaceContainerHigh,
        s.surfaceContainerHighest,
      ];

  /// 잘 보이도록 고친 색 묶음
  static ColorScheme scheme({required Brightness brightness, bool highContrast = false, Color seed = const Color(0xFF3D5AFE)}) {
    final dark = brightness == Brightness.dark;
    var s = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    // 밝은 테마의 기본 파랑은 검게 섞으면 잿빛이 되므로, 처음부터 짙고 선명한 남색에서 시작한다.
    if (!dark) s = s.copyWith(primary: const Color(0xFF2236A8), onPrimary: Colors.white);
    if (highContrast) {
      s = s.copyWith(
        surface: dark ? Colors.black : Colors.white,
        onSurface: dark ? Colors.white : Colors.black,
        onSurfaceVariant: dark ? Colors.white : Colors.black,
        outline: dark ? Colors.white : Colors.black,
        primary: dark ? const Color(0xFFFFEB3B) : const Color(0xFF0019A8),
        onPrimary: dark ? Colors.black : Colors.white,
      );
    }
    final g = grounds(s, highContrast: highContrast);
    // 테두리·글자 단추는 바탕 위 primary 글자를 쓰고 눌렀을 때 살짝 물들므로 여유를 둔다 (8.5).
    final primary = ensureContrast(ensureContrast(s.primary, [s.onPrimary]), g, ratio: 9);
    final error = ensureContrast(ensureContrast(s.error, [s.onError]), g, ratio: 7.5);
    return s.copyWith(
      primary: primary,
      // 어두운 테마의 진한 글자를 더 진하게 해 두면, 눌렀을 때 바탕을 어둡게 해도 7:1 이 남는다.
      onPrimary: ensureContrast(s.onPrimary, [primary], ratio: 12),
      error: error,
      onSurface: ensureContrast(s.onSurface, g),
      onSurfaceVariant: ensureContrast(s.onSurfaceVariant, g),
      outline: ensureContrast(s.outline, g, ratio: 4.5),
      onPrimaryContainer: ensureContrast(s.onPrimaryContainer, [s.primaryContainer]),
      onSecondaryContainer: ensureContrast(s.onSecondaryContainer, [s.secondaryContainer]),
      onTertiaryContainer: ensureContrast(s.onTertiaryContainer, [s.tertiaryContainer]),
      onErrorContainer: ensureContrast(s.onErrorContainer, [s.errorContainer]),
    );
  }

  /// 채운 단추를 눌렀을 때 덮는 색. 검정·흰색(진하기 32·24·16%) 가운데 눌러도 글자/바탕 명암비가 7 이상으로 남고
  /// 바탕색이 가장 크게 바뀌는(눈에 잘 띄는) 것을 고른다. 하나도 없으면 글자에서 먼 쪽 (명암비가 오른다).
  static Color pressedOverlay(Color foreground, Color background) {
    Color? best;
    var bestVis = 0.0;
    for (final c in [Colors.black, Colors.white]) {
      for (final a in [pressedAlpha, 0.24, 0.16]) {
        final o = c.withValues(alpha: a);
        final down = Color.alphaBlend(o, background);
        if (contrastRatio(foreground, down) < minContrast) continue;
        final vis = contrastRatio(down, background);
        if (vis > bestVis) (best, bestVis) = (o, vis);
        break;
      }
    }
    return best ?? (foreground.computeLuminance() > 0.18 ? Colors.black : Colors.white).withValues(alpha: pressedAlpha);
  }

  /// 되돌릴 수 없는 일(지우기·삭제) 단추의 빨강. 모든 테마에서 같은 진한 빨강 + 흰 글자.
  static Color dangerColor(ColorScheme s) => ensureContrast(const Color(0xFFD32F2F), [Colors.white], ratio: 7.5);

  /// 테두리·글자 단추를 눌렀을 때 물들이는 진하기: 모든 바탕 위에서 글자 명암비 7 을 지키는 가장 진한 값.
  static double tintAlpha(Color tint, List<Color> grounds) {
    for (final a in [pressedTintAlpha, 0.12, 0.10]) {
      if (grounds.every((g) => contrastRatio(tint, Color.alphaBlend(tint.withValues(alpha: a), g)) >= minContrast)) return a;
    }
    return 0.08;
  }

  static WidgetStateProperty<Color?> _overlay({required Color pressed, required Color tint}) => WidgetStateProperty.resolveWith((st) {
        if (st.contains(WidgetState.pressed)) return pressed;
        if (st.contains(WidgetState.focused)) return tint.withValues(alpha: 0.10);
        if (st.contains(WidgetState.hovered)) return tint.withValues(alpha: 0.08);
        return null;
      });

  /// 채운 단추 모양 (바탕 [bg], 글자 [fg]). 테마의 채운 단추와 [danger] 가 같이 쓴다.
  static ButtonStyle filledStyle(ColorScheme s, {required Color bg, required Color fg}) => ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, buttonHeight)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
        textStyle: const WidgetStatePropertyAll(labelStyle),
        backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled) ? null : bg),
        foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled) ? null : fg),
        iconColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled) ? null : fg),
        overlayColor: _overlay(pressed: pressedOverlay(fg, bg), tint: fg),
        side: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.focused) ? BorderSide(color: s.onSurface, width: focusWidth) : null),
      );

  /// 되돌릴 수 없는 일(지우기·삭제)의 단추: 분명한 빨강 바탕 + 흰 글자.
  static ButtonStyle danger(ColorScheme s) => filledStyle(s, bg: dangerColor(s), fg: Colors.white);

  static ThemeData build({required Brightness brightness, bool highContrast = false, Color seed = const Color(0xFF3D5AFE)}) {
    final scheme = AssistantTheme.scheme(brightness: brightness, highContrast: highContrast, seed: seed);
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'NotoSansKR');
    final t = base.textTheme;
    final ink = scheme.onSurface;
    final tint = scheme.primary;
    final tintA = tintAlpha(tint, grounds(scheme, highContrast: highContrast));
    final textOverlay = _overlay(pressed: tint.withValues(alpha: tintA), tint: tint);
    BorderSide? focusSide(Set<WidgetState> st) => st.contains(WidgetState.focused) ? BorderSide(color: tint, width: focusWidth) : null;
    return base.copyWith(
      scaffoldBackgroundColor: scaffoldColor(scheme, highContrast: highContrast),
      textTheme: t.copyWith(
        // 1단계: 화면 제목 / 2단계: 카드 제목 / 3단계: 본문 / 4단계: 보조 글 (보조 글도 16 이상, 흐린 회색 금지)
        headlineSmall: t.headlineSmall?.copyWith(fontSize: 26, fontWeight: FontWeight.w700, height: 1.3, color: ink),
        titleMedium: t.titleMedium?.copyWith(fontSize: 19, fontWeight: FontWeight.w700, height: 1.35, color: ink),
        bodyLarge: t.bodyLarge?.copyWith(fontSize: 17, height: 1.5, color: ink),
        bodyMedium: t.bodyMedium?.copyWith(fontSize: minBodySize, height: 1.5, color: ink),
        bodySmall: t.bodySmall?.copyWith(fontSize: minBodySize, height: 1.45, color: ink),
        labelLarge: t.labelLarge?.copyWith(fontSize: labelSize, fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: highContrast ? BorderSide(color: scheme.onSurface, width: 2) : BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(style: filledStyle(scheme, bg: scheme.primary, fg: scheme.onPrimary)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: filledStyle(scheme, bg: scheme.primary, fg: scheme.onPrimary)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, buttonHeight)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
          textStyle: const WidgetStatePropertyAll(labelStyle),
          foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled) ? null : tint),
          iconColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled) ? null : tint),
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
          foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled) ? null : tint),
          iconColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled) ? null : tint),
          overlayColor: textOverlay,
          side: WidgetStateProperty.resolveWith(focusSide),
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(style: ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(minTouch, minTouch)))),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(minTouch, buttonHeight)),
          // 나뉜 단추는 minimumSize 를 쓰지 않아 위아래 여백으로 높이 52 를 만든다 (글자 줄 21 + 16 + 16).
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8, vertical: 16)),
          textStyle: const WidgetStatePropertyAll(labelStyle),
          backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) && !st.contains(WidgetState.disabled) ? scheme.primary : null),
          foregroundColor: WidgetStateProperty.resolveWith((st) {
            if (st.contains(WidgetState.disabled)) return null;
            return st.contains(WidgetState.selected) ? scheme.onPrimary : ink;
          }),
          iconColor: WidgetStateProperty.resolveWith((st) {
            if (st.contains(WidgetState.disabled)) return null;
            return st.contains(WidgetState.selected) ? scheme.onPrimary : ink;
          }),
          overlayColor: WidgetStateProperty.resolveWith((st) {
            final sel = st.contains(WidgetState.selected);
            if (st.contains(WidgetState.pressed)) return sel ? pressedOverlay(scheme.onPrimary, scheme.primary) : tint.withValues(alpha: tintA);
            if (st.contains(WidgetState.focused) || st.contains(WidgetState.hovered)) return (sel ? scheme.onPrimary : tint).withValues(alpha: 0.10);
            return null;
          }),
          side: WidgetStateProperty.resolveWith((st) => BorderSide(
                color: st.contains(WidgetState.disabled) ? ink.withValues(alpha: 0.38) : tint,
                width: st.contains(WidgetState.focused) ? focusWidth : outlineWidth,
              )),
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: TextStyle(fontSize: minBodySize, fontWeight: FontWeight.w700, color: ink),
        side: BorderSide(color: tint, width: outlineWidth),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: t.bodyLarge?.copyWith(fontSize: 17, height: 1.4, color: ink),
        subtitleTextStyle: t.bodyMedium?.copyWith(fontSize: minBodySize, height: 1.45, color: scheme.onSurfaceVariant),
        iconColor: scheme.onSurfaceVariant,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(),
    );
  }

  static ThemeMode mode(AppSettings s) => switch (s.themeMode) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };

  /// 모듈 색 면 위 글자색
  static Color onModule(ModuleId m) => Colors.white;
}
