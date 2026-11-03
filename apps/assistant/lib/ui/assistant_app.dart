import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../app/assistant_state.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// 본체 앱. 하나의 글씨 크기·테마·움직임 설정이 모든 화면(모듈 포함)에 바로 적용된다.
class AssistantApp extends StatelessWidget {
  const AssistantApp({super.key, required this.state});
  final AssistantState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final s = state.settings;
        return MaterialApp(
          title: s.appName,
          debugShowCheckedModeBanner: false,
          theme: AssistantTheme.build(brightness: Brightness.light, highContrast: s.highContrast),
          darkTheme: AssistantTheme.build(brightness: Brightness.dark, highContrast: s.highContrast),
          themeMode: AssistantTheme.mode(s),
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [Locale('ko', 'KR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(s.textSize.scale), disableAnimations: s.reduceMotion || mq.disableAnimations),
              child: child!,
            );
          },
          home: state.user == null ? LoginScreen(state: state) : HomeScreen(key: ValueKey(state.user!.id), state: state),
        );
      },
    );
  }
}
