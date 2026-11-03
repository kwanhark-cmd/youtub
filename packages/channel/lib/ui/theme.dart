import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 상태 4가지. 같은 뜻은 앱 어디서나 같은 색·아이콘을 쓴다.
enum Status {
  /// 초록: 완료·연결됨
  done,

  /// 파랑: 진행 중
  progress,

  /// 노랑: 확인 필요
  check,

  /// 빨강: 문제·주의
  problem,
}

/// 기능 영역별 색 (홈 타일·설정 묶음). 같은 영역은 앱 어디서나 같은 색.
enum Hue {
  /// 채널
  blue,

  /// 제작
  purple,

  /// 확인 대기
  yellow,

  /// 블로그
  orange,

  /// 내 코너
  green,

  /// 위험·문제
  red,

  /// 그 밖 (설정·자료 관리)
  slate,
}

/// 앱 꾸미기 → 색 묶음. 주요색·강조색·보조 버튼 색만 바뀌고 상태 색(초록·파랑·노랑·빨강)은 그대로.
enum ColorTheme { basic, ocean, forest, sunset }

/// 앱의 모든 색·크기·간격·둥글기·그림자·움직임 시간. 화면은 이 값만 쓴다.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.tonal,
    required this.onTonal,
    required this.success,
    required this.progress,
    required this.warning,
    required this.danger,
    required this.onStatusDark,
    required this.background,
    required this.card,
    required this.text,
    required this.textSoft,
    required this.border,
    required this.shadowColor,
    required this.reduceMotion,
    required this.highContrast,
  });

  // ---- 색 ----
  final Color primary; // 주요색
  final Color onPrimary;
  final Color accent; // 강조색 (주요 동작 버튼)
  final Color onAccent;
  final Color tonal; // 보조 버튼 바탕 (회색 대신 옅은 주요색)
  final Color onTonal;
  final Color success; // 초록
  final Color progress; // 파랑
  final Color warning; // 노랑
  final Color danger; // 빨강
  final Color onStatusDark; // 노랑 위 글자
  final Color background;
  final Color card;
  final Color text;
  final Color textSoft;
  final Color border;
  final Color shadowColor;

  // ---- 사용자 설정 ----
  final bool reduceMotion;
  final bool highContrast;

  // ---- 크기·간격·둥글기 ----
  static const double buttonHeight = 56;
  static const double touch = 48;
  static const double radius = 16;
  static const double radiusSmall = 12;
  static const double gapXs = 4;
  static const double gapS = 8;
  static const double gapM = 12;
  static const double gapL = 16;
  static const double gapXl = 24;

  /// 카드와 카드 사이 (예전 16의 1.5배)
  static const double cardGap = 24;
  static const double radiusCard = 22;
  static const double pagePad = 16;
  static const double bottomSpace = 120; // 마이크 버튼에 가리지 않게
  static const double iconS = 24;
  static const double iconM = 32;
  static const double icon3dS = 40;
  static const double icon3dM = 56;
  static const double icon3dL = 72;
  static const double depth = 5; // 버튼·타일의 두께 (눌리면 줄어듦)
  static const double tileMaxWidth = 320;
  static const double micSize = 84;
  static const double contentMaxWidth = 720;

  /// 큰 숫자 (게이지·통계). 글씨 단계: hero 34 > title 26 > section 21 > body 17 > small 15
  static const fontHero = 34.0;
  static const fontTitle = 26.0;
  static const fontSection = 21.0;
  static const fontBody = 17.0;
  static const fontButton = 18.0;
  static const fontSmall = 15.0;

  // ---- 움직임 시간 (움직임 줄이기면 0) ----
  Duration get fast => reduceMotion ? Duration.zero : const Duration(milliseconds: 150);
  Duration get normal => reduceMotion ? Duration.zero : const Duration(milliseconds: 250);
  Duration get slow => reduceMotion ? Duration.zero : const Duration(milliseconds: 450);
  Duration get stagger => reduceMotion ? Duration.zero : const Duration(milliseconds: 40);

  // ---- 그림자 (입체감) ----
  List<BoxShadow> raised([Color? base]) => [
    BoxShadow(color: shadowColor.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 6)),
    BoxShadow(color: shadowColor.withValues(alpha: 0.12), blurRadius: 3, offset: const Offset(0, 1)),
  ];

  List<BoxShadow> pressedShadow() => [
    BoxShadow(color: shadowColor.withValues(alpha: 0.22), blurRadius: 4, offset: const Offset(0, 1)),
  ];

  /// 채운 카드의 부드러운 그림자 (테두리 대신). 어두운 모드에서도 보이게 조금 진하게.
  List<BoxShadow> soft() => highContrast
      ? const []
      : [
          BoxShadow(
            color: shadowColor.withValues(alpha: background.computeLuminance() < 0.2 ? 0.45 : 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ];

  /// 영역 색 타일 바탕. 밝은 모드는 파스텔, 어두운 모드는 중간 채도 (어두운 바탕 위 어두운 상자 금지).
  Color tileBg(Hue h) {
    if (highContrast) return card;
    final dark = background.computeLuminance() < 0.2;
    return switch (h) {
      Hue.blue => dark ? const Color(0xFF2F5EAE) : const Color(0xFFDCEAFF),
      Hue.purple => dark ? const Color(0xFF6A45B8) : const Color(0xFFEDE3FF),
      Hue.yellow => dark ? const Color(0xFFD9A514) : const Color(0xFFFFF1BF),
      Hue.orange => dark ? const Color(0xFFB04E14) : const Color(0xFFFFE4D1),
      Hue.green => dark ? const Color(0xFF237447) : const Color(0xFFD9F4E3),
      Hue.red => dark ? const Color(0xFFB3261E) : const Color(0xFFFFE0DE),
      Hue.slate => dark ? const Color(0xFF4A5280) : const Color(0xFFE6E9F4),
    };
  }

  /// 영역 색 타일 위 글자색 (대비 4.5:1 이상, 테스트로 확인).
  Color onTile(Hue h) {
    if (highContrast) return text;
    final dark = background.computeLuminance() < 0.2;
    if (dark) return h == Hue.yellow ? const Color(0xFF1F1600) : const Color(0xFFFFFFFF);
    return switch (h) {
      Hue.blue => const Color(0xFF0B3577),
      Hue.purple => const Color(0xFF41197F),
      Hue.yellow => const Color(0xFF574000),
      Hue.orange => const Color(0xFF7A2E00),
      Hue.green => const Color(0xFF0D4A2C),
      Hue.red => const Color(0xFF7F1010),
      Hue.slate => const Color(0xFF262B45),
    };
  }

  /// 영역 색 아이콘 칩 (설정 묶음 머리 등): 진한 바탕 + 흰 아이콘.
  Color hueStrong(Hue h) {
    if (highContrast) return text;
    return switch (h) {
      Hue.blue => const Color(0xFF2563EB),
      Hue.purple => const Color(0xFF7C3AED),
      Hue.yellow => const Color(0xFF946200),
      Hue.orange => const Color(0xFFC2410C),
      Hue.green => const Color(0xFF15803D),
      Hue.red => const Color(0xFFB91C1C),
      Hue.slate => const Color(0xFF475070),
    };
  }

  Color onHueStrong(Hue h) => highContrast ? background : const Color(0xFFFFFFFF);

  static Hue hueOfStatus(Status s) => switch (s) {
    Status.done => Hue.green,
    Status.progress => Hue.blue,
    Status.check => Hue.yellow,
    Status.problem => Hue.red,
  };

  List<BoxShadow> flat() => [
    BoxShadow(color: shadowColor.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 1)),
  ];

  // ---- 상태 ----
  Color statusColor(Status s) => switch (s) {
    Status.done => success,
    Status.progress => progress,
    Status.check => warning,
    Status.problem => danger,
  };

  Color onStatus(Status s) => s == Status.check ? onStatusDark : const Color(0xFFFFFFFF);

  static IconData statusIcon(Status s) => switch (s) {
    Status.done => Icons.check_circle,
    Status.progress => Icons.autorenew,
    Status.check => Icons.error_outline,
    Status.problem => Icons.report,
  };

  /// 버튼 아래쪽 두께 색 (바탕보다 어둡게).
  static Color darker(Color c, [double amount = 0.22]) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness - amount).clamp(0.0, 1.0)).toColor();
  }

  static AppTokens light({bool reduceMotion = false}) => AppTokens(
    primary: const Color(0xFF3949AB),
    onPrimary: const Color(0xFFFFFFFF),
    accent: const Color(0xFFC2410C),
    onAccent: const Color(0xFFFFFFFF),
    tonal: const Color(0xFFE3E7FA),
    onTonal: const Color(0xFF26338A),
    success: const Color(0xFF15803D),
    progress: const Color(0xFF1D4ED8),
    warning: const Color(0xFFFACC15),
    danger: const Color(0xFFB91C1C),
    onStatusDark: const Color(0xFF1F2328),
    background: const Color(0xFFF6F7FB),
    card: const Color(0xFFFFFFFF),
    text: const Color(0xFF1A1C2E),
    textSoft: const Color(0xFF4A4F66),
    border: const Color(0xFFD5D9E8),
    shadowColor: const Color(0xFF1A1C2E),
    reduceMotion: reduceMotion,
    highContrast: false,
  );

  static AppTokens dark({bool reduceMotion = false}) => AppTokens(
    primary: const Color(0xFF8C9EFF),
    onPrimary: const Color(0xFF10163F),
    accent: const Color(0xFFC2410C),
    onAccent: const Color(0xFFFFFFFF),
    tonal: const Color(0xFF2A3157),
    onTonal: const Color(0xFFDDE2FF),
    success: const Color(0xFF15803D),
    progress: const Color(0xFF1D4ED8),
    warning: const Color(0xFFFACC15),
    danger: const Color(0xFFB91C1C),
    onStatusDark: const Color(0xFF1F2328),
    background: const Color(0xFF12131C),
    card: const Color(0xFF242739),
    text: const Color(0xFFECEDF5),
    textSoft: const Color(0xFFB9BCCF),
    border: const Color(0xFF3A3E57),
    shadowColor: const Color(0xFF000000),
    reduceMotion: reduceMotion,
    highContrast: false,
  );

  /// 고대비: 글자와 바탕 차이를 최대로.
  static AppTokens contrast({required bool darkMode, bool reduceMotion = false}) => darkMode
      ? AppTokens(
          primary: const Color(0xFFB4C1FF),
          onPrimary: const Color(0xFF000000),
          accent: const Color(0xFFFFB37A),
          onAccent: const Color(0xFF000000),
          tonal: const Color(0xFF000000),
          onTonal: const Color(0xFFFFFFFF),
          success: const Color(0xFF7CF2A4),
          progress: const Color(0xFF9CC2FF),
          warning: const Color(0xFFFFE066),
          danger: const Color(0xFFFF9A9A),
          onStatusDark: const Color(0xFF000000),
          background: const Color(0xFF000000),
          card: const Color(0xFF0B0B0B),
          text: const Color(0xFFFFFFFF),
          textSoft: const Color(0xFFF0F0F0),
          border: const Color(0xFFFFFFFF),
          shadowColor: const Color(0xFF000000),
          reduceMotion: reduceMotion,
          highContrast: true,
        )
      : AppTokens(
          primary: const Color(0xFF1A237E),
          onPrimary: const Color(0xFFFFFFFF),
          accent: const Color(0xFF8A2C08),
          onAccent: const Color(0xFFFFFFFF),
          tonal: const Color(0xFFFFFFFF),
          onTonal: const Color(0xFF000000),
          success: const Color(0xFF0B5A2A),
          progress: const Color(0xFF0B3A9E),
          warning: const Color(0xFFFFD500),
          danger: const Color(0xFF8B0000),
          onStatusDark: const Color(0xFF000000),
          background: const Color(0xFFFFFFFF),
          card: const Color(0xFFFFFFFF),
          text: const Color(0xFF000000),
          textSoft: const Color(0xFF1A1A1A),
          border: const Color(0xFF000000),
          shadowColor: const Color(0xFF000000),
          reduceMotion: reduceMotion,
          highContrast: true,
        );

  /// 색 묶음 적용 (고대비 모드에서는 쓰지 않음: 대비가 우선)
  AppTokens withPalette(ColorTheme p) {
    if (p == ColorTheme.basic || highContrast) return this;
    final dark = background.computeLuminance() < 0.2;
    // (주요색, 주요색 위 글자, 강조색, 강조색 위 글자, 보조 바탕, 보조 글자) — 대비는 테스트로 확인
    final c = switch ((p, dark)) {
      (ColorTheme.ocean, false) => (0xFF0B5C8C, 0xFFFFFFFF, 0xFF0F766E, 0xFFFFFFFF, 0xFFDCEFF7, 0xFF0B4566),
      (ColorTheme.ocean, true) => (0xFF7CC4F0, 0xFF062033, 0xFF0F766E, 0xFFFFFFFF, 0xFF1E3A4C, 0xFFD6EEFA),
      (ColorTheme.forest, false) => (0xFF2E6B3A, 0xFFFFFFFF, 0xFFB45309, 0xFFFFFFFF, 0xFFE1F0E3, 0xFF1F4D29),
      (ColorTheme.forest, true) => (0xFF8FD19E, 0xFF0E2A15, 0xFFB45309, 0xFFFFFFFF, 0xFF22392A, 0xFFDDF2E2),
      (ColorTheme.sunset, false) => (0xFF7B2D8E, 0xFFFFFFFF, 0xFFBE185D, 0xFFFFFFFF, 0xFFF3E2F7, 0xFF5A1F68),
      (ColorTheme.sunset, true) => (0xFFD7A6E6, 0xFF2E0F38, 0xFFBE185D, 0xFFFFFFFF, 0xFF3A2445, 0xFFF3DDF8),
      _ => (
        primary.toARGB32(),
        onPrimary.toARGB32(),
        accent.toARGB32(),
        onAccent.toARGB32(),
        tonal.toARGB32(),
        onTonal.toARGB32(),
      ),
    };
    return AppTokens(
      primary: Color(c.$1),
      onPrimary: Color(c.$2),
      accent: Color(c.$3),
      onAccent: Color(c.$4),
      tonal: Color(c.$5),
      onTonal: Color(c.$6),
      success: success,
      progress: progress,
      warning: warning,
      danger: danger,
      onStatusDark: onStatusDark,
      background: background,
      card: card,
      text: text,
      textSoft: textSoft,
      border: border,
      shadowColor: shadowColor,
      reduceMotion: reduceMotion,
      highContrast: highContrast,
    );
  }

  /// 빨강(위험) 버튼 위 글자색: 보통 흰색, 고대비 어두운 모드(밝은 빨강)에서는 검정.
  Color get onDanger => danger.computeLuminance() > 0.35 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

  /// 상태 색 위에 올라가는 글자색 (흰색 또는 짙은색) — 고대비 모드에서는 밝은 상태색에 검정.
  Color onStatusFor(Status s) {
    if (highContrast && background.computeLuminance() < 0.5) return const Color(0xFF000000);
    return onStatus(s);
  }

  @override
  AppTokens copyWith({bool? reduceMotion}) => AppTokens(
    primary: primary,
    onPrimary: onPrimary,
    accent: accent,
    onAccent: onAccent,
    tonal: tonal,
    onTonal: onTonal,
    success: success,
    progress: progress,
    warning: warning,
    danger: danger,
    onStatusDark: onStatusDark,
    background: background,
    card: card,
    text: text,
    textSoft: textSoft,
    border: border,
    shadowColor: shadowColor,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    highContrast: highContrast,
  );

  @override
  AppTokens lerp(AppTokens? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension TokensOf on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>() ?? AppTokens.light();
}

/// WCAG 대비 비율.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// 토큰으로 Flutter 테마를 만든다. 버튼은 모두 색이 있는 버튼(회색 글자 버튼 없음).
ThemeData buildAppTheme(AppTokens t, Brightness b) {
  final base = ColorScheme.fromSeed(seedColor: t.primary, brightness: b);
  final cs = base.copyWith(
    primary: t.primary,
    onPrimary: t.onPrimary,
    secondary: t.accent,
    onSecondary: t.onAccent,
    error: t.danger,
    onError: t.onDanger,
    surface: t.card,
    onSurface: t.text,
    onSurfaceVariant: t.textSoft,
    outline: t.border,
    primaryContainer: t.tonal,
    onPrimaryContainer: t.onTonal,
    secondaryContainer: t.tonal,
    onSecondaryContainer: t.onTonal,
    tertiaryContainer: t.warning,
    onTertiaryContainer: t.onStatusDark,
    errorContainer: t.danger,
    onErrorContainer: t.onDanger,
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppTokens.radius),
    side: t.highContrast ? BorderSide(color: t.border, width: 2) : BorderSide.none,
  );
  const minSize = Size(AppTokens.touch, AppTokens.buttonHeight);
  const textStyle = TextStyle(fontFamily: 'NotoSansKR', fontSize: AppTokens.fontButton, fontWeight: FontWeight.w700);
  const pad = EdgeInsets.symmetric(horizontal: AppTokens.gapL, vertical: AppTokens.gapM);
  final transitions = t.reduceMotion
      ? const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _NoTransition(),
            TargetPlatform.iOS: _NoTransition(),
            TargetPlatform.linux: _NoTransition(),
            TargetPlatform.macOS: _NoTransition(),
            TargetPlatform.windows: _NoTransition(),
          },
        )
      : const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          },
        );
  return ThemeData(
    colorScheme: cs,
    brightness: b,
    fontFamily: 'NotoSansKR',
    useMaterial3: true,
    scaffoldBackgroundColor: t.background,
    extensions: [t],
    pageTransitionsTheme: transitions,
    visualDensity: VisualDensity.comfortable,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    textTheme: TextTheme(
      headlineSmall: TextStyle(
        fontFamily: 'NotoSansKR',
        fontSize: AppTokens.fontTitle,
        fontWeight: FontWeight.w800,
        color: t.text,
      ),
      titleLarge: TextStyle(
        fontFamily: 'NotoSansKR',
        fontSize: AppTokens.fontSection,
        fontWeight: FontWeight.w700,
        color: t.text,
      ),
      titleMedium: TextStyle(
        fontFamily: 'NotoSansKR',
        fontSize: AppTokens.fontBody + 1,
        fontWeight: FontWeight.w700,
        color: t.text,
      ),
      bodyLarge: TextStyle(fontFamily: 'NotoSansKR', fontSize: AppTokens.fontBody + 1, color: t.text),
      bodyMedium: TextStyle(fontFamily: 'NotoSansKR', fontSize: AppTokens.fontBody, color: t.text),
      bodySmall: TextStyle(fontFamily: 'NotoSansKR', fontSize: AppTokens.fontSmall, color: t.textSoft),
      labelLarge: textStyle,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: t.background,
      foregroundColor: t.text,
      elevation: 0,
      scrolledUnderElevation: 2,
      centerTitle: false,
      toolbarHeight: 64,
      titleTextStyle: TextStyle(
        fontFamily: 'NotoSansKR',
        fontSize: AppTokens.fontTitle - 2,
        fontWeight: FontWeight.w800,
        color: t.text,
      ),
      iconTheme: IconThemeData(color: t.text, size: AppTokens.iconM),
    ),
    cardTheme: CardThemeData(
      color: t.card,
      elevation: t.highContrast ? 0 : 3,
      shadowColor: t.shadowColor.withValues(alpha: b == Brightness.dark ? 0.6 : 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        side: t.highContrast ? BorderSide(color: t.border, width: 2) : BorderSide.none,
      ),
      margin: const EdgeInsets.symmetric(vertical: AppTokens.cardGap / 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        minimumSize: minSize,
        padding: pad,
        textStyle: textStyle,
        shape: shape,
        elevation: 2,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: t.tonal,
        foregroundColor: t.onTonal,
        minimumSize: minSize,
        padding: pad,
        textStyle: textStyle,
        shape: shape,
        side: BorderSide(color: t.highContrast ? t.border : t.tonal, width: t.highContrast ? 2 : 1),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        backgroundColor: t.tonal,
        foregroundColor: t.onTonal,
        minimumSize: minSize,
        padding: pad,
        textStyle: textStyle,
        shape: shape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        backgroundColor: t.tonal,
        foregroundColor: t.onTonal,
        minimumSize: const Size(AppTokens.touch, AppTokens.touch),
        iconSize: AppTokens.iconS + 2,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: t.tonal,
        foregroundColor: t.onTonal,
        selectedBackgroundColor: t.primary,
        selectedForegroundColor: t.onPrimary,
        minimumSize: minSize,
        textStyle: textStyle,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.tonal,
      selectedColor: t.primary,
      labelStyle: TextStyle(
        fontFamily: 'NotoSansKR',
        color: t.onTonal,
        fontSize: AppTokens.fontBody,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: TextStyle(
        fontFamily: 'NotoSansKR',
        color: t.onPrimary,
        fontSize: AppTokens.fontBody,
        fontWeight: FontWeight.w700,
      ),
      checkmarkColor: t.onPrimary,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.gapM, vertical: AppTokens.gapS),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusSmall)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.accent,
      foregroundColor: t.onAccent,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radius + 8)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.card,
      indicatorColor: t.tonal,
      height: 76,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontFamily: 'NotoSansKR',
          fontSize: AppTokens.fontSmall - 1,
          fontWeight: FontWeight.w700,
          color: t.text,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(size: 28, color: s.contains(WidgetState.selected) ? t.onTonal : t.textSoft),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: t.card,
      indicatorColor: t.tonal,
      selectedIconTheme: IconThemeData(color: t.onTonal, size: 30),
      unselectedIconTheme: IconThemeData(color: t.textSoft, size: 28),
      selectedLabelTextStyle: TextStyle(
        fontFamily: 'NotoSansKR',
        color: t.text,
        fontWeight: FontWeight.w800,
        fontSize: AppTokens.fontSmall,
      ),
      unselectedLabelTextStyle: TextStyle(fontFamily: 'NotoSansKR', color: t.textSoft, fontSize: AppTokens.fontSmall),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.radiusSmall)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        borderSide: BorderSide(color: t.border, width: t.highContrast ? 2 : 1),
      ),
      labelStyle: TextStyle(fontFamily: 'NotoSansKR', color: t.textSoft, fontSize: AppTokens.fontBody),
      filled: true,
      fillColor: t.card,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radius + 4)),
      titleTextStyle: TextStyle(
        fontFamily: 'NotoSansKR',
        fontSize: AppTokens.fontSection,
        fontWeight: FontWeight.w800,
        color: t.text,
      ),
      contentTextStyle: TextStyle(fontFamily: 'NotoSansKR', fontSize: AppTokens.fontBody + 1, color: t.text),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.fixed,
      backgroundColor: t.text,
      contentTextStyle: TextStyle(fontFamily: 'NotoSansKR', fontSize: AppTokens.fontBody, color: t.background),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radius)),
      actionTextColor: t.warning,
    ),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: AppTokens.gapM,
      minTileHeight: AppTokens.touch + 8,
      textColor: t.text,
      iconColor: t.primary,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.onPrimary : t.textSoft),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.primary : t.tonal),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.progress, linearTrackColor: t.tonal),
    dividerTheme: DividerThemeData(color: t.border, thickness: t.highContrast ? 2 : 1),
  );
}

class _NoTransition extends PageTransitionsBuilder {
  const _NoTransition();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
