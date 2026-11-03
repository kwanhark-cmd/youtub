import 'package:flutter/material.dart';

import 'module_api.dart';
import 'settings.dart';

/// 글자 위계 4단계 + 간격 1.5배. 모든 화면이 이 값을 쓴다.
class AssistantTheme {
  static const double gap = 12 * 1.5;
  static const double radius = 22;

  static ThemeData build({required Brightness brightness, bool highContrast = false, Color seed = const Color(0xFF3D5AFE)}) {
    final dark = brightness == Brightness.dark;
    var scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    if (highContrast) {
      scheme = scheme.copyWith(
        surface: dark ? Colors.black : Colors.white,
        onSurface: dark ? Colors.white : Colors.black,
        primary: dark ? const Color(0xFFFFEB3B) : const Color(0xFF0019A8),
        onPrimary: dark ? Colors.black : Colors.white,
      );
    }
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'NotoSansKR');
    final t = base.textTheme;
    return base.copyWith(
      scaffoldBackgroundColor: highContrast ? scheme.surface : (dark ? const Color(0xFF121318) : const Color(0xFFF4F5F9)),
      textTheme: t.copyWith(
        // 1단계: 화면 제목 / 2단계: 카드 제목 / 3단계: 본문 / 4단계: 보조 글
        headlineSmall: t.headlineSmall?.copyWith(fontSize: 26, fontWeight: FontWeight.w700, height: 1.3),
        titleMedium: t.titleMedium?.copyWith(fontSize: 19, fontWeight: FontWeight.w700, height: 1.35),
        bodyLarge: t.bodyLarge?.copyWith(fontSize: 17, height: 1.5),
        bodySmall: t.bodySmall?.copyWith(fontSize: 14, height: 1.45, color: highContrast ? scheme.onSurface : null),
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
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 52), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(),
    );
  }

  static ThemeMode mode(AppSettings s) => switch (s.themeMode) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };

  /// 모듈 색 면 위 글자색
  static Color onModule(ModuleId m) => Colors.white;
}
