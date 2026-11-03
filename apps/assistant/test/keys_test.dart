import 'dart:convert';

import 'package:assistant_core/assistant_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/app/keys.dart';

void main() {
  const json = '{"installed":{"client_id":"123-abc.apps.googleusercontent.com","client_secret":"GOCSPX-xyz","redirect_uris":["http://localhost"]}}';

  test('구글 데스크톱 앱 JSON 하나로 열쇠 저장', () async {
    final k = SharedKeys(MemorySecrets());
    expect(await k.hasGoogle(), isFalse);
    expect(await k.setGoogleJson('{"web":{"client_id":"x"}}'), isFalse);
    expect(await k.setGoogleJson('깨진 파일'), isFalse);
    expect(await k.setGoogleJson(json), isTrue);
    final g = (await k.googleClient())!;
    expect(g.clientId, '123-abc.apps.googleusercontent.com');
    expect(g.clientSecret, 'GOCSPX-xyz');
  });

  test('7일 만료 계산', () async {
    final sec = MemorySecrets();
    final k = SharedKeys(sec);
    await k.setGoogleJson(json);
    expect(await k.googleDaysLeft(), isNull);
    await k.markGoogleConnected(at: DateTime(2026, 1, 1));
    expect(await k.googleDaysLeft(now: DateTime(2026, 1, 5)), 3);
    expect(await k.googleDaysLeft(now: DateTime(2026, 1, 9)), -1);
    expect(jsonDecode((await sec.read(SharedKeys.google))!)['client_secret'], 'GOCSPX-xyz');
  });

  test('AI 열쇠 하나', () async {
    final k = SharedKeys(MemorySecrets());
    expect(await k.ai(), isNull);
    await k.setAi('claude', '  sk-ant-test  ');
    expect((await k.ai())!.key, 'sk-ant-test');
    expect((await k.ai())!.provider, 'claude');
  });
}
