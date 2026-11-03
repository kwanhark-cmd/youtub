import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'log.dart';

/// 비밀 값 저장소 (운영체제 보안 저장소). 시험에서는 [MemorySecrets].
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MemorySecrets implements SecretStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

class OsSecrets implements SecretStore {
  OsSecrets({this.prefix = 'assistant/'});
  final String prefix;
  // 맥: 개발자 서명 없이도 동작하도록 기본 키체인 사용 (1번 앱과 같은 방식)
  final _s = const FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));
  @override
  Future<String?> read(String key) async {
    try {
      return await _s.read(key: '$prefix$key');
    } catch (e) {
      CoreLog.warn('보안 저장소 읽기 실패 ($key): $e');
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) => _s.write(key: '$prefix$key', value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: '$prefix$key');
}

/// 글씨 크기 3단계
enum TextSize { normal, large, huge }

extension TextSizeScale on TextSize {
  double get scale => switch (this) { TextSize.normal => 1.0, TextSize.large => 1.25, TextSize.huge => 1.5 };
  String get label => switch (this) { TextSize.normal => '보통', TextSize.large => '크게', TextSize.huge => '아주 크게' };
}

/// 본체 앱 설정 (사용자 폴더의 settings.json). 모든 모듈에 바로 적용되는 공통 설정을 담는다.
class AppSettings extends ChangeNotifier {
  AppSettings(this.file) {
    _load();
  }
  final File? file;
  Map<String, Object?> _m = {};

  void _load() {
    final f = file;
    if (f == null || !f.existsSync()) return;
    try {
      _m = Map<String, Object?>.from(jsonDecode(f.readAsStringSync()) as Map);
    } catch (e) {
      CoreLog.error('설정 파일을 읽지 못해 기본값으로 시작', e);
      try {
        f.copySync('${f.path}.broken');
      } catch (_) {}
    }
  }

  void _save() {
    final f = file;
    if (f != null) {
      try {
        f.parent.createSync(recursive: true);
        final tmp = File('${f.path}.tmp')..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_m), flush: true);
        tmp.renameSync(f.path);
      } catch (e) {
        CoreLog.error('설정 저장 실패', e);
      }
    }
    notifyListeners();
  }

  T get<T>(String key, T def) {
    final v = _m[key];
    return v is T ? v : def;
  }

  void set(String key, Object? value) {
    _m[key] = value;
    _save();
  }

  Map<String, Object?> get raw => Map.unmodifiable(_m);

  // ---- 공통 보기 설정 ----
  TextSize get textSize => TextSize.values.asNameMap()[get<String>('textSize', 'normal')] ?? TextSize.normal;
  set textSize(TextSize v) => set('textSize', v.name);

  /// system / light / dark
  String get themeMode => get<String>('themeMode', 'system');
  set themeMode(String v) => set('themeMode', v);

  bool get highContrast => get<bool>('highContrast', false);
  set highContrast(bool v) => set('highContrast', v);

  bool get reduceMotion => get<bool>('reduceMotion', false);
  set reduceMotion(bool v) => set('reduceMotion', v);

  String get appName => get<String>('appName', '개인비서');
  set appName(String v) => set('appName', v.trim().isEmpty ? '개인비서' : v.trim());

  // ---- 하드 엔진 ----
  String get engineUrl => get<String>('engineUrl', 'http://127.0.0.1:47810');
  set engineUrl(String v) => set('engineUrl', v.trim());

  // ---- AI 비용 ----
  int get monthlyAiBudgetWon => get<int>('aiBudgetWon', 20000);
  set monthlyAiBudgetWon(int v) => set('aiBudgetWon', v);

  // ---- 모듈 사이 연결 (켜고 끄기, 기본 켜짐) ----
  bool linkOn(String kind) => get<bool>('link.$kind', true);
  void setLink(String kind, bool on) => set('link.$kind', on);
}
