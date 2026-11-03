import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/app_log.dart';

/// 비밀값(암호화 키, AI 연결 키) 보관소.
abstract class KeyStore {
  Future<String?> read(String name);
  Future<void> write(String name, String value);
  Future<void> delete(String name);
}

/// 테스트용 메모리 보관소.
class MemoryKeyStore implements KeyStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String name) async => _m[name];
  @override
  Future<void> write(String name, String value) async => _m[name] = value;
  @override
  Future<void> delete(String name) async => _m.remove(name);
}

/// 운영체제 보안 저장소. 쓸 수 없는 기기에서는 앱 폴더의 파일로 대체합니다.
class SecureKeyStore implements KeyStore {
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  final File fallbackFile;
  bool _useFallback = false;

  SecureKeyStore(this.fallbackFile);

  Future<Map<String, String>> _readFallback() async {
    if (!await fallbackFile.exists()) return {};
    try {
      final raw = jsonDecode(utf8.decode(base64.decode(await fallbackFile.readAsString())));
      return (raw as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeFallback(Map<String, String> m) async {
    await fallbackFile.parent.create(recursive: true);
    await fallbackFile.writeAsString(base64.encode(utf8.encode(jsonEncode(m))));
  }

  @override
  Future<String?> read(String name) async {
    if (!_useFallback) {
      try {
        final v = await _secure.read(key: name);
        if (v != null) return v;
        // 예전에 대체 파일에 저장했던 값이 있을 수 있음
        return (await _readFallback())[name];
      } catch (e) {
        _switchToFallback(e);
      }
    }
    return (await _readFallback())[name];
  }

  @override
  Future<void> write(String name, String value) async {
    if (!_useFallback) {
      try {
        await _secure.write(key: name, value: value);
        return;
      } catch (e) {
        _switchToFallback(e);
      }
    }
    final m = await _readFallback();
    m[name] = value;
    await _writeFallback(m);
  }

  @override
  Future<void> delete(String name) async {
    try {
      if (!_useFallback) await _secure.delete(key: name);
    } catch (e) {
      _switchToFallback(e);
    }
    final m = await _readFallback();
    if (m.remove(name) != null) await _writeFallback(m);
  }

  void _switchToFallback(Object e) {
    _useFallback = true;
    AppLog.warn('보안 저장소를 쓸 수 없어 파일 보관으로 대체', {'error': e.runtimeType.toString()});
  }
}
