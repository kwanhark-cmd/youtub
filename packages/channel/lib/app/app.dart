import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/strings.dart';
import '../features/accounts/local_accounts.dart';
import '../ui/home_shell.dart';
import '../ui/login_screen.dart';
import '../ui/onboarding.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'services.dart';

/// 앱 전체 상태: 누가 로그인했는지, 글씨 크기.
class AppState extends ChangeNotifier {
  AppState(this.env);
  final AppEnv env;
  UserContext? user;

  /// 로그인 전 화면의 글씨 크기 (마지막 사용자 설정을 기억).
  double get textScale =>
      user?.settings.textScale ?? (env.accounts.db.getSetting<num>('lastTextScale')?.toDouble() ?? 1.0);

  /// 다른 기능 단계(2~4단계)가 로그인 직후 기능을 붙이는 곳.
  static final List<Future<void> Function(UserContext)> plugins = [];

  Future<void> login(LocalUser u) async {
    user?.close();
    final ctx = await UserContext.open(env, u);
    for (final p in plugins) {
      await p(ctx);
    }
    user = ctx;
    UiPrefs.haptics = ctx.settings.haptics;
    UiHooks.logError = (m) => env.logger.error(m);
    UiHooks.makeReport = () async {
      try {
        return ctx.maintenance.writeReport(env.documentsDir);
      } catch (e) {
        env.logger.error('문제 신고 파일 만들기 실패', e);
        return null;
      }
    };
    UiPrefs.sound = ctx.settings.clickSound;
    env.logger.info('로그인 #${u.id}');
    notifyListeners();
  }

  static const autoLoginKey = 'app/autoLogin';

  /// 자동 로그인: 보안 저장소에 사용자 번호만 둔다 (비밀번호는 저장하지 않음).
  Future<void> setAutoLogin(LocalUser u, bool on) =>
      on ? env.secrets.write(autoLoginKey, '${u.id}') : env.secrets.delete(autoLoginKey);

  Future<bool> tryAutoLogin() async {
    try {
      final id = int.tryParse(await env.secrets.read(autoLoginKey) ?? '');
      if (id == null) return false;
      final found = env.accounts.list().where((x) => x.id == id);
      if (found.isEmpty) return false;
      await login(found.first);
      return true;
    } catch (e) {
      env.logger.warn('자동 로그인 실패: $e');
      return false;
    }
  }

  void logout() {
    env.secrets.delete(autoLoginKey);
    user?.close();
    user = null;
    notifyListeners();
  }

  void setTextScale(double v) {
    user?.settings.textScale = v;
    env.accounts.db.setSetting('lastTextScale', v);
    notifyListeners();
  }

  void refresh() => notifyListeners();

  // ---- 보기 설정 (로그인 전에는 마지막 값을 기억) ----
  T _view<T>(String key, T Function() fromUser, T def) =>
      user != null ? fromUser() : (env.accounts.db.getSetting<T>('last_$key') ?? def);

  String get themeMode => _view('themeMode', () => user!.settings.themeMode, 'system');
  bool get highContrast => _view('highContrast', () => user!.settings.highContrast, false);
  bool get reduceMotion => _view('reduceMotion', () => user!.settings.reduceMotion, false);

  /// 앱 꾸미기 (사용자별). 로그인 전에는 기본값.
  ColorTheme get colorTheme => ColorTheme.values.asNameMap()[user?.settings.colorTheme] ?? ColorTheme.basic;
  String get displayName => user?.look.displayName ?? S.appName;

  void setView({String? themeMode, bool? highContrast, bool? reduceMotion}) {
    final s = user?.settings;
    if (themeMode != null) {
      s?.themeMode = themeMode;
      env.accounts.db.setSetting('last_themeMode', themeMode);
    }
    if (highContrast != null) {
      s?.highContrast = highContrast;
      env.accounts.db.setSetting('last_highContrast', highContrast);
    }
    if (reduceMotion != null) {
      s?.reduceMotion = reduceMotion;
      env.accounts.db.setSetting('last_reduceMotion', reduceMotion);
    }
    notifyListeners();
  }
}

AppTokens tokensFor(AppState s, Brightness b, {bool platformReduceMotion = false}) {
  final rm = s.reduceMotion || platformReduceMotion;
  if (s.highContrast) return AppTokens.contrast(darkMode: b == Brightness.dark, reduceMotion: rm);
  final base = b == Brightness.dark ? AppTokens.dark(reduceMotion: rm) : AppTokens.light(reduceMotion: rm);
  return base.withPalette(s.colorTheme);
}

/// 창·최근 앱 목록에 보이는 이름
String displayName(AppState s) => s.displayName;

class ChannelBiseoApp extends StatelessWidget {
  const ChannelBiseoApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return MaterialApp(
          title: displayName(state),
          navigatorKey: appNavigatorKey,
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(tokensFor(state, Brightness.light), Brightness.light),
          darkTheme: buildAppTheme(tokensFor(state, Brightness.dark), Brightness.dark),
          themeMode: switch (state.themeMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          themeAnimationDuration: state.reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [Locale('ko', 'KR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          // 글씨 크기 설정을 모든 화면에 한 번에 적용
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(state.textScale)),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: _root(),
        );
      },
    );
  }

  Widget _root() {
    final u = state.user;
    if (u == null) return LoginScreen(state: state);
    if (!u.settings.onboardingDone) return OnboardingWizard(state: state, user: u);
    return HomeShell(state: state, user: u);
  }
}
