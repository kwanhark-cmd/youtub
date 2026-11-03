import 'dart:io';

import 'package:account_vault/core/crypto/vault_crypto.dart';
import 'package:account_vault/core/vault/vault.dart';
import 'package:flutter_test/flutter_test.dart';

class ThrowingGate implements BiometricGate {
  ThrowingGate({this.onAvailable = false, this.onAuth = false});
  final bool onAvailable, onAuth;
  @override
  Future<bool> isAvailable() async =>
      onAvailable ? throw StateError('플러그인 없음') : true;
  @override
  Future<bool> authenticate(String reason) async =>
      onAuth ? throw StateError('인증 오류') : true;
}

class MapStore implements DeviceKeyStore {
  final m = <String, List<int>>{};
  bool throwOnRead = false;
  @override
  Future<void> delete(String id) async => m.remove(id);
  @override
  Future<List<int>?> read(String id) async =>
      throwOnRead ? throw StateError('보안 저장소 오류') : m[id];
  @override
  Future<void> write(String id, List<int> k) async => m[id] = k;
}

void main() {
  late Directory tmp;
  late VaultStore store;
  late MapStore keys;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('bio');
    store = VaultStore(
      directory: Directory('${tmp.path}/p'),
      newVaultKdf: KdfParams.fastForTests,
    );
    keys = MapStore();
    final (s, _) = await store.create(
      profileId: 'p',
      masterPassword: 'fake-master-1',
      initialData: {'a': 1},
    );
    await s.enableDeviceUnlock(keys);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> expectFallback(UnlockResult r) async {
    expect(r, isA<UnlockUnavailable>(), reason: '열리면 안 되고 "비밀번호로"여야 함');
    // 언제나 마스터 비밀번호로는 열린다
    expect(
      await store.unlockWithPassword('fake-master-1'),
      isA<UnlockSuccess>(),
    );
  }

  test('지문 장치 확인 중 플러그인 오류 → 마스터 비밀번호로', () async {
    await expectFallback(
      await store.unlockWithDevice(keys, ThrowingGate(onAvailable: true)),
    );
  });

  test('인증 중 오류 → 마스터 비밀번호로', () async {
    await expectFallback(
      await store.unlockWithDevice(keys, ThrowingGate(onAuth: true)),
    );
  });

  test('보안 저장소 읽기 오류·기기 키 없음 → 마스터 비밀번호로', () async {
    keys.throwOnRead = true;
    await expectFallback(await store.unlockWithDevice(keys, ThrowingGate()));
    keys.throwOnRead = false;
    keys.m.clear(); // 기기 초기화·앱 재설치 등으로 키가 사라진 경우
    await expectFallback(await store.unlockWithDevice(keys, ThrowingGate()));
  });

  test('생체 인증 실패는 비밀번호 실패 횟수(대기)에 들어가지 않음', () async {
    for (var i = 0; i < 5; i++) {
      await store.unlockWithDevice(keys, ThrowingGate(onAuth: true));
    }
    expect((await store.readHeader()).failedAttempts, 0);
  });
}
