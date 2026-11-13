import 'dart:convert';
import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/app/assistant_state.dart';
import 'package:personal_assistant/ui/assistant_app.dart';
import 'package:personal_assistant/ui/settings_screen.dart';

import 'support.dart';

/// 가짜 GitHub: releases/latest 가 [tag] 를 돌려준다 (null 이면 404).
UpdateChecker Function() fakeRelease(String? tag, {bool withApk = true}) => () => UpdateChecker(
      repo: releaseRepo,
      currentVersion: appVersion,
      client: MockClient((r) async {
        if (tag == null) return http.Response('{"message":"Not Found"}', 404);
        return http.Response(
          jsonEncode({
            'tag_name': tag,
            'body': '',
            'assets': [
              if (withApk) {'name': androidAsset, 'browser_download_url': 'https://github.com/$releaseRepo/releases/download/$tag/$androidAsset'},
              {'name': 'gaein-biseo-windows.zip', 'browser_download_url': 'https://github.com/$releaseRepo/releases/download/$tag/gaein-biseo-windows.zip'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('upd'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('안내 글', () {
    test('안드로이드: 백업이 맨 먼저, 그다음 받기 → 지우기 → 설치 → 되살리기', () {
      final s = updateSteps(android: true);
      final backup = s.indexOf('① 먼저 백업');
      final get = s.indexOf('② ');
      final delete = s.indexOf('③ 기존 개인비서 앱을 지워요');
      final install = s.indexOf('④ ');
      final restore = s.indexOf('⑤ ');
      expect(backup, greaterThan(0));
      expect([backup, get, delete, install, restore], orderedEquals([...[backup, get, delete, install, restore]]..sort()));
      expect(s, contains('앱 안 자료도 함께 지워지니'));
      expect(s, contains('앱 밖'));
      expect(s, contains('백업에서 되살리기'));
      // "자료가 그대로 남는다"는 약속은 안드로이드에서 하지 않는다.
      expect(s, isNot(contains('그대로 남아요')));
      expect(s, contains('덮어 설치가 안 돼요'));
    });

    test('컴퓨터: 새 파일로 바꾸기, 자료는 사용자 폴더에 남음', () {
      final s = updateSteps(android: false);
      expect(s, contains('사용자 폴더'));
      expect(s, contains('그대로 남아요'));
      expect(s, isNot(contains('지워요')));
    });

    test('받기 주소: 안드로이드는 설치 파일, 없으면·컴퓨터는 공개 페이지', () {
      const info = UpdateInfo(version: '1.1.0', notes: '', assets: {androidAsset: 'https://x/a.apk'});
      expect(updateDownloadUrl(info, android: true), 'https://x/a.apk');
      expect(updateDownloadUrl(info, android: false), releasePage);
      expect(updateDownloadUrl(const UpdateInfo(version: '1.1.0', notes: '', assets: {}), android: true), releasePage);
      expect(releasePage, 'https://github.com/kwanhark-cmd/youtub/releases/latest');
    });
  });

  Future<void> openSettings(WidgetTester t, AssistantState s) async {
    t.view.physicalSize = const Size(720, 1280);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    await s.login(s.auth.create('관학', '1234'));
    await t.pumpWidget(AssistantApp(state: s));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('home-settings')));
    await t.pumpAndSettle();
  }

  Future<void> tapUpdate(WidgetTester t) async {
    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('settings-update')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
  }

  testWidgets('안드로이드에서 새 버전: 백업 먼저 안내 + 설치 파일 받기 (아주 큰 글씨에도 넘침 없음)', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final s = fakeState(tmp)..updateChecker = fakeRelease('v9.0.0');
      s.settings.textSize = TextSize.huge;
      await openSettings(t, s);
      await tapUpdate(t);
      expect(find.text('새 버전 9.0.0'), findsOneWidget);
      expect(find.text(updateSteps(android: true)), findsOneWidget);
      expect(find.textContaining('덮어 설치하면'), findsNothing);
      expect(find.text('설치 파일 받기'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.text('나중에'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('update-steps')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('컴퓨터에서 새 버전: 바꾸기 안내 + 받으러 가기', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final s = fakeState(tmp)..updateChecker = fakeRelease('v9.0.0');
      await openSettings(t, s);
      await tapUpdate(t);
      expect(find.text(updateSteps(android: false)), findsOneWidget);
      expect(find.text('받으러 가기'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('같은 버전이거나 아직 Releases 가 없으면 "최신"', (t) async {
    final s = fakeState(tmp)..updateChecker = fakeRelease('v$appVersion');
    await openSettings(t, s);
    await tapUpdate(t);
    expect(find.text('지금이 최신 버전이에요.'), findsOneWidget);
    expect(find.byKey(const Key('update-steps')), findsNothing);
    s.updateChecker = fakeRelease(null);
    await t.pumpAndSettle(const Duration(seconds: 5));
    await tapUpdate(t);
    expect(find.text('지금이 최신 버전이에요.'), findsWidgets);
  });

  test('앱이 아는 버전(appVersion)은 pubspec.yaml 의 version 과 같다', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    final v = RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(pub)!.group(1);
    expect(appVersion, v, reason: 'pubspec.yaml 버전을 올렸으면 lib/app/assistant_state.dart 의 appVersion 도 같이 올려야 해요');
  });
}
