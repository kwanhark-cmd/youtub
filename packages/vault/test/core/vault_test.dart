import 'dart:convert';
import 'dart:io';

import 'package:account_vault/core/clock.dart';
import 'package:account_vault/core/crypto/recovery_code.dart';
import 'package:account_vault/core/crypto/vault_crypto.dart';
import 'package:account_vault/core/vault/vault.dart';
import 'package:flutter_test/flutter_test.dart';

// 테스트용 가짜 값만 사용한다(실제 비밀번호 형태 아님).
const fakePw = 'test-master-phrase-AAA';

class MemoryKeyStore implements DeviceKeyStore {
  final map = <String, List<int>>{};
  @override
  Future<void> delete(String id) async => map.remove(id);
  @override
  Future<List<int>?> read(String id) async => map[id];
  @override
  Future<void> write(String id, List<int> key) async => map[id] = key;
}

class FakeGate implements BiometricGate {
  FakeGate({this.available = true, this.ok = true});
  bool available, ok;
  @override
  Future<bool> authenticate(String reason) async => ok;
  @override
  Future<bool> isAvailable() async => available;
}

void main() {
  late Directory tmp;
  late FixedClock clock;

  VaultStore store() => VaultStore(
    directory: Directory('${tmp.path}/p1'),
    clock: clock,
    newVaultKdf: KdfParams.fastForTests,
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('vault_test');
    clock = FixedClock(DateTime(2026, 11, 3, 9));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('암호화·복호화 왕복', () async {
    final c = VaultCrypto();
    final key = await c.newRandomKey();
    final blob = await c.encrypt(utf8.encode('가짜 데이터'), key, aad: [1, 2]);
    expect(utf8.decode(await c.decrypt(blob, key, aad: [1, 2])), '가짜 데이터');
    // AAD 가 다르면 실패
    expect(
      () => c.decrypt(blob, key, aad: [9]),
      throwsA(isA<VaultCryptoException>()),
    );
    // 다른 키면 실패
    expect(
      () async => c.decrypt(blob, await c.newRandomKey()),
      throwsA(isA<VaultCryptoException>()),
    );
  });

  test('표준 Argon2id 설정으로도 키가 만들어진다', () async {
    final c = VaultCrypto();
    final k1 = await c.deriveKey('abc', List.filled(16, 7), KdfParams.standard);
    final k2 = await c.deriveKey('abc', List.filled(16, 7), KdfParams.standard);
    final k3 = await c.deriveKey('abd', List.filled(16, 7), KdfParams.standard);
    expect(await k1.extractBytes(), await k2.extractBytes());
    expect(await k1.extractBytes(), isNot(await k3.extractBytes()));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('만들기 → 잠그기 → 맞는 비밀번호로 열기', () async {
    final s = store();
    final (session, code) = await s.create(
      profileId: 'p1',
      masterPassword: fakePw,
      initialData: {'hello': '세계'},
    );
    expect(RecoveryCode.isWellFormed(code), isTrue);
    session.lock();
    expect(session.isOpen, isFalse);
    final r = await s.unlockWithPassword(fakePw);
    expect(r, isA<UnlockSuccess>());
    expect((r as UnlockSuccess).session.data['hello'], '세계');
  });

  test('틀린 비밀번호로는 열리지 않고, 반복하면 지연된다', () async {
    final s = store();
    await s.create(profileId: 'p1', masterPassword: fakePw, initialData: {});
    var r = await s.unlockWithPassword('wrong-1');
    expect(r, isA<UnlockWrongSecret>());
    await s.unlockWithPassword('wrong-2');
    r = await s.unlockWithPassword('wrong-3');
    expect((r as UnlockWrongSecret).waitBeforeNext, const Duration(seconds: 5));
    // 지연 중에는 맞는 비밀번호도 시도 불가
    expect(await s.unlockWithPassword(fakePw), isA<UnlockLockedOut>());
    clock.advance(const Duration(seconds: 6));
    expect(await s.unlockWithPassword(fakePw), isA<UnlockSuccess>());
    // 성공하면 실패 횟수 초기화
    expect((await s.readHeader()).failedAttempts, 0);
  });

  test('복구 코드: 열면 새 비밀번호 필수, 이전 코드는 다시 못 씀', () async {
    final s = store();
    final (_, code) = await s.create(
      profileId: 'p1',
      masterPassword: fakePw,
      initialData: {'x': 1},
    );
    final r = await s.unlockWithRecoveryCode(
      code.toLowerCase().replaceAll('-', ' '),
    );
    expect(r, isA<UnlockSuccess>());
    final session = (r as UnlockSuccess).session;
    expect(session.mustResetPassword, isTrue);
    final newCode = await session.completeRecovery('new-master-phrase-BBB');
    expect(newCode, isNot(code));
    expect(await s.unlockWithPassword(fakePw), isA<UnlockWrongSecret>());
    clock.advance(const Duration(minutes: 10));
    expect(await s.unlockWithRecoveryCode(code), isA<UnlockWrongSecret>());
    clock.advance(const Duration(minutes: 10));
    expect(
      await s.unlockWithPassword('new-master-phrase-BBB'),
      isA<UnlockSuccess>(),
    );
    clock.advance(const Duration(minutes: 10));
    expect(await s.unlockWithRecoveryCode(newCode), isA<UnlockSuccess>());
  });

  test('생체 인증: 성공하면 열리고, 실패·취소하면 비밀번호로 넘어간다', () async {
    final s = store();
    final ks = MemoryKeyStore();
    final (session, _) = await s.create(
      profileId: 'p1',
      masterPassword: fakePw,
      initialData: {'a': 'b'},
    );
    expect(await s.unlockWithDevice(ks, FakeGate()), isA<UnlockUnavailable>());
    await session.enableDeviceUnlock(ks);
    expect(await s.unlockWithDevice(ks, FakeGate()), isA<UnlockSuccess>());
    expect(
      await s.unlockWithDevice(ks, FakeGate(ok: false)),
      isA<UnlockUnavailable>(),
    );
    expect(
      await s.unlockWithDevice(ks, FakeGate(available: false)),
      isA<UnlockUnavailable>(),
    );
    ks.map['p1'] = List.filled(32, 0); // 바뀐 기기 키
    expect(await s.unlockWithDevice(ks, FakeGate()), isA<UnlockUnavailable>());
  });

  test('디스크에 비밀번호·평문 데이터가 남지 않는다', () async {
    final s = store();
    final (session, code) = await s.create(
      profileId: 'p1',
      masterPassword: fakePw,
      initialData: {'secret': 'FAKE-SITE-PASSWORD-123'},
    );
    await session.save({'secret': 'FAKE-SITE-PASSWORD-123', 'n': 2});
    for (final f in Directory('${tmp.path}/p1').listSync().whereType<File>()) {
      final text = latin1.decode(f.readAsBytesSync());
      expect(text.contains(fakePw), isFalse, reason: f.path);
      expect(text.contains('FAKE-SITE-PASSWORD-123'), isFalse, reason: f.path);
      expect(
        text.contains(RecoveryCode.normalize(code)),
        isFalse,
        reason: f.path,
      );
    }
  });

  test('본문이 손상되면 직전 저장본으로 복구, 둘 다 손상되면 안전하게 실패', () async {
    final s = store();
    final (session, _) = await s.create(
      profileId: 'p1',
      masterPassword: fakePw,
      initialData: {'v': 1},
    );
    await session.save({'v': 2});
    s.dataFile.writeAsStringSync(
      '{"format":"account-vault-data","blob":{"n":"x"}}',
    );
    final r = await s.unlockWithPassword(fakePw);
    expect(r, isA<UnlockSuccess>());
    expect((r as UnlockSuccess).session.data['v'], 1);
    expect(r.session.openNote, 'restored_prev');
    s.dataFile.writeAsStringSync('garbage');
    s.prevDataFile.writeAsStringSync('garbage');
    expect(await s.unlockWithPassword(fakePw), isA<UnlockCorrupted>());
  });

  test('머리글이 손상되면 열리지 않는다(안전하게 실패)', () async {
    final s = store();
    await s.create(profileId: 'p1', masterPassword: fakePw, initialData: {});
    s.headerFile.writeAsStringSync('{bad');
    expect(await s.unlockWithPassword(fakePw), isA<UnlockCorrupted>());
  });

  test('마스터 비밀번호 변경', () async {
    final s = store();
    final (session, _) = await s.create(
      profileId: 'p1',
      masterPassword: fakePw,
      initialData: {'k': 1},
    );
    expect(await session.verifyMasterPassword(fakePw), isTrue);
    expect(await session.verifyMasterPassword('nope'), isFalse);
    await session.changeMasterPassword('changed-phrase-CCC');
    expect(await s.unlockWithPassword(fakePw), isA<UnlockWrongSecret>());
    clock.advance(const Duration(minutes: 1));
    final r = await s.unlockWithPassword('changed-phrase-CCC');
    expect((r as UnlockSuccess).session.data['k'], 1);
  });

  test('복구 코드 형식', () {
    final c = RecoveryCode.generate();
    expect(c.length, 29);
    expect(
      RecoveryCode.normalize(c.replaceAll('0', 'o')),
      RecoveryCode.normalize(c),
    );
    expect(RecoveryCode.isWellFormed('abc'), isFalse);
  });

  test('지연 시간표', () {
    expect(lockoutDelayFor(2), Duration.zero);
    expect(lockoutDelayFor(3), const Duration(seconds: 5));
    expect(lockoutDelayFor(20), const Duration(seconds: 300));
  });
}
