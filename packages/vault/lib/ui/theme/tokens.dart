import 'package:flutter/material.dart';

/// 화면 디자인 값은 모두 이 파일 하나에만 있다. 다른 화면은 여기 값만 쓴다.
///
/// 색 규칙: 주요색 1, 강조색 1, 상태색 4
///   초록 = 안전·정상, 파랑 = 진행 중, 노랑 = 만료 임박·확인 필요, 빨강 = 만료·위험
/// 같은 뜻은 어디서나 같은 색 + 아이콘 + 글자를 함께 쓴다.

enum StatusKind { safe, progress, caution, danger }

class AppPalette {
  const AppPalette({
    required this.name,
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.safe,
    required this.progress,
    required this.caution,
    required this.danger,
    required this.safeFill,
    required this.progressFill,
    required this.cautionFill,
    required this.dangerFill,
    required this.onSafeFill,
    required this.onProgressFill,
    required this.onCautionFill,
    required this.onDangerFill,
    required this.shadow,
    required this.tileTop,
    required this.tileBottom,
  });

  final String name;
  final Brightness brightness;
  final Color background, surface, surfaceAlt, text, textMuted, border;
  final Color primary, onPrimary, accent, onAccent;

  /// 상태색(바탕 위의 글자·아이콘·테두리용)
  final Color safe, progress, caution, danger;

  /// 상태색 채움(버튼·배지 바탕) + 그 위 글자색
  final Color safeFill, progressFill, cautionFill, dangerFill;
  final Color onSafeFill, onProgressFill, onCautionFill, onDangerFill;
  final Color shadow, tileTop, tileBottom;

  Color status(StatusKind k) => switch (k) {
    StatusKind.safe => safe,
    StatusKind.progress => progress,
    StatusKind.caution => caution,
    StatusKind.danger => danger,
  };

  Color statusFill(StatusKind k) => switch (k) {
    StatusKind.safe => safeFill,
    StatusKind.progress => progressFill,
    StatusKind.caution => cautionFill,
    StatusKind.danger => dangerFill,
  };

  Color onStatusFill(StatusKind k) => switch (k) {
    StatusKind.safe => onSafeFill,
    StatusKind.progress => onProgressFill,
    StatusKind.caution => onCautionFill,
    StatusKind.danger => onDangerFill,
  };

  static const light = AppPalette(
    name: 'light',
    brightness: Brightness.light,
    background: Color(0xFFF3F5FB),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE8ECF7),
    text: Color(0xFF111827),
    textMuted: Color(0xFF4B5563),
    border: Color(0xFFCBD2E1),
    primary: Color(0xFF4338CA),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFF0F766E),
    onAccent: Color(0xFFFFFFFF),
    safe: Color(0xFF15803D),
    progress: Color(0xFF1D4ED8),
    caution: Color(0xFF8A5A00),
    danger: Color(0xFFB91C1C),
    safeFill: Color(0xFF15803D),
    progressFill: Color(0xFF1D4ED8),
    cautionFill: Color(0xFFFACC15),
    dangerFill: Color(0xFFB91C1C),
    onSafeFill: Color(0xFFFFFFFF),
    onProgressFill: Color(0xFFFFFFFF),
    onCautionFill: Color(0xFF1F2937),
    onDangerFill: Color(0xFFFFFFFF),
    shadow: Color(0x33303A66),
    tileTop: Color(0xFFFFFFFF),
    tileBottom: Color(0xFFE6EAF8),
  );

  static const dark = AppPalette(
    name: 'dark',
    brightness: Brightness.dark,
    background: Color(0xFF0F172A),
    surface: Color(0xFF1E293B),
    surfaceAlt: Color(0xFF273449),
    text: Color(0xFFF1F5F9),
    textMuted: Color(0xFFCBD5E1),
    border: Color(0xFF475569),
    primary: Color(0xFFA5B4FC),
    onPrimary: Color(0xFF1E1B4B),
    accent: Color(0xFF5EEAD4),
    onAccent: Color(0xFF042F2E),
    safe: Color(0xFF4ADE80),
    progress: Color(0xFF7DB4FF),
    caution: Color(0xFFFACC15),
    danger: Color(0xFFFCA5A5),
    safeFill: Color(0xFF4ADE80),
    progressFill: Color(0xFF7DB4FF),
    cautionFill: Color(0xFFFACC15),
    dangerFill: Color(0xFFF87171),
    onSafeFill: Color(0xFF052E16),
    onProgressFill: Color(0xFF0B1B3A),
    onCautionFill: Color(0xFF1F1300),
    onDangerFill: Color(0xFF2B0505),
    shadow: Color(0x88000000),
    tileTop: Color(0xFF2A3A55),
    tileBottom: Color(0xFF1B2638),
  );

  static const contrast = AppPalette(
    name: 'contrast',
    brightness: Brightness.dark,
    background: Color(0xFF000000),
    surface: Color(0xFF0A0A0A),
    surfaceAlt: Color(0xFF1A1A1A),
    text: Color(0xFFFFFFFF),
    textMuted: Color(0xFFF0F0F0),
    border: Color(0xFFFFFFFF),
    primary: Color(0xFFFFFF00),
    onPrimary: Color(0xFF000000),
    accent: Color(0xFF00FFFF),
    onAccent: Color(0xFF000000),
    safe: Color(0xFF00FF7F),
    progress: Color(0xFF8CC8FF),
    caution: Color(0xFFFFFF00),
    danger: Color(0xFFFF8A8A),
    safeFill: Color(0xFF00FF7F),
    progressFill: Color(0xFF8CC8FF),
    cautionFill: Color(0xFFFFFF00),
    dangerFill: Color(0xFFFF8A8A),
    onSafeFill: Color(0xFF000000),
    onProgressFill: Color(0xFF000000),
    onCautionFill: Color(0xFF000000),
    onDangerFill: Color(0xFF000000),
    shadow: Color(0x00000000),
    tileTop: Color(0xFF0A0A0A),
    tileBottom: Color(0xFF0A0A0A),
  );

  static const all = [light, dark, contrast];

  /// 색 테마별 주요색(밝은 모드, 어두운 모드). 모두 WCAG AA 대비 검사 대상.
  static const colorThemes = <String, (Color, Color, Color, Color)>{
    'violet': (
      Color(0xFF4338CA),
      Color(0xFFFFFFFF),
      Color(0xFFA5B4FC),
      Color(0xFF1E1B4B),
    ),
    'plum': (
      Color(0xFF86198F),
      Color(0xFFFFFFFF),
      Color(0xFFF0ABFC),
      Color(0xFF3B0764),
    ),
    'navy': (
      Color(0xFF1E3A8A),
      Color(0xFFFFFFFF),
      Color(0xFFA5C8FF),
      Color(0xFF0B1B3A),
    ),
    'slate': (
      Color(0xFF334155),
      Color(0xFFFFFFFF),
      Color(0xFFCBD5E1),
      Color(0xFF0F172A),
    ),
  };

  /// 색 테마 적용(고대비 모드는 바꾸지 않음).
  AppPalette withColorTheme(String theme) {
    final t = colorThemes[theme];
    if (t == null || name == 'contrast') return this;
    final dark = brightness == Brightness.dark;
    return AppPalette(
      name: '$name-$theme',
      brightness: brightness,
      background: background,
      surface: surface,
      surfaceAlt: surfaceAlt,
      text: text,
      textMuted: textMuted,
      border: border,
      primary: dark ? t.$3 : t.$1,
      onPrimary: dark ? t.$4 : t.$2,
      accent: accent,
      onAccent: onAccent,
      safe: safe,
      progress: progress,
      caution: caution,
      danger: danger,
      safeFill: safeFill,
      progressFill: progressFill,
      cautionFill: cautionFill,
      dangerFill: dangerFill,
      onSafeFill: onSafeFill,
      onProgressFill: onProgressFill,
      onCautionFill: onCautionFill,
      onDangerFill: onDangerFill,
      shadow: shadow,
      tileTop: tileTop,
      tileBottom: tileBottom,
    );
  }
}

/// 크기·간격·둥글기·그림자·움직임 시간.
class AppTokens {
  AppTokens._();

  // 크기
  static const buttonHeight = 56.0;
  static const minTouch = 48.0;
  static const iconSize = 28.0;
  static const tileEmoji = 56.0;
  static const smallestScreen = Size(360, 640);

  // 간격
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 24.0;
  static const s6 = 32.0;

  // 둥글기
  static const radiusButton = 18.0;
  static const radiusCard = 20.0;
  static const radiusTile = 26.0;

  // 카드 사이 간격(기존 12의 1.5배)
  static const cardGap = 18.0;

  // 글자 위계 4단계(기본, 화면 배율이 곱해짐): 큰 숫자 > 화면 제목 > 카드 제목 > 본문
  static const fontDisplay = 44.0;
  static const fontTitle = 28.0;
  static const fontHeading = 22.0;
  static const fontBody = 18.0;
  static const fontSmall = 16.0;
  static const fontBigNumber = 40.0;

  // 움직임
  static const pressDuration = Duration(milliseconds: 110);
  static const transition = Duration(milliseconds: 220);
  static const lockAnimation = Duration(milliseconds: 650); // 1초 이내
  static const checkAnimation = Duration(milliseconds: 500);

  /// 카드용 부드러운 그림자(입체감 없이 바탕과 구분만).
  static List<BoxShadow> soft(AppPalette p) {
    if (p.name == 'contrast') return const [];
    return [
      BoxShadow(
        color: p.shadow.withValues(
          alpha: p.brightness == Brightness.dark ? 0.45 : 0.12,
        ),
        offset: const Offset(0, 3),
        blurRadius: 10,
      ),
    ];
  }

  /// 입체 그림자(메인 타일·주요 버튼만 사용).
  static List<BoxShadow> raised(AppPalette p, {bool pressed = false}) {
    if (p.name == 'contrast') return const [];
    return pressed
        ? [
            BoxShadow(
              color: p.shadow,
              offset: const Offset(0, 1),
              blurRadius: 2,
            ),
          ]
        : [
            BoxShadow(
              color: p.shadow,
              offset: const Offset(0, 6),
              blurRadius: 0,
            ),
            BoxShadow(
              color: p.shadow.withValues(alpha: p.shadow.a * 0.6),
              offset: const Offset(0, 10),
              blurRadius: 16,
            ),
          ];
  }

  static const fontFamily = 'NotoSansKR';
}

/// 앱 어디서나 테마 값을 꺼내 쓰는 도우미.
class AppTheme extends InheritedWidget {
  const AppTheme({
    super.key,
    required this.palette,
    required this.reduceMotion,
    required super.child,
  });

  final AppPalette palette;
  final bool reduceMotion;

  static AppTheme of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppTheme>() ??
      const AppTheme(
        palette: AppPalette.light,
        reduceMotion: false,
        child: SizedBox(),
      );

  Duration motion(Duration d) => reduceMotion ? Duration.zero : d;

  @override
  bool updateShouldNotify(AppTheme old) =>
      old.palette != palette || old.reduceMotion != reduceMotion;
}

extension ThemeX on BuildContext {
  AppPalette get palette => AppTheme.of(this).palette;
  Duration motion(Duration d) => AppTheme.of(this).motion(d);
  bool get reduceMotion => AppTheme.of(this).reduceMotion;
}

AppPalette paletteFor(
  String mode,
  Brightness platform, [
  String colorTheme = 'violet',
]) => _basePalette(mode, platform).withColorTheme(colorTheme);

AppPalette _basePalette(String mode, Brightness platform) => switch (mode) {
  'dark' => AppPalette.dark,
  'contrast' => AppPalette.contrast,
  'system' => platform == Brightness.dark ? AppPalette.dark : AppPalette.light,
  _ => AppPalette.light,
};

ThemeData buildTheme(AppPalette p) {
  final scheme = ColorScheme(
    brightness: p.brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    secondary: p.accent,
    onSecondary: p.onAccent,
    error: p.danger,
    onError: p.onDangerFill,
    surface: p.surface,
    onSurface: p.text,
    surfaceContainerHighest: p.surfaceAlt,
    outline: p.border,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: AppTokens.fontFamily,
    scaffoldBackgroundColor: p.background,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
  );
  final text = base.textTheme.apply(bodyColor: p.text, displayColor: p.text);
  return base.copyWith(
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontSize: AppTokens.fontTitle,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontSize: AppTokens.fontHeading,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontSize: AppTokens.fontBody,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: text.bodyLarge?.copyWith(
        fontSize: AppTokens.fontBody,
        height: 1.4,
      ),
      bodyMedium: text.bodyMedium?.copyWith(
        fontSize: AppTokens.fontSmall,
        height: 1.4,
      ),
      labelLarge: text.labelLarge?.copyWith(
        fontSize: AppTokens.fontBody,
        fontWeight: FontWeight.w700,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 64,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: TextStyle(color: p.textMuted, fontSize: AppTokens.fontBody),
      hintStyle: TextStyle(color: p.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusButton),
        borderSide: BorderSide(color: p.border, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusButton),
        borderSide: BorderSide(color: p.border, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusButton),
        borderSide: BorderSide(color: p.primary, width: 3),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.onPrimary : p.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.primary : p.surfaceAlt,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.text,
      contentTextStyle: TextStyle(
        color: p.background,
        fontSize: AppTokens.fontBody,
      ),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: DividerThemeData(color: p.border),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

/// WCAG 대비 비율(테스트에서 사용).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
