import 'package:flutter/material.dart';

/// 앱의 모든 색·크기·간격·둥글기·그림자·애니메이션 시간을 모은 단 하나의 파일.
/// 모든 화면은 여기 값만 사용합니다.

enum ThemeModeChoice { light, dark, highContrast }

enum TextSizeChoice { normal, large, huge }

extension TextSizeScale on TextSizeChoice {
  double get scale => switch (this) {
    TextSizeChoice.normal => 1.0,
    TextSizeChoice.large => 1.25,
    TextSizeChoice.huge => 1.5,
  };
  String get label => switch (this) {
    TextSizeChoice.normal => '보통',
    TextSizeChoice.large => '크게',
    TextSizeChoice.huge => '아주 크게',
  };
}

/// 분류(지금 쓰는 것 / 판매 / 폐기)와 상태 색. 어디서나 같은 색.
class AppPalette {
  final Color primary; // 주요색
  final Color onPrimary;
  final Color accent; // 강조색
  final Color onAccent;
  final Color use; // 지금 쓰는 것 = 파랑
  final Color sell; // 판매 = 초록
  final Color discard; // 폐기 = 빨강
  final Color progress; // 진행 중 = 보라
  final Color attention; // 확인 필요 = 노랑
  final Color onAttention;
  final Color background;
  final Color surface;
  final Color onSurface;
  final Color muted;
  final Color shadow;
  final Color border;
  final Brightness brightness;

  const AppPalette({
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.use,
    required this.sell,
    required this.discard,
    required this.progress,
    required this.attention,
    required this.onAttention,
    required this.background,
    required this.surface,
    required this.onSurface,
    required this.muted,
    required this.shadow,
    required this.border,
    required this.brightness,
  });

  /// 분류 색 위의 글자는 항상 흰색 (대비 검사 통과 색만 사용)
  Color get onCategory => Colors.white;

  static const light = AppPalette(
    primary: Color(0xFF2B4C7E),
    onPrimary: Colors.white,
    accent: Color(0xFFB35900),
    onAccent: Colors.white,
    use: Color(0xFF1565C0),
    sell: Color(0xFF2E7D32),
    discard: Color(0xFFC62828),
    progress: Color(0xFF6A1B9A),
    attention: Color(0xFFFFD54F),
    onAttention: Color(0xFF212121),
    background: Color(0xFFF5F3EE),
    surface: Colors.white,
    onSurface: Color(0xFF1C1C1C),
    muted: Color(0xFF555555),
    shadow: Color(0x33000000),
    border: Color(0xFFD6D2C8),
    brightness: Brightness.light,
  );

  static const dark = AppPalette(
    primary: Color(0xFF9EC1F7),
    onPrimary: Color(0xFF0D1B2E),
    accent: Color(0xFFFFB74D),
    onAccent: Color(0xFF1C1C1C),
    use: Color(0xFF1565C0),
    sell: Color(0xFF2E7D32),
    discard: Color(0xFFC62828),
    progress: Color(0xFF7B1FA2),
    attention: Color(0xFFFFD54F),
    onAttention: Color(0xFF212121),
    background: Color(0xFF121212),
    surface: Color(0xFF262A30),
    onSurface: Color(0xFFF0F0F0),
    muted: Color(0xFFBDBDBD),
    shadow: Color(0x66000000),
    border: Color(0xFF3A3A3A),
    brightness: Brightness.dark,
  );

  static const highContrast = AppPalette(
    primary: Color(0xFF000000),
    onPrimary: Colors.white,
    accent: Color(0xFF6B2E00),
    onAccent: Colors.white,
    use: Color(0xFF0D47A1),
    sell: Color(0xFF1B5E20),
    discard: Color(0xFFB71C1C),
    progress: Color(0xFF4A148C),
    attention: Color(0xFFFFEB3B),
    onAttention: Colors.black,
    background: Colors.white,
    surface: Colors.white,
    onSurface: Colors.black,
    muted: Color(0xFF222222),
    shadow: Color(0x55000000),
    border: Colors.black,
    brightness: Brightness.light,
  );

  static AppPalette of(ThemeModeChoice m, [String colorTheme = 'ocean']) {
    final base = switch (m) {
      ThemeModeChoice.light => light,
      ThemeModeChoice.dark => dark,
      ThemeModeChoice.highContrast => highContrast,
    };
    if (m == ThemeModeChoice.highContrast) return base; // 고대비는 색 테마 없이 고정
    final c = colorThemes[colorTheme] ?? colorThemes['ocean']!;
    return base.withPrimary(m == ThemeModeChoice.dark ? c.dark : c.light, onDark: m == ThemeModeChoice.dark);
  }

  AppPalette withPrimary(Color p, {required bool onDark}) => AppPalette(
    primary: p,
    onPrimary: onDark ? const Color(0xFF0D1B2E) : Colors.white,
    accent: accent,
    onAccent: onAccent,
    use: use,
    sell: sell,
    discard: discard,
    progress: progress,
    attention: attention,
    onAttention: onAttention,
    background: background,
    surface: surface,
    onSurface: onSurface,
    muted: muted,
    shadow: shadow,
    border: border,
    brightness: brightness,
  );
}

/// 색 테마 (주요색만 바뀜. 분류색 파랑·초록·빨강, 상태색 보라·노랑은 고정)
class ColorTheme {
  final String label;
  final Color light;
  final Color dark;
  const ColorTheme(this.label, this.light, this.dark);
}

const colorThemes = <String, ColorTheme>{
  'ocean': ColorTheme('바다 (남색)', Color(0xFF2B4C7E), Color(0xFF9EC1F7)),
  'earth': ColorTheme('흙 (갈색)', Color(0xFF5D4037), Color(0xFFD7B9A8)),
  'slate': ColorTheme('먹 (회청색)', Color(0xFF37474F), Color(0xFFB0BEC5)),
  'lake': ColorTheme('호수 (청록)', Color(0xFF00576B), Color(0xFF8ED3E3)),
};

/// 글자 위계 4단계: 큰 숫자 > 제목 > 본문 > 설명
class AppText {
  static const double display = 34; // 큰 숫자 (현황)
  static const double title = 22; // 화면·카드 제목
  static const double body = 17; // 본문
  static const double caption = 14.5; // 작은 설명
}

/// 크기·간격·둥글기
class AppSizes {
  static const double buttonMinHeight = 56;
  static const double touchMin = 48;
  static const double radius = 18;
  static const double radiusSmall = 12;
  static const double gap = 16;
  static const double gapSmall = 8;
  static const double gapLarge = 24;
  static const double cardGap = 24; // 카드 사이 간격 (기본 간격의 1.5배)
  static const double page = 16;
  static const double captureButton = 84;
  static const double tileIcon = 56;
  static const double cardBorder = 4;
  static const double depth = 5; // 3D 두께
  static const double thumb = 300; // 썸네일 긴 변(px)
  static const int photoMaxSide = 1568; // 저장·AI 전송 사진 긴 변(px)
}

/// 움직임 시간. "움직임 줄이기"가 켜지면 모두 0.
class AppMotion {
  final bool reduce;
  const AppMotion(this.reduce);
  Duration get fast => reduce ? Duration.zero : const Duration(milliseconds: 120);
  Duration get normal => reduce ? Duration.zero : const Duration(milliseconds: 280);
  Duration get slow => reduce ? Duration.zero : const Duration(milliseconds: 600);
  Duration get celebrate => reduce ? Duration.zero : const Duration(milliseconds: 1200);
}

/// 그림자(입체감). 메인 타일과 주요 버튼에만 사용.
class AppShadows {
  /// 일반 카드용 부드러운 그림자 (가벼움)
  static List<BoxShadow> soft(AppPalette p) => [BoxShadow(color: p.shadow.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4))];

  static List<BoxShadow> raised(AppPalette p, {bool pressed = false}) => pressed
      ? [BoxShadow(color: p.shadow, blurRadius: 2, offset: const Offset(0, 1))]
      : [
          BoxShadow(color: p.shadow, blurRadius: 10, offset: const Offset(0, 6)),
          BoxShadow(color: p.shadow.withValues(alpha: 0.1), blurRadius: 1, offset: const Offset(0, 1)),
        ];
}

/// 테마 확장: 위젯에서 `context.palette` 로 꺼내 씀.
class AppThemeExt extends ThemeExtension<AppThemeExt> {
  final AppPalette palette;
  final AppMotion motion;
  final bool highContrast;
  const AppThemeExt(this.palette, this.motion, {this.highContrast = false});
  @override
  AppThemeExt copyWith({AppPalette? palette, AppMotion? motion}) => AppThemeExt(palette ?? this.palette, motion ?? this.motion, highContrast: highContrast);
  @override
  AppThemeExt lerp(covariant AppThemeExt? other, double t) => other ?? this;
}

extension AppThemeContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppThemeExt>()!.palette;
  AppMotion get motion => Theme.of(this).extension<AppThemeExt>()!.motion;
}

const String appFont = 'NotoSansKR';

ThemeData buildTheme(ThemeModeChoice mode, {bool reduceMotion = false, String colorTheme = 'ocean'}) {
  final p = AppPalette.of(mode, colorTheme);
  final scheme = ColorScheme(
    brightness: p.brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    secondary: p.accent,
    onSecondary: p.onAccent,
    error: p.discard,
    onError: Colors.white,
    surface: p.surface,
    onSurface: p.onSurface,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: appFont);
  final text = base.textTheme
      .apply(bodyColor: p.onSurface, displayColor: p.onSurface, fontFamily: appFont)
      .copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: p.onSurface, fontSize: AppText.display),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: p.onSurface, fontSize: 26),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: p.onSurface, fontSize: AppText.title),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: p.onSurface, fontSize: 18),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(color: p.onSurface, fontSize: AppText.body),
        bodySmall: base.textTheme.bodySmall?.copyWith(color: p.muted, fontSize: AppText.caption),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(color: p.onSurface, fontSize: 16),
      );
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radius));
  const minSize = Size(AppSizes.touchMin, AppSizes.buttonMinHeight);
  return base.copyWith(
    scaffoldBackgroundColor: p.background,
    textTheme: text,
    extensions: [AppThemeExt(p, AppMotion(reduceMotion), highContrast: mode == ThemeModeChoice.highContrast)],
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: text.headlineMedium,
      toolbarHeight: 64,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: minSize,
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        shape: buttonShape,
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFamily: appFont),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        elevation: 4,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: minSize, shape: buttonShape, backgroundColor: p.primary, foregroundColor: p.onPrimary),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: minSize,
        shape: buttonShape,
        foregroundColor: p.onSurface,
        side: BorderSide(color: p.border, width: 2),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFamily: appFont),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: minSize,
        foregroundColor: p.primary,
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFamily: appFont),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusSmall),
        borderSide: BorderSide(color: p.border, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusSmall),
        borderSide: BorderSide(color: p.border, width: 2),
      ),
      labelStyle: TextStyle(color: p.muted, fontSize: 17),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radius)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      contentTextStyle: const TextStyle(fontSize: 17, fontFamily: appFont, color: Colors.white),
      backgroundColor: const Color(0xFF263238),
      actionTextColor: const Color(0xFFFFD54F),
    ),
    dividerColor: p.border,
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.primary : p.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.primary.withValues(alpha: 0.4) : p.border),
    ),
  );
}

/// WCAG 대비 계산 (자동 대비 검사에 사용)
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
