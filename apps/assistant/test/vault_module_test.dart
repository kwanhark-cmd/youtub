import 'dart:io';

import 'package:account_vault/assistant_entry.dart';
import 'package:account_vault/app/app_controller.dart';
import 'package:account_vault/app/services.dart';
import 'package:account_vault/core/crypto/vault_crypto.dart';
import 'package:account_vault/core/vault/vault.dart';
import 'package:account_vault/data/models.dart';
import 'package:assistant_core/assistant_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_assistant/modules/vault_module.dart';

import 'support.dart';

// 모두 가짜 값.
const fakeMaster = 'fake-master-phrase-777';
const fakePw = 'Fake-Tool-PW-9931';
const fakePw2 = 'Other-Fake-PW-4410';

class _KeyStore implements DeviceKeyStore {
  final map = <String, List<int>>{};
  @override
  Future<void> delete(String id) async => map.remove(id);
  @override
  Future<List<int>?> read(String id) async => map[id];
  @override
  Future<void> write(String id, List<int> key) async => map[id] = key;
}

class _Bio implements BiometricGate {
  @override
  Future<bool> authenticate(String reason) async => false;
  @override
  Future<bool> isAvailable() async => false;
}

class _Clip implements ClipboardPort {
  String? v;
  @override
  Future<String?> read() async => v;
  @override
  Future<void> write(String text) async => v = text;
}

class _Notif implements NotificationPort {
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> scheduleReminders(List<DateTime> times) async {}
}

class _Speech implements SpeechPort {
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<bool> listen({required void Function(String) onPartial, required void Function(String) onFinal}) async => false;
  @override
  Future<void> stop() async {}
}

class _Tts implements TtsPort {
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
}

class _Files implements FilePort {
  @override
  Future<String?> openText({List<String> extensions = const []}) async => null;
  @override
  Future<String?> saveText(String name, String content) async => null;
}

class _Launcher implements LauncherPort {
  @override
  Future<bool> open(Uri uri) async => true;
}

class _Screen implements SecureScreenPort {
  @override
  Future<void> setSecure(bool v) async {}
}

class _Haptics implements HapticPort {
  @override
  void success() {}
  @override
  void tap() {}
}

class _Installer implements InstallerPort {
  _Installer(this.dir);
  final Directory dir;
  @override
  String get os => 'linux';
  @override
  Future<Directory> downloadDir() async => dir;
  @override
  Future<String> install(File file) async => '';
}

class _Style implements LauncherStylePort {
  @override
  Future<bool> setStyle(String s) async => true;
}

Future<AppController> makeController(Directory dir) async {
  final scratch = Directory('${dir.path}/tmp')..createSync(recursive: true);
  final services = AppServices(
    dataDir: dir,
    scratchDir: scratch,
    keyStore: _KeyStore(),
    biometric: _Bio(),
    clipboard: _Clip(),
    notifications: _Notif(),
    speech: _Speech(),
    tts: _Tts(),
    files: _Files(),
    launcher: _Launcher(),
    secureScreen: _Screen(),
    haptics: _Haptics(),
    installer: _Installer(scratch),
    launcherStyle: _Style(),
    appVersion: '1.0.0-test',
  );
  final c = AppController(services, kdf: KdfParams.fastForTests);
  await c.init();
  return c;
}

Future<void> fill(AppController c) async {
  final now = c.now();
  await c.mutate((d) {
    d.subscriptions.addAll([
      Subscription(serviceName: '넷플릭스', amount: 17000, nextRenewal: now.add(const Duration(days: 1)), cardLast4: '9999888877776666'),
      Subscription(serviceName: 'ChatGPT', category: 'AI', amount: 29000, nextRenewal: now.add(const Duration(days: 20)), isCancelCandidate: true),
    ]);
    d.credits.addAll([
      CreditItem(serviceName: '힉스필드', amountText: '300 크레딧', expiresAt: now.add(const Duration(days: 3))),
      CreditItem(serviceName: 'Runway', kind: CreditKind.trial, expiresAt: now.add(const Duration(days: 30))),
    ]);
    d.accounts.addAll([
      Account(serviceName: '힉스필드', category: 'AI', loginId: 'fake.user@example.com', password: fakePw, memo: 'recovery: FAKE-RECOVERY-CODE'),
      Account(serviceName: 'Facebook', category: 'SNS', loginId: 'fakefb', password: fakePw2),
    ]);
  });
}

void expectNoSecrets(Iterable<String> texts) {
  for (final t in texts) {
    expect(t.contains(fakePw), isFalse, reason: t);
    expect(t.contains(fakePw2), isFalse, reason: t);
    expect(t.contains('FAKE-RECOVERY-CODE'), isFalse, reason: t);
    expect(t.contains('99998888'), isFalse, reason: t);
    expect(t.contains('fake.user'), isFalse, reason: t);
  }
}

void main() {
  late Directory root;
  late Directory vaultDir;
  late AppController c;
  late VaultModule m;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('vault_module');
    vaultDir = Directory('${root.path}/vault_app')..createSync(recursive: true);
    c = await makeController(vaultDir);
    m = VaultModule(fakeState(root), openController: () async => c, hasProfiles: () async => false);
  });

  tearDown(() {
    c.dispose();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('아직 띄우지 않았고 금고가 없으면: 오늘 할 일 없음, 검색 없음, 음성은 잠김 안내', () async {
    expect(await m.statusLine(), '마스터 비밀번호로 열기');
    expect(await m.today(), isEmpty);
    expect(await m.search('넷플릭스'), isEmpty);
    final r = await m.handle(const VoiceCommand('이번 달 구독료 얼마야?'));
    expect(r!.speak, VaultModule.lockedReply);
    expect(r.openModule, isTrue);
    expect(await m.releaseSecretForTool('힉스필드', (_) async => true), isNull);
  });

  test('잠김: 비밀 없이 안내 한 줄만, 검색·음성·비밀번호 전달 막힘', () async {
    await c.createProfile('테스트', fakeMaster);
    await fill(c);
    await m.lazy.get();
    await c.lock();

    expect(await m.statusLine(), '잠겨 있어요');
    final items = await m.today();
    expect(items, hasLength(1));
    expect(items.single.text, '금고를 열면 만료 임박 구독을 알려 드려요');
    expect(items.single.urgency, lessThan(30));
    expect(await m.search('힉스필드'), isEmpty);
    final r = await m.handle(const VoiceCommand('힉스필드 크레딧 언제 끝나?'));
    expect(r!.speak, VaultModule.lockedReply);
    expect(r.openModule, isTrue);
    var asked = false;
    expect(await m.releaseSecretForTool('힉스필드', (_) async => asked = true), isNull);
    expect(asked, isFalse);
    expect(await m.receive(Suggestion(id: 'h1', kind: LinkKind.hardToVault, from: ModuleId.harddisk, to: ModuleId.vault, title: '넷플릭스 영수증')), isFalse);
  });

  test('열림: 오늘 할 일·검색·음성이 동작하고 비밀번호는 없다', () async {
    await c.createProfile('테스트', fakeMaster);
    await fill(c);
    await m.lazy.get();

    expect(await m.statusLine(), '구독 2개 · 이번 달 46,000원');

    final items = await m.today();
    final texts = items.map((e) => e.text).toList();
    expect(texts, contains('힉스필드 무료 크레딧 300 크레딧 3일 뒤 만료'));
    expect(texts.any((t) => t.startsWith('넷플릭스 내일 결제')), isTrue);
    expect(texts.any((t) => t.contains('Runway')), isFalse, reason: '30일 뒤는 아직');
    final netflix = items.firstWhere((e) => e.text.startsWith('넷플릭스'));
    final higgs = items.firstWhere((e) => e.text.startsWith('힉스필드'));
    expect(netflix.urgency, greaterThan(higgs.urgency), reason: '가까울수록 급함');
    expectNoSecrets(texts);

    final hits = [...await m.search('힉스'), ...await m.search('Higgsfield'), ...await m.search('넷플'), ...await m.search('facebook')];
    expect(hits.map((h) => h.title), containsAll(['힉스필드', '넷플릭스', 'Facebook']));
    expect(hits.firstWhere((h) => h.kind == '구독').subtitle, contains('17,000원'));
    expect(hits.firstWhere((h) => h.kind == '계정' && h.title == '힉스필드').subtitle, contains('@example.com'));
    expectNoSecrets(hits.expand((h) => [h.title, h.subtitle ?? '']));
    expect(await m.search(fakePw), isEmpty, reason: '비밀번호로 검색해도 나오지 않음');

    final money = await m.handle(const VoiceCommand('이번 달 구독료 얼마야?'));
    expect(money!.speak, contains('46,000원'));
    final credit = await m.handle(const VoiceCommand('힉스필드 크레딧 언제 끝나?'));
    expect(credit!.speak, contains('힉스필드'));
    final pw = await m.handle(const VoiceCommand('힉스필드 비밀번호 알려줘'));
    expect(pw!.speak, contains('읽어 드리지 않아요'));
    final change = await m.handle(const VoiceCommand('넷플릭스 해지 후보에 넣어'));
    expect(change!.needsConfirm, isTrue);
    expect(c.data.subscriptions.firstWhere((s) => s.serviceName == '넷플릭스').isCancelCandidate, isFalse, reason: '확인 전엔 바꾸지 않음');
    expectNoSecrets([money.speak, credit.speak, pw.speak, change.speak]);
    expect(change.hasAction, isTrue);
    expect(change.confirmText, contains('넷플릭스'));
    expect(await change.onConfirm!(), '네, 처리했어요.');
    expect(c.data.subscriptions.firstWhere((s) => s.serviceName == '넷플릭스').isCancelCandidate, isTrue, reason: '"네" 뒤에만 바뀜');
  });

  test('음성으로 바꾸기: 묻는 사이 금고가 잠기면 바꾸지 않는다', () async {
    await c.createProfile('테스트', fakeMaster);
    await fill(c);
    await m.lazy.get();
    final change = await m.handle(const VoiceCommand('넷플릭스 해지 후보에 넣어'));
    await c.lock();
    expect(await change!.onConfirm!(), contains('잠겨서 바꾸지 않았어요'));
  });

  test('하드 → 금고: 영수증을 구독 메모에 근거 문서로 붙이고, 잠금 후에도 남는다', () async {
    await c.createProfile('테스트', fakeMaster);
    await fill(c);
    await m.lazy.get();
    final sg = Suggestion(id: 'h1', kind: LinkKind.hardToVault, from: ModuleId.harddisk, to: ModuleId.vault, title: '넷플릭스 결제 영수증 2026-10', files: const ['/fake/receipts/netflix_2026_10.pdf']);
    expect(await m.receive(sg), isTrue);
    expect(await m.receive(sg), isTrue, reason: '두 번 받아도 한 줄만');
    expect(await m.receive(Suggestion(id: 'h2', kind: LinkKind.hardToVault, from: ModuleId.harddisk, to: ModuleId.vault, title: '모르는 가게 계약서')), isFalse);
    expect(await m.receive(Suggestion(id: 'h3', kind: LinkKind.chatsToAll, from: ModuleId.chats, to: ModuleId.vault, title: '넷플릭스')), isFalse);

    await c.lock();
    await c.unlockWithPassword(c.profileList.single, fakeMaster);
    final memo = c.data.subscriptions.firstWhere((s) => s.serviceName == '넷플릭스').memo;
    expect(memo, contains('근거 문서: 넷플릭스 결제 영수증 2026-10'));
    expect('근거 문서'.allMatches(memo), hasLength(1));
  });

  test('금고 → 채널: 승인했을 때만 비밀번호를 건넨다', () async {
    await c.createProfile('테스트', fakeMaster);
    await fill(c);
    await m.lazy.get();
    final asked = <String>[];
    expect(await m.releaseSecretForTool('Higgsfield', (s) async {
      asked.add(s);
      return false;
    }), isNull);
    expect(asked, ['힉스필드']);
    expect(await m.releaseSecretForTool('힉스필드', (_) async => true), fakePw);
    expect(await m.releaseSecretForTool('없는서비스', (_) async => true), isNull);
  });

  test('개인비서 입구(hostedVaultController): 단독 앱 업데이트 카드 숨김', () {
    expect(c.hostedByAssistant, isFalse, reason: '직접 만든 컨트롤러는 단독 앱 기본값');
    final hosted = hostedVaultController(c.services, kdf: KdfParams.fastForTests);
    expect(hosted.hostedByAssistant, isTrue);
  });

  test('개인비서 보기 설정이 열 때 넘어감 (마스터 비밀번호 마법사는 그대로)', () async {
    m.s.settings
      ..textSize = TextSize.huge
      ..themeMode = 'light'
      ..reduceMotion = true;
    await m.open();
    expect(c.settings.textScaleLevel, 2);
    expect(c.settings.themeMode, 'light');
    expect(c.settings.reduceMotion, isTrue);
    m.s.settings
      ..textSize = TextSize.normal
      ..highContrast = true;
    await m.open();
    expect(c.settings.textScaleLevel, 0);
    expect(c.settings.themeMode, 'contrast');
  });
}
