import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../app/app_controller.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/recovery_reset_screen.dart';
import 'theme/tokens.dart';
import 'widgets/common.dart';

class VaultApp extends StatefulWidget {
  const VaultApp({super.key, required this.controller});
  final AppController controller;

  @override
  State<VaultApp> createState() => _VaultAppState();
}

class _VaultAppState extends State<VaultApp> {
  StreamSubscription<void>? _lockSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(widget.controller);
    rootNavigatorKey = widget.controller.navigatorKey;
    // 잠기면 열려 있던 화면을 모두 닫고 잠금 화면으로.
    _lockSub = widget.controller.lockEvents.stream.listen((_) {
      widget.controller.navigatorKey.currentState?.popUntil((r) => r.isFirst);
    });
  }

  @override
  void dispose() {
    _lockSub?.cancel();
    WidgetsBinding.instance.removeObserver(widget.controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: widget.controller,
      child: Builder(
        builder: (context) {
          final app = context.app;
          final platform = MediaQuery.platformBrightnessOf(context);
          final palette = paletteFor(
            app.settings.themeMode,
            platform,
            app.settings.colorTheme,
          );
          return AppTheme(
            palette: palette,
            reduceMotion: app.settings.reduceMotion,
            child: MaterialApp(
              navigatorKey: app.navigatorKey,
              navigatorObservers: [app.navObserver],
              debugShowCheckedModeBanner: false,
              title: app.settings.appTitle,
              theme: buildTheme(palette),
              locale: const Locale('ko', 'KR'),
              supportedLocales: const [Locale('ko', 'KR')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) {
                final mq = MediaQuery.of(context);
                // 글씨 크기 3단계 × 기기 설정, 너무 커지지 않게 2.2배까지
                final sys = mq.textScaler.scale(1);
                final scale = (app.settings.textScale * sys).clamp(1.0, 2.2);
                return MediaQuery(
                  data: mq.copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations:
                        app.settings.reduceMotion || mq.disableAnimations,
                  ),
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => app.touch(),
                    child: AppTheme(
                      palette: palette,
                      reduceMotion: app.settings.reduceMotion,
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                );
              },
              home: const RootGate(),
            ),
          );
        },
      ),
    );
  }
}

/// 상태에 따라 첫 화면을 고른다: 첫 실행 → 마법사, 잠김 → 잠금 화면, 열림 → 홈.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final Widget child;
    if (!app.ready) {
      child = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (app.onboarding || (app.profileList.isEmpty && !app.isUnlocked)) {
      child = const OnboardingScreen();
    } else if (app.isUnlocked && app.mustResetPassword) {
      child = const RecoveryResetScreen();
    } else if (app.isUnlocked) {
      child = const HomeScreen();
    } else if (app.profileList.isEmpty) {
      child = const OnboardingScreen();
    } else {
      child = const LockScreen();
    }
    return AnimatedSwitcher(
      duration: context.motion(AppTokens.transition),
      child: KeyedSubtree(key: ValueKey(child.runtimeType), child: child),
    );
  }
}

/// 화면 그리기 오류가 나도 앱이 멈추지 않고 쉬운 안내를 보여 준다.
class FriendlyErrorBox extends StatelessWidget {
  const FriendlyErrorBox({super.key});

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFFFF7D6),
    padding: const EdgeInsets.all(16),
    alignment: Alignment.center,
    child: const Text(
      '이 부분을 보여 주지 못했어요.\n설정 → 문제 신고에서 기록을 보내 주세요.',
      textAlign: TextAlign.center,
      style: TextStyle(color: Color(0xFF1F2937), fontSize: 18),
      textDirection: TextDirection.ltr,
    ),
  );
}
