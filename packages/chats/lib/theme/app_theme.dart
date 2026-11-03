import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'tokens.dart';

/// 테마 값을 화면 어디서나 꺼내 쓰기 위한 확장.
class AppTheme extends ThemeExtension<AppTheme> {
  final AppPalette palette;
  final bool reduceMotion;

  const AppTheme(this.palette, {this.reduceMotion = false});

  static AppTheme of(BuildContext context) => Theme.of(context).extension<AppTheme>()!;

  /// 움직임 줄이기가 켜져 있으면 0초.
  Duration motion(BuildContext context, Duration d) =>
      reduceMotion || MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;

  @override
  AppTheme copyWith({AppPalette? palette, bool? reduceMotion}) =>
      AppTheme(palette ?? this.palette, reduceMotion: reduceMotion ?? this.reduceMotion);

  @override
  AppTheme lerp(covariant AppTheme? other, double t) => t < 0.5 ? this : (other ?? this);

  static ThemeData build(AppPalette p, {bool reduceMotion = false}) {
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      secondary: p.accent,
      onSecondary: p.onAccent,
      error: p.danger,
      onError: p.onDanger,
      surface: p.surface,
      onSurface: p.text,
      surfaceContainerHighest: p.surfaceAlt,
      outline: p.border,
    );
    TextStyle t(double size, FontWeight w, {Color? color, double height = 1.45}) =>
        TextStyle(fontSize: size, fontWeight: w, color: color ?? p.text, height: height, fontFamily: 'NanumGothic');
    final text = TextTheme(
      // 글자 위계 4단계: 큰 숫자(display) > 제목(title) > 본문(body) > 설명(small)
      displaySmall: t(AppSize.textDisplay, FontWeight.w900, height: 1.1),
      headlineMedium: t(AppSize.textHeadline, FontWeight.w800, height: 1.3),
      titleLarge: t(AppSize.textTitle, FontWeight.w800, height: 1.3),
      titleMedium: t(AppSize.textBody + 1, FontWeight.w700),
      bodyLarge: t(AppSize.textBody, FontWeight.w400),
      bodyMedium: t(AppSize.textBody, FontWeight.w400),
      bodySmall: t(AppSize.textSmall, FontWeight.w400, color: p.textMuted),
      labelLarge: t(AppSize.textButton, FontWeight.w700),
      labelMedium: t(AppSize.textSmall, FontWeight.w700),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: p.brightness,
      fontFamily: 'NanumGothic',
      scaffoldBackgroundColor: p.background,
      textTheme: text,
      extensions: [AppTheme(p, reduceMotion: reduceMotion)],
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: reduceMotion
          ? const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: _NoTransition(),
                TargetPlatform.iOS: _NoTransition(),
                TargetPlatform.windows: _NoTransition(),
                TargetPlatform.macOS: _NoTransition(),
                TargetPlatform.linux: _NoTransition(),
              },
            )
          : const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
                TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
                TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
              },
            ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        toolbarHeight: 64,
      ),
      // 테두리만 있는 상자 대신: 배경색을 채운 카드 + 부드러운 그림자(고대비에서만 테두리)
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: p.borderWidth > 1 ? 0 : 2,
        shadowColor: p.shadow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSize.radiusCard),
          side: p.borderWidth > 1 ? BorderSide(color: p.border, width: p.borderWidth) : BorderSide.none,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: t(AppSize.textBody, FontWeight.w400, color: p.textMuted),
        labelStyle: t(AppSize.textBody, FontWeight.w600, color: p.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSize.radius),
          borderSide: BorderSide(color: p.border, width: p.borderWidth),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSize.radius),
          borderSide: BorderSide(color: p.border, width: p.borderWidth),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSize.radius),
          borderSide: BorderSide(color: p.primary, width: 2.5),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onPrimary : p.textMuted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.primary : p.surfaceAlt),
        trackOutlineColor: WidgetStatePropertyAll(p.border),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceAlt,
        selectedColor: p.primary,
        labelStyle: t(AppSize.textSmall, FontWeight.w700),
        secondaryLabelStyle: t(AppSize.textSmall, FontWeight.w700, color: p.onPrimary),
        checkmarkColor: p.onPrimary,
        side: BorderSide(color: p.border, width: p.borderWidth),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSize.radiusSmall)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSize.radiusCard)),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSize.radius)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.info, linearTrackColor: p.surfaceAlt),
      dividerTheme: DividerThemeData(color: p.border, thickness: p.borderWidth),
      sliderTheme: SliderThemeData(activeTrackColor: p.primary, thumbColor: p.primary, inactiveTrackColor: p.surfaceAlt),
    );
  }
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
