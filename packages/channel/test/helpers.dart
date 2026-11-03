import 'dart:io';

import 'package:channel_biseo/app/services.dart';
import 'package:channel_biseo/core/logger.dart';
import 'package:channel_biseo/core/secret_store.dart';
import 'package:channel_biseo/features/accounts/local_accounts.dart';
import 'package:channel_biseo/features/ai/ai_service.dart';
import 'package:channel_biseo/features/runner/notifier.dart';
import 'package:channel_biseo/features/voice/voice_io.dart';
import 'package:channel_biseo/features/youtube/mock_youtube_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 테스트 중 바뀌는 시계.
class TestClock {
  TestClock([DateTime? start]) : t = start ?? DateTime(2026, 11, 2, 9, 0);
  DateTime t;
  DateTime call() => t;
  void advance(Duration d) => t = t.add(d);
}

/// 실제 인터넷에 절대 나가지 않는 HTTP. 호출되면 테스트가 실패한다.
http.Client noNetwork() => MockClient((req) async {
  throw StateError('테스트 중 실제 네트워크 호출 시도: ${req.url.host}');
});

class TestKit {
  TestKit({
    this.isDesktop = true,
    DateTime? start,
    http.Client? client,
    this.aiProviders,
    List<String> speech = const [],
    MockYouTubeApi? yt,
    this.android = false,
  }) : clock = TestClock(start),
       secrets = MemorySecretStore(),
       speaker = FakeSpeaker(),
       notifier = MemoryNotifier(),
       speechIn = FakeSpeechInput(speech),
       mockYt = yt ?? MockYouTubeApi(),
       logger = AppLogger(),
       httpClient = client ?? noNetwork();

  final bool isDesktop;
  final TestClock clock;
  final MemorySecretStore secrets;
  final FakeSpeaker speaker;
  final MemoryNotifier notifier;
  final FakeSpeechInput speechIn;
  final MockYouTubeApi mockYt;
  final AppLogger logger;
  final http.Client httpClient;
  final Map<String, AiProvider>? aiProviders;

  late final AppEnv env = AppEnv(
    baseDir: Directory.systemTemp.createTempSync('cb_test').path,
    documentsDir: Directory.systemTemp.createTempSync('cb_docs').path,
    secrets: secrets,
    httpClient: httpClient,
    logger: logger,
    speech: speechIn,
    speaker: speaker,
    notifier: notifier,
    isDesktop: isDesktop,
    platformName: 'test',
    appVersion: '0.0.0+test',
    launchUrl: (u) async => true,
    now: clock.call,
    inMemoryDb: true,
    mockYouTube: mockYt,
    aiProviders: aiProviders,
    pickFile: (_) async => pickResult,
    osName: android ? 'android' : 'windows',
    setLauncherIcon: android ? (id) async => launcherIcons.add(id) : null,
    pinShortcut: android
        ? (label, png) async {
            shortcuts.add((label, png.length));
            return true;
          }
        : null,
    pickDirectory: () async => null,
  );

  /// 파일 고르기 창에서 고른 것처럼 돌려줄 경로.
  String? pickResult;

  /// 안드로이드 흉내: 홈 화면 아이콘 바꾸기·바로가기 기록
  final bool android;
  final List<String> launcherIcons = [];
  final List<(String, int)> shortcuts = [];

  Future<UserContext> user([String name = '테스트']) async {
    final u = env.accounts.create(name, '1234');
    return UserContext.open(env, u);
  }

  Future<UserContext> userWithChannels() async {
    final u = await user();
    await u.youtube.connectGoogle();
    for (final c in u.youtube.channels()) {
      await u.youtube.syncChannel(c.channelId);
    }
    return u;
  }
}

LocalUser fakeUser(int id) => LocalUser(id, 'u$id');
