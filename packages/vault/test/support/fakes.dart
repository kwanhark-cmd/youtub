import 'dart:io';

import 'package:account_vault/app/app_controller.dart';
import 'package:account_vault/app/services.dart';
import 'package:account_vault/core/clock.dart';
import 'package:account_vault/core/crypto/vault_crypto.dart';
import 'package:account_vault/core/vault/vault.dart';
import 'package:account_vault/data/models.dart';

/// 테스트용 가짜 운영체제 기능. 실제 비밀번호·카드번호는 쓰지 않는다.
class FakeKeyStore implements DeviceKeyStore {
  final map = <String, List<int>>{};
  @override
  Future<void> delete(String id) async => map.remove(id);
  @override
  Future<List<int>?> read(String id) async => map[id];
  @override
  Future<void> write(String id, List<int> key) async => map[id] = key;
}

class FakeBiometric implements BiometricGate {
  bool available = true;
  bool succeed = true;
  @override
  Future<bool> authenticate(String reason) async => succeed;
  @override
  Future<bool> isAvailable() async => available;
}

class FakeClipboard implements ClipboardPort {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String text) async => value = text;
}

class FakeNotifications implements NotificationPort {
  List<DateTime> scheduled = [];
  final shownTexts = <String>[];
  @override
  Future<void> cancelAll() async => scheduled = [];
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> scheduleReminders(List<DateTime> times) async =>
      scheduled = times;
}

class FakeSpeech implements SpeechPort {
  bool available = false;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> listen({
    required void Function(String) onPartial,
    required void Function(String) onFinal,
  }) async => false;
  @override
  Future<void> stop() async {}
}

class FakeTts implements TtsPort {
  final spoken = <String>[];
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async {}
}

class FakeFiles implements FilePort {
  final saved = <String, String>{};
  String? toOpen;
  @override
  Future<String?> openText({List<String> extensions = const []}) async =>
      toOpen;
  @override
  Future<String?> saveText(String name, String content) async {
    saved[name] = content;
    return '/fake/$name';
  }
}

class FakeLauncher implements LauncherPort {
  final opened = <Uri>[];
  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

class FakeSecureScreen implements SecureScreenPort {
  bool? on;
  @override
  Future<void> setSecure(bool v) async => on = v;
}

class FakeHaptics implements HapticPort {
  @override
  void success() {}
  @override
  void tap() {}
}

class FakeInstaller implements InstallerPort {
  final installed = <String>[];
  Directory? dir;
  @override
  String get os => 'android';
  @override
  Future<Directory> downloadDir() async =>
      dir ??= Directory.systemTemp.createTempSync('dl');
  @override
  Future<String> install(File file) async {
    installed.add(file.path);
    return '설치 화면을 열었어요';
  }
}

class FakeLauncherStyle implements LauncherStylePort {
  String? style;
  @override
  Future<bool> setStyle(String s) async {
    style = s;
    return true;
  }
}

class TestRig {
  TestRig._(this.dir, this.services, this.controller);
  final Directory dir;
  final AppServices services;
  final AppController controller;

  FakeClipboard get clipboard => services.clipboard as FakeClipboard;
  FakeBiometric get biometric => services.biometric as FakeBiometric;
  FakeTts get tts => services.tts as FakeTts;
  FakeFiles get files => services.files as FakeFiles;
  FakeNotifications get notifications =>
      services.notifications as FakeNotifications;

  static Future<TestRig> create({Clock? clock, int clipboardSeconds = 30}) =>
      createAt(
        Directory.systemTemp.createTempSync('vault_rig'),
        clock: clock,
        clipboardSeconds: clipboardSeconds,
      );

  /// 이미 있는 자료 폴더(예: 이전 버전 금고)로 앱을 띄운다.
  static Future<TestRig> createAt(
    Directory dir, {
    Clock? clock,
    int clipboardSeconds = 30,
  }) async {
    final scratch = Directory('${dir.path}/tmp')..createSync(recursive: true);
    final services = AppServices(
      dataDir: dir,
      scratchDir: scratch,
      keyStore: FakeKeyStore(),
      biometric: FakeBiometric(),
      clipboard: FakeClipboard(),
      notifications: FakeNotifications(),
      speech: FakeSpeech(),
      tts: FakeTts(),
      files: FakeFiles(),
      launcher: FakeLauncher(),
      secureScreen: FakeSecureScreen(),
      haptics: FakeHaptics(),
      installer: FakeInstaller(),
      launcherStyle: FakeLauncherStyle(),
      appVersion: '1.0.0-test',
    );
    final c = AppController(
      services,
      clock: clock,
      kdf: KdfParams.fastForTests,
      clipboardSeconds: clipboardSeconds,
    );
    await c.init();
    return TestRig._(dir, services, c);
  }

  void dispose() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// 디자인 테스트용 가짜 데이터(모두 가짜 값).
VaultData sampleData(DateTime now) => VaultData(
  subscriptions: [
    Subscription(
      serviceName: 'Claude',
      category: 'AI',
      amount: 2000,
      currency: Currency.usd,
      nextRenewal: now.add(const Duration(days: 2)),
      cardLast4: '1111',
      isCancelCandidate: true,
    ),
    Subscription(
      serviceName: 'ChatGPT',
      category: 'AI',
      amount: 29000,
      nextRenewal: now.add(const Duration(days: 12)),
      lastUsedAt: now.subtract(const Duration(days: 90)),
    ),
    Subscription(
      serviceName: '아주아주긴이름의영상구독서비스프리미엄플랜',
      amount: 1234567,
      cycle: BillingCycle.yearly,
      nextRenewal: now.add(const Duration(days: 40)),
      createdAt: now.subtract(const Duration(days: 100)),
    ),
    Subscription(
      serviceName: 'Figma',
      category: '디자인',
      amount: 1500,
      currency: Currency.usd,
      nextRenewal: now.add(const Duration(days: 5)),
      isPaused: true,
    ),
  ],
  credits: [
    CreditItem(
      serviceName: '힉스필드',
      amountText: '300 크레딧',
      expiresAt: now.add(const Duration(days: 1)),
    ),
    CreditItem(
      serviceName: 'Runway',
      kind: CreditKind.trial,
      expiresAt: now.add(const Duration(days: 6)),
    ),
    CreditItem(
      serviceName: '오래된 보너스',
      kind: CreditKind.bonusCredit,
      expiresAt: now.subtract(const Duration(days: 3)),
    ),
    CreditItem(
      serviceName: '먼 미래',
      expiresAt: now.add(const Duration(days: 90)),
      done: true,
    ),
  ],
  accounts: [
    Account(
      serviceName: 'Facebook',
      category: 'SNS',
      loginId: 'fake.user.with.a.very.long.identifier',
      signupEmail: 'fake.address.long@example.com',
      password: 'Fake-Shared-PW-1',
      passwordChangedAt: now.subtract(const Duration(days: 400)),
      purpose: '가게 홍보 페이지 운영, 동호회 그룹 관리',
    ),
    Account(serviceName: 'X', category: 'SNS', password: 'Fake-Shared-PW-1'),
    Account(serviceName: '카카오톡', category: 'SNS', loginId: 'fake_kakao'),
  ],
);
