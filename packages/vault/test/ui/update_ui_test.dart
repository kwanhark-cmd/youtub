import 'dart:convert';
import 'dart:io';

import 'package:account_vault/core/crypto/vault_crypto.dart';
import 'package:account_vault/logic/update_check.dart';
import 'package:account_vault/ui/screens/update_card.dart';
import 'package:account_vault/ui/theme/tokens.dart';
import 'package:account_vault/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fakes.dart';

Future<void> realWait(WidgetTester tester, [int rounds = 20]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('업데이트: 확인 → 자동 백업 → 내려받기 → 해시 확인 → 설치 화면', (tester) async {
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final apk = utf8.encode('fake new apk');
    late String hash;
    late TestRig rig;
    await tester.runAsync(() async {
      hash = await VaultCrypto().sha256Hex(apk);
      rig = await TestRig.create();
      await rig.controller.updateSettings((s) => s.autoLockSeconds = 0);
      await rig.controller.createProfile('a', 'fake-master-phrase-1');
    });
    addTearDown(rig.dispose);
    final client = MockClient((req) async {
      if (req.url.toString() == releasesApi) {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'tag_name': 'v99.0.0',
              'body':
                  '## 바뀐 것\n- 가짜\n\n| account_vault-99.0.0-android.apk | `$hash` |',
              'assets': [
                {
                  'name': 'account_vault-99.0.0-android.apk',
                  'browser_download_url': 'https://dl/apk',
                  'size': apk.length,
                },
              ],
            }),
          ),
          200,
        );
      }
      return http.Response.bytes(apk, 200);
    });
    await tester.pumpWidget(
      AppScope(
        controller: rig.controller,
        child: AppTheme(
          palette: AppPalette.light,
          reduceMotion: true,
          child: MaterialApp(
            home: Scaffold(
              body: ListView(children: [UpdateCard(client: client)]),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('새 버전 확인하기'));
    await realWait(tester);
    expect(find.textContaining('새 버전 99.0.0'), findsOneWidget);
    await tester.tap(find.text('백업하고 내려받아 설치'));
    await realWait(tester, 3);
    expect(find.textContaining('복구 코드가 종이에'), findsOneWidget);
    await tester.tap(find.text('백업하고 내려받기'));
    await realWait(tester, 30);
    final installer = rig.services.installer as FakeInstaller;
    expect(
      installer.installed.single,
      endsWith('account_vault-99.0.0-android.apk'),
    );
    final backups = Directory('${rig.dir.path}/store/auto_backups').listSync();
    expect(backups.single.path, contains('before-update-99.0.0'));
    expect(tester.takeException(), isNull);
  });
}
