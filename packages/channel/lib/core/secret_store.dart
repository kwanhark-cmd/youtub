import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 민감 정보(토큰, API 키) 저장소.
/// 실제 앱: OS 보안 저장소 (Keychain / Credential Manager / Android Keystore / libsecret).
/// 테스트: 메모리.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// [prefix] 로 시작하는 키를 모두 지운다 (사용자 초기화, 연결 해제 등).
  Future<void> deletePrefix(String prefix);
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<void> deletePrefix(String prefix) async => data.removeWhere((k, _) => k.startsWith(prefix));
}

class OsSecretStore implements SecretStore {
  OsSecretStore()
    : _s = const FlutterSecureStorage(
        // 맥: 개발자 서명 없이도 동작하도록 기본 키체인 사용
        mOptions: MacOsOptions(usesDataProtectionKeychain: false),
      );

  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);

  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _s.delete(key: key);

  @override
  Future<void> deletePrefix(String prefix) async {
    final all = await _s.readAll();
    for (final k in all.keys) {
      if (k.startsWith(prefix)) await _s.delete(key: k);
    }
  }
}

/// 사용자별 키 앞부분. 다른 사용자의 비밀 정보와 섞이지 않게 항상 이 앞부분을 붙인다.
class UserSecrets {
  UserSecrets(this.store, this.userId);
  final SecretStore store;
  final int userId;

  String _k(String key) => 'u$userId/$key';

  Future<String?> read(String key) => store.read(_k(key));
  Future<void> write(String key, String value) => store.write(_k(key), value);
  Future<void> delete(String key) => store.delete(_k(key));
  Future<void> deletePrefix(String prefix) => store.deletePrefix(_k(prefix));
  Future<void> deleteAll() => store.deletePrefix('u$userId/');
}
