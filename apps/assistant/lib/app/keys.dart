import 'dart:convert';

import 'package:assistant_core/assistant_core.dart';

/// 하나의 열쇠 보관함: 구글 열쇠 하나(유튜브·블로거·지메일·캘린더·주소록), AI 열쇠 하나, 도구 열쇠.
/// 운영체제 보안 저장소에만 둔다. 로그·백업(비암호화)·음성·검색에 절대 나가지 않는다.
class SharedKeys {
  SharedKeys(this.secrets);
  final SecretStore secrets;

  static const google = 'key.google.client';
  static const aiKey = 'key.ai';
  static const aiProvider = 'key.ai.provider';
  static const higgsfield = 'key.tool.higgsfield';
  static const figma = 'key.tool.figma';

  /// 구글 콘솔에서 받은 JSON("데스크톱 앱" 클라이언트)에서 client_id·secret 을 꺼낸다.
  static ({String clientId, String clientSecret})? parseGoogleJson(String raw) {
    try {
      final j = jsonDecode(raw) as Map;
      final inner = (j['installed'] ?? j['web'] ?? j) as Map;
      final id = '${inner['client_id'] ?? ''}'.trim();
      final secret = '${inner['client_secret'] ?? ''}'.trim();
      if (!id.endsWith('.apps.googleusercontent.com') || secret.isEmpty) return null;
      return (clientId: id, clientSecret: secret);
    } catch (_) {
      return null;
    }
  }

  Future<bool> setGoogleJson(String raw) async {
    final g = parseGoogleJson(raw);
    if (g == null) return false;
    await secrets.write(google, jsonEncode({'client_id': g.clientId, 'client_secret': g.clientSecret, 'saved': DateTime.now().toIso8601String()}));
    CoreLog.info('구글 열쇠 저장됨');
    return true;
  }

  Future<({String clientId, String clientSecret})?> googleClient() async {
    final v = await secrets.read(google);
    if (v == null) return null;
    final j = jsonDecode(v) as Map;
    return (clientId: '${j['client_id']}', clientSecret: '${j['client_secret']}');
  }

  /// 구글 "테스트" 앱은 연결이 7일 뒤 만료된다. 저장한 날 기준 남은 날.
  Future<int?> googleDaysLeft({DateTime? now}) async {
    final v = await secrets.read(google);
    if (v == null) return null;
    final saved = DateTime.tryParse('${(jsonDecode(v) as Map)['connected'] ?? ''}');
    if (saved == null) return null;
    return 7 - (now ?? DateTime.now()).difference(saved).inDays;
  }

  Future<void> markGoogleConnected({DateTime? at}) async {
    final v = await secrets.read(google);
    if (v == null) return;
    final j = Map<String, Object?>.from(jsonDecode(v) as Map)..['connected'] = (at ?? DateTime.now()).toIso8601String();
    await secrets.write(google, jsonEncode(j));
  }

  Future<bool> hasGoogle() async => (await googleClient()) != null;

  Future<void> setAi(String provider, String key) async {
    await secrets.write(aiProvider, provider);
    await secrets.write(aiKey, key.trim());
  }

  Future<({String provider, String key})?> ai() async {
    final k = await secrets.read(aiKey);
    if (k == null || k.isEmpty) return null;
    return (provider: await secrets.read(aiProvider) ?? 'claude', key: k);
  }

  Future<bool> hasAi() async => (await ai()) != null;

  Future<bool> has(String name) async => ((await secrets.read(name)) ?? '').isNotEmpty;
  Future<void> set(String name, String v) => secrets.write(name, v.trim());
}
