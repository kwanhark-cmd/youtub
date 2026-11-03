import 'dart:convert';
import 'dart:io';

import 'package:account_vault/app/platform_services.dart' show appVersion;
import 'package:account_vault/core/crypto/vault_crypto.dart';
import 'package:account_vault/logic/update_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('버전 비교', () {
    expect(compareVersions('1.1.0', '1.0.0'), greaterThan(0));
    expect(compareVersions('v1.10.0', '1.9.3'), greaterThan(0));
    expect(compareVersions('1.0.0+3', '1.0.0'), 0);
    expect(compareVersions('1.0.0', '1.0.1'), lessThan(0));
  });

  test('앱 안의 버전 = pubspec 버전', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    final v = RegExp(
      r'^version: ([0-9.]+)',
      multiLine: true,
    ).firstMatch(pub)![1];
    expect(appVersion, v);
  });

  final apkBytes = utf8.encode('fake apk bytes');
  late String apkHash;
  setUpAll(() async => apkHash = await VaultCrypto().sha256Hex(apkBytes));

  http.Client server({String? hash, String? sumsHash}) => MockClient((
    req,
  ) async {
    if (req.url.toString() == releasesApi) {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'tag_name': 'v9.9.9',
            'html_url': 'https://example.com/r',
            'body':
                '## 바뀐 것\n- 테스트\n\n| 파일 | SHA-256 |\n|---|---|\n| account_vault-9.9.9-android.apk | `${hash ?? apkHash}` |',
            'assets': [
              {
                'name': 'account_vault-9.9.9-android.apk',
                'browser_download_url': 'https://dl/apk',
                'size': apkBytes.length,
              },
              {
                'name': 'account_vault-9.9.9-windows-setup.exe',
                'browser_download_url': 'https://dl/exe',
                'size': 1,
              },
              {
                'name': 'SHA256SUMS.txt',
                'browser_download_url': 'https://dl/sums',
                'size': 1,
              },
            ],
          }),
        ),
        200,
      );
    }
    if (req.url.toString() == 'https://dl/sums') {
      return http.Response(
        '${sumsHash ?? hash ?? apkHash}  account_vault-9.9.9-android.apk\n',
        200,
      );
    }
    if (req.url.toString() == 'https://dl/apk') {
      return http.Response.bytes(apkBytes, 200);
    }
    return http.Response('', 404);
  });

  test('최신 버전 정보·기기별 파일·해시 읽기', () async {
    final info = await UpdateChecker(client: server()).latest();
    expect(info.version, '9.9.9');
    expect(info.assetFor('android')!.name, 'account_vault-9.9.9-android.apk');
    expect(info.assetFor('windows')!.name, endsWith('windows-setup.exe'));
    expect(info.assetFor('macos'), isNull);
    expect(info.hashes['account_vault-9.9.9-android.apk'], apkHash);
  });

  test('해시가 맞으면 저장, 다르면 설치 중단(파일 남기지 않음)', () async {
    final dir = Directory.systemTemp.createTempSync('upd');
    addTearDown(() => dir.deleteSync(recursive: true));
    final ok = UpdateChecker(client: server());
    final info = await ok.latest();
    final f = await ok.download(info, info.assetFor('android')!, dir);
    expect(f.readAsBytesSync(), apkBytes);
    f.deleteSync();

    final bad = UpdateChecker(client: server(hash: 'a' * 64));
    final info2 = await bad.latest();
    await expectLater(
      bad.download(info2, info2.assetFor('android')!, dir),
      throwsA(isA<UpdateException>()),
    );
    expect(dir.listSync(), isEmpty);
  });

  test('본문과 SHA256SUMS 의 해시가 다르면 거부', () async {
    final c = UpdateChecker(client: server(sumsHash: 'b' * 64));
    await expectLater(c.latest(), throwsA(isA<UpdateException>()));
  });

  test('해시가 없는 파일은 설치하지 않음', () async {
    final dir = Directory.systemTemp.createTempSync('upd2');
    addTearDown(() => dir.deleteSync(recursive: true));
    final c = UpdateChecker(client: server());
    final info = await c.latest();
    await expectLater(
      c.download(info, info.assetFor('windows')!, dir),
      throwsA(isA<UpdateException>()),
    );
  });

  test('인터넷 오류는 쉬운 안내', () async {
    final c = UpdateChecker(
      client: MockClient((_) async => throw const SocketException('x')),
    );
    await expectLater(c.latest(), throwsA(isA<UpdateException>()));
  });
}
