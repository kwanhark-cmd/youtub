import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/logger.dart';
import '../data/repository.dart';

/// AI 열쇠·구글 비밀번호 같은 비밀 값 보관소.
/// 기본은 운영체제 보안 저장소(안드로이드 키스토어, 맥 키체인, 윈도우 자격 증명, 리눅스 키링).
/// 보안 저장소를 쓸 수 없는 기기에서는 앱 자료(DB)에 보관하고 그 사실을 표시합니다.
abstract class SecretStore {
  bool get isSecure;
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class DeviceSecretStore implements SecretStore {
  final Repository repo;
  final FlutterSecureStorage _s = const FlutterSecureStorage();
  bool _secure = true;
  DeviceSecretStore(this.repo);

  @override
  bool get isSecure => _secure;

  String _dbKey(String k) => 'secret_$k';

  @override
  Future<String?> read(String key) async {
    if (_secure) {
      try {
        return await _s.read(key: key) ?? await repo.getSetting(Repository.globalUser, _dbKey(key));
      } catch (e) {
        log.warn('보안 저장소 읽기 실패, 앱 자료 사용: $e');
        _secure = false;
      }
    }
    return repo.getSetting(Repository.globalUser, _dbKey(key));
  }

  @override
  Future<void> write(String key, String? value) async {
    if (_secure) {
      try {
        if (value == null || value.isEmpty) {
          await _s.delete(key: key);
        } else {
          await _s.write(key: key, value: value);
        }
        await repo.setSetting(Repository.globalUser, _dbKey(key), null);
        return;
      } catch (e) {
        log.warn('보안 저장소 쓰기 실패, 앱 자료 사용: $e');
        _secure = false;
      }
    }
    await repo.setSetting(Repository.globalUser, _dbKey(key), value);
  }
}

/// 테스트용
class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};
  @override
  bool get isSecure => true;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

/// 비밀 값 이름
String apiKeyName(int userId) => 'ai_key_$userId';
String googleSecretName(int userId) => 'google_client_secret_$userId';
String googleRefreshName(int userId) => 'google_refresh_$userId';
