import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'core/logger.dart';
import 'services/media_picker.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/import_screen.dart';
import 'ui/keys.dart';
import 'ui/screens/onboarding_screen.dart';

export 'ui/keys.dart';

class BinugiApp extends StatelessWidget {
  final AppState state;
  final MediaPicker picker;
  final bool listenShares;
  const BinugiApp({super.key, required this.state, required this.picker, this.listenShares = true});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
        Provider<MediaPicker>.value(value: picker),
      ],
      child: Consumer<AppState>(
        builder: (context, s, _) => MaterialApp(
          navigatorKey: navKey,
          scaffoldMessengerKey: messengerKey,
          title: s.global.appName,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(s.global.theme, reduceMotion: s.global.reduceMotion, colorTheme: s.global.colorTheme),
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [Locale('ko', 'KR')],
          localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final system = mq.textScaler.scale(1).clamp(1.0, 1.3);
            return MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(system * s.global.textSize.scale),
                disableAnimations: s.global.reduceMotion || mq.disableAnimations,
              ),
              child: child!,
            );
          },
          home: s.global.onboarded ? ShareListener(enabled: listenShares, child: const HomeScreen()) : const OnboardingScreen(),
        ),
      ),
    );
  }
}

/// 안드로이드 "공유하기 → 이 앱"으로 들어온 글을 가져오기 화면으로 넘김
class ShareListener extends StatefulWidget {
  final Widget child;
  final bool enabled;
  const ShareListener({super.key, required this.child, this.enabled = true});
  @override
  State<ShareListener> createState() => _ShareListenerState();
}

class _ShareListenerState extends State<ShareListener> {
  StreamSubscription<List<SharedMediaFile>>? _sub;

  bool get _supported => widget.enabled && !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    if (!_supported) return;
    try {
      _sub = ReceiveSharingIntent.instance.getMediaStream().listen(_handle, onError: (e) => log.warn('공유 받기 오류: $e'));
      ReceiveSharingIntent.instance.getInitialMedia().then((m) {
        _handle(m);
        ReceiveSharingIntent.instance.reset();
      });
    } catch (e) {
      log.warn('공유 받기 사용 불가: $e');
    }
  }

  void _handle(List<SharedMediaFile> files) {
    final texts = files.where((f) => f.type == SharedMediaType.text || f.type == SharedMediaType.url).map((f) => f.path).join('\n');
    if (texts.trim().isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navKey.currentState?.push(MaterialPageRoute(builder: (_) => ImportScreen(initialText: texts)));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 시작 자체가 실패했을 때 보여 주는 화면
class StartFailedApp extends StatelessWidget {
  final String error;
  const StartFailedApp({super.key, required this.error});
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildTheme(ThemeModeChoice.light),
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('앱을 시작하지 못했어요', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              const Text('기기를 다시 켠 뒤 앱을 열어 보세요. 계속 안 되면 저장 공간이 충분한지 확인해 주세요.', style: TextStyle(fontSize: 18), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Text(AppLogger.redact(error), style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
        ),
      ),
    ),
  );
}
