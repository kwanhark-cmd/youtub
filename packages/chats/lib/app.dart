import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'services/app_controller.dart';
import 'services/settings.dart';
import 'services/share_intake.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'ui/screens/import_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/profile_screen.dart';
import 'ui/nav.dart';
import 'ui/shell.dart';
import 'ui/widgets/common.dart';
import 'ui/widgets/dialogs.dart';

export 'ui/nav.dart' show navigatorKey, messengerKey;

/// 예상 못 한 오류가 나면 쉬운 한국어로 알려 줍니다(앱은 계속 동작).
class AppErrorBus {
  static DateTime? _last;
  static void report() {
    final now = DateTime.now();
    if (_last != null && now.difference(_last!) < const Duration(seconds: 5)) return;
    _last = now;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    showNotice(ctx, '잠깐 문제가 있었어요. 계속 쓰셔도 돼요. 반복되면 설정 > 문제 신고로 알려 주세요.', kind: StatusKind.problem);
  }
}

class AiChatOrganizerApp extends StatelessWidget {
  final AppController controller;
  final Widget? home;
  const AiChatOrganizerApp({super.key, required this.controller, this.home});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppController>.value(
      value: controller,
      child: Consumer<AppController>(
        builder: (context, c, _) {
          final s = c.settings;
          final light = AppTheme.build(
            ColorThemes.apply(AppPalette.pick(isDark: false, highContrast: s.highContrast), s.colorTheme),
            reduceMotion: s.reduceMotion,
          );
          final dark = AppTheme.build(
            ColorThemes.apply(AppPalette.pick(isDark: true, highContrast: s.highContrast), s.colorTheme),
            reduceMotion: s.reduceMotion,
          );
          return MaterialApp(
            title: 'AI 대화 기록 정리 비서',
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            scaffoldMessengerKey: messengerKey,
            theme: light,
            darkTheme: dark,
            themeMode: switch (s.theme) {
              ThemeChoice.system => ThemeMode.system,
              ThemeChoice.light => ThemeMode.light,
              ThemeChoice.dark => ThemeMode.dark,
            },
            locale: const Locale('ko', 'KR'),
            supportedLocales: const [Locale('ko', 'KR')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              // 글씨 크기 3단계를 모든 화면에 즉시 적용
              return MediaQuery(
                data: mq.copyWith(
                  textScaler: TextScaler.linear(s.fontSize.scale),
                  disableAnimations: s.reduceMotion || mq.disableAnimations,
                ),
                child: child!,
              );
            },
            home: home ?? const RootGate(),
          );
        },
      ),
    );
  }
}

/// 처음 실행·사용자 고르기·홈 중 알맞은 화면을 보여줍니다.
class RootGate extends StatefulWidget {
  const RootGate({super.key});
  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  @override
  void initState() {
    super.initState();
    // 안드로이드 "공유하기 → 이 앱"으로 들어온 파일
    ShareIntake.listen((path) {
      final c = context.read<AppController>();
      if (c.session == null) return;
      navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => ImportScreen(initialPath: path)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    if (c.fatalError != null) {
      return Scaffold(
        body: Center(
          child: EmptyState(
            mood: MascotMood.warning,
            title: '자료를 열지 못했어요',
            message: c.fatalError!,
            actionLabel: '사용자 고르기로 가기',
            onAction: c.signOut,
          ),
        ),
      );
    }
    final s = c.session;
    if (s == null) {
      if (c.profiles.isEmpty) return const OnboardingScreen();
      return const ProfileScreen();
    }
    if (!s.settings.onboardingDone) return const OnboardingScreen();
    return const MainShell();
  }
}
