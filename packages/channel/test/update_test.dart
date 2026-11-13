import 'dart:convert';
import 'dart:io';

import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/app/services.dart';
import 'package:channel_biseo/core/db.dart';
import 'package:channel_biseo/core/failure.dart';
import 'package:channel_biseo/core/logger.dart';
import 'package:channel_biseo/core/secret_store.dart';
import 'package:channel_biseo/features/runner/notifier.dart';
import 'package:channel_biseo/features/update/update_service.dart';
import 'package:channel_biseo/features/voice/voice_io.dart';
import 'package:channel_biseo/stages.dart';
import 'package:channel_biseo/ui/home_shell.dart';
import 'package:channel_biseo/ui/onboarding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'helpers.dart';

/// 업데이트 방식 검증.
/// test/fixtures/v1.1.0 = 버전 1.1.0 코드로 실제로 만든 사용자 자료 폴더 (자료 버전 5).
/// 만든 방법: test/fixtures/v1.1.0/make_fixture_test.dart.txt
const fixture = 'test/fixtures/v1.1.0';

/// 고정 자료를 임시 폴더로 복사 (원본은 그대로 두기)
String copyFixture() {
  final dst = Directory.systemTemp.createTempSync('cb_upgrade').path;
  for (final f in Directory('$fixture/support').listSync(recursive: true).whereType<File>()) {
    final t = p.join(dst, p.relative(f.path, from: '$fixture/support'));
    Directory(p.dirname(t)).createSync(recursive: true);
    f.copySync(t);
  }
  return dst;
}

int count(String db, String table) {
  final d = sqlite3.open(db, mode: OpenMode.readOnly);
  try {
    return d.select('SELECT COUNT(*) AS n FROM $table').first['n'] as int;
  } finally {
    d.close();
  }
}

/// 새 버전 앱이 예전 자료 폴더를 여는 상황
AppEnv upgradedEnv(
  String base, {
  String version = '1.2.0+7',
  http.Client? client,
  Future<void> Function(File)? install,
}) {
  final secrets = MemorySecretStore();
  // 운영체제 보안 저장소는 업데이트로 바뀌지 않음 (같은 앱 ID) → 그대로 넣어 둠
  (jsonDecode(File('$fixture/secrets.json').readAsStringSync()) as Map).forEach(
    (k, v) => secrets.data[k as String] = v as String,
  );
  return AppEnv(
    baseDir: base,
    documentsDir: Directory.systemTemp.createTempSync('cb_upgrade_docs').path,
    secrets: secrets,
    httpClient: client ?? noNetwork(),
    logger: AppLogger(),
    speech: FakeSpeechInput(const []),
    speaker: FakeSpeaker(),
    notifier: MemoryNotifier(),
    isDesktop: true,
    platformName: 'test',
    appVersion: version,
    launchUrl: (u) async => true,
    now: () => DateTime(2026, 11, 3, 9),
    installUpdate: install,
    osName: 'windows',
  );
}

Map<String, dynamic> releaseJson(String tag, {List<Map<String, dynamic>>? assets}) => {
  'tag_name': tag,
  'body': '- 화면 새 단장\n- 업데이트 확인 버튼',
  'html_url': 'https://github.com/kwanhark-cmd/-/releases/tag/$tag',
  'assets':
      assets ??
      [
        {'name': 'channel-biseo-windows-setup.exe', 'browser_download_url': 'https://x/win.exe', 'size': 4},
        {'name': 'channel-biseo-macos.zip', 'browser_download_url': 'https://x/mac.zip', 'size': 4},
        {'name': 'channel-biseo-android.apk', 'browser_download_url': 'https://x/a.apk', 'size': 4},
        {'name': 'channel-biseo-linux.tar.gz', 'browser_download_url': 'https://x/l.tgz', 'size': 4},
      ],
};

http.Client fakeGithub(Map<String, dynamic>? release, {int status = 200, List<String>? calls}) =>
    MockClient((req) async {
      calls?.add(req.url.toString());
      if (req.url.host == 'api.github.com') {
        if (release == null) return http.Response('', status == 200 ? 404 : status);
        return http.Response(jsonEncode(release), status, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      if (req.url.host == 'x') return http.Response.bytes([1, 2, 3, 4], 200);
      throw StateError('예상하지 못한 주소 ${req.url}');
    });

void main() {
  setUpAll(registerStages);
  identifiersTest();

  group('1.1.0 자료로 새 버전 열기', () {
    test('설정·열쇠·채널·영상·수정 기록·제작·메모가 모두 그대로, 변환 전 백업', () async {
      final base = copyFixture();
      final dbPath = p.join(base, 'users', 'u1', 'data.sqlite');
      final before = {
        for (final t in ['accounts', 'channels', 'videos', 'edits', 'productions', 'memos', 'settings'])
          t: count(dbPath, t),
      };
      expect(before['videos'], greaterThan(0));
      final env = upgradedEnv(base);
      final users = env.accounts.list();
      expect(users.map((e) => e.name), ['김사장']);
      final s = AppState(env);
      await s.login(env.accounts.verify(users.single.id, '1234')!);
      final u = s.user!;
      // 자료 버전 5 → 6
      expect(u.db.version, userDataMigrations.last.version);
      final backups = Directory(p.join(base, 'users', 'u1', 'backups')).listSync().map((e) => p.basename(e.path));
      expect(backups.any((n) => n.contains('-v5-')), isTrue, reason: '변환 전 백업');
      // 설정 그대로
      expect(u.settings.onboardingDone, isTrue);
      expect(u.settings.textScale, 1.5);
      expect(u.settings.themeMode, 'dark');
      expect(u.settings.reduceMotion, isTrue);
      expect(u.settings.haptics, isFalse);
      // 새 설정은 기본값
      expect(u.settings.showPracticeData, isFalse);
      // 연결 열쇠 그대로 (보안 저장소)
      expect(u.ai.hasKey, isTrue);
      // 자료 그대로
      for (final t in before.keys.where((t) => t != 'settings')) {
        expect(u.db.select('SELECT COUNT(*) AS n FROM $t').first['n'], before[t], reason: t);
      }
      expect(u.youtube.channels().length, 3);
      // 버전 기록
      expect(u.db.select('SELECT version FROM app_versions').map((r) => r['version']), ['1.2.0+7']);
      expect(env.logger.recentLines().join('\n'), contains('DB 변환 완료: v6'));
    });

    testWidgets('첫 실행 안내를 다시 보지 않고 바로 홈', (t) async {
      final base = copyFixture();
      final env = upgradedEnv(base);
      final s = AppState(env);
      await s.login(env.accounts.verify(1, '1234')!);
      await t.pumpWidget(ChannelBiseoApp(state: s));
      await t.pumpAndSettle();
      expect(find.byType(OnboardingWizard), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    test('"첫 실행 안내 끝남" 표시가 없어도 쓰던 자료가 있으면 건너뜀', () async {
      final base = copyFixture();
      final d = sqlite3.open(p.join(base, 'users', 'u1', 'data.sqlite'));
      d.execute("DELETE FROM settings WHERE key = 'onboardingDone'");
      d.close();
      final env = upgradedEnv(base);
      final s = AppState(env);
      await s.login(env.accounts.verify(1, '1234')!);
      expect(s.user!.settings.onboardingDone, isTrue);
    });

    test('새로 만든 사용자는 첫 실행 안내를 봄', () async {
      final k = TestKit();
      final u = await k.user();
      expect(u.settings.onboardingDone, isFalse);
    });

    test('같은 버전으로 다시 열면 버전 기록이 늘지 않음, 다음 업데이트는 한 줄 추가', () async {
      final base = copyFixture();
      for (final v in ['1.2.0+7', '1.2.0+7', '1.3.0+8']) {
        final env = upgradedEnv(base, version: v);
        final s = AppState(env);
        await s.login(env.accounts.verify(1, '1234')!);
        s.logout();
      }
      final rows = sqlite3.open(p.join(base, 'users', 'u1', 'data.sqlite')).select('SELECT version FROM app_versions');
      expect(rows.map((r) => r['version']), unorderedEquals(['1.2.0+7', '1.3.0+8']));
    });
  });

  group('업데이트 확인 (GitHub Releases)', () {
    test('버전 비교', () {
      expect(UpdateService.compare('v1.2.0', '1.1.0+6'), greaterThan(0));
      expect(UpdateService.compare('1.1.0', '1.1.0+6'), 0);
      expect(UpdateService.compare('1.0.9', '1.1.0'), lessThan(0));
      expect(UpdateService.compare('1.10.0', '1.9.3'), greaterThan(0));
    });

    test('새 버전 있음 / 같음 / 아직 공개 없음 / 서버 오류', () async {
      Future<ReleaseInfo?> run(http.Client c) =>
          UpdateService(client: c, currentVersion: '1.1.0+6', logger: AppLogger()).check();
      final r = await run(fakeGithub(releaseJson('v1.2.0')));
      expect(r!.version, '1.2.0');
      expect(r.notes, contains('업데이트 확인 버튼'));
      expect(await run(fakeGithub(releaseJson('v1.1.0'))), isNull);
      expect(await run(fakeGithub(null)), isNull);
      await expectLater(run(fakeGithub(null, status: 500)), throwsA(isA<AppFailure>()));
    });

    test('운영체제별 설치 파일 고르기', () {
      final r = ReleaseInfo(
        version: '1.2.0',
        notes: '',
        pageUrl: '',
        assets: [
          for (final a in releaseJson('v1.2.0')['assets'] as List)
            ReleaseAsset(a['name'] as String, a['browser_download_url'] as String, a['size'] as int),
        ],
      );
      expect(UpdateService.assetFor(r, 'windows')!.name, endsWith('windows-setup.exe'));
      expect(UpdateService.assetFor(r, 'macos')!.name, endsWith('macos.zip'));
      expect(UpdateService.assetFor(r, 'android')!.name, endsWith('.apk'));
      expect(UpdateService.assetFor(r, 'linux')!.name, contains('linux'));
      expect(UpdateService.assetFor(r, 'ios'), isNull);
    });

    test('내려받기: 크기가 다르면 실패하고 반쯤 받은 파일을 남기지 않음', () async {
      final svc = UpdateService(client: fakeGithub(null), currentVersion: '1.1.0', logger: AppLogger());
      final dir = Directory.systemTemp.createTempSync('cb_dl').path;
      final f = await svc.download(ReleaseAsset('a.exe', 'https://x/a.exe', 4), dir);
      expect(f.readAsBytesSync(), [1, 2, 3, 4]);
      await expectLater(svc.download(ReleaseAsset('b.exe', 'https://x/b.exe', 9), dir), throwsA(isA<AppFailure>()));
      expect(Directory(dir).listSync().map((e) => p.basename(e.path)), ['a.exe']);
    });

    test('설치 전 백업: 모든 사용자 자료 파일, 옛 백업은 빼고', () {
      final base = copyFixture();
      Directory(p.join(base, 'users', 'u1', 'backups')).createSync(recursive: true);
      File(p.join(base, 'users', 'u1', 'backups', 'old.sqlite')).writeAsStringSync('x');
      final docs = Directory.systemTemp.createTempSync('cb_docs').path;
      final dir = backupAllForUpdate(
        baseDir: base,
        documentsDir: docs,
        fromVersion: '1.1.0',
        now: DateTime(2026, 11, 3),
      );
      final files = Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => p.relative(f.path, from: dir));
      expect(files, unorderedEquals(['users.sqlite', p.join('users', 'u1', 'data.sqlite')]));
      expect(p.split(dir), contains('업데이트-백업'));
    });
  });

  group('설정 → 업데이트 확인 화면', () {
    Future<(AppState, List<String>, List<File>)> open(WidgetTester t, Map<String, dynamic>? release, {bool hosted = false}) async {
      final calls = <String>[];
      final installed = <File>[];
      final base = copyFixture();
      final env = upgradedEnv(
        base,
        version: '1.1.0+6',
        client: fakeGithub(release, calls: calls),
        install: (f) async => installed.add(f),
      );
      final s = AppState(env)..hostedByAssistant = hosted;
      await s.login(env.accounts.verify(1, '1234')!);
      s.user!.settings.reduceMotion = true;
      await t.pumpWidget(ChannelBiseoApp(state: s));
      await t.pumpAndSettle();
      // 앱을 켜고 쓰는 동안에는 스스로 확인·내려받기를 하지 않음
      expect(calls, isEmpty);
      await t.tap(find.byIcon(Icons.settings).last);
      await t.pumpAndSettle();
      return (s, calls, installed);
    }

    testWidgets('새 버전: 안내 → "설치하기"를 눌러야만 백업·내려받기·설치', (t) async {
      final (s, calls, installed) = await open(t, releaseJson('v1.2.0'));
      await t.tap(find.byKey(const Key('update-check')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('update-dialog')), findsOneWidget);
      expect(find.textContaining('그대로예요'), findsOneWidget);
      expect(calls.where((c) => c.contains('x/')), isEmpty, reason: '누르기 전에는 내려받지 않음');
      // 나중에 → 아무것도 안 함
      await t.tap(find.text('나중에'));
      await t.pumpAndSettle();
      expect(installed, isEmpty);
      // 다시 확인 → 설치하기
      await t.tap(find.byKey(const Key('update-check')));
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('update-install')));
        for (var i = 0; i < 50 && installed.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await t.pump();
        }
      });
      await t.pumpAndSettle();
      expect(installed.single.path, endsWith('channel-biseo-windows-setup.exe'));
      final backup = s.user!.lastUpdateBackup!;
      expect(File(p.join(backup, 'users', 'u1', 'data.sqlite')).existsSync(), isTrue);
      expect(File(p.join(backup, 'users.sqlite')).existsSync(), isTrue);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('개인비서 안에서는(hostedByAssistant) 단독 앱 업데이트 확인 버튼이 없음', (t) async {
      final (_, calls, installed) = await open(t, releaseJson('v9.0.0'), hosted: true);
      expect(find.byKey(const Key('update-check')), findsNothing);
      expect(find.byKey(const Key('report-top')), findsOneWidget, reason: '문제 신고는 그대로');
      expect(calls, isEmpty);
      expect(installed, isEmpty);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('최신 버전이면 알려 주기만', (t) async {
      final (_, _, installed) = await open(t, releaseJson('v1.1.0'));
      await t.tap(find.byKey(const Key('update-check')));
      await t.pumpAndSettle();
      expect(find.textContaining('최신 버전'), findsOneWidget);
      expect(installed, isEmpty);
      await t.pumpWidget(const SizedBox());
    });
  });
}

/// 앱 식별자가 바뀌면 업데이트가 "덮어쓰기"가 아니라 다른 앱이 되어 자료·열쇠를 못 찾는다.
/// 이 테스트가 실패하면 식별자를 원래대로 되돌릴 것.
void identifiersTest() {
  // 통합 앱(개인비서) 안에서는 이 패키지에 플랫폼 폴더가 없다. 단독 앱 저장소에서만 확인한다.
  // 통합 앱의 식별자는 apps/assistant/test/identifiers_test.dart 에서 확인한다.
  test('앱 식별자는 바뀌지 않음 (자료 폴더·보안 저장소 위치가 여기서 정해짐)', skip: !File('android/app/build.gradle.kts').existsSync(), () {
    String read(String f) => File(f).readAsStringSync();
    expect(read('android/app/build.gradle.kts'), contains('applicationId = "com.channelbiseo.channel_biseo"'));
    expect(
      read('macos/Runner/Configs/AppInfo.xcconfig'),
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.channelbiseo.channelBiseo'),
    );
    expect(read('macos/Runner/Configs/AppInfo.xcconfig'), contains('PRODUCT_NAME = channel_biseo'));
    expect(read('windows/runner/Runner.rc'), contains('VALUE "CompanyName", "com.channelbiseo"'));
    expect(read('windows/runner/Runner.rc'), contains('VALUE "ProductName", "channel_biseo"'));
    expect(read('windows/CMakeLists.txt'), contains('set(BINARY_NAME "channel_biseo")'));
    expect(read('windows/installer.iss'), contains('AppId={{CD2DFF57-56A7-48BC-9257-59C453116D1F}'));
    expect(read('linux/CMakeLists.txt'), contains('set(APPLICATION_ID "com.channelbiseo.channel_biseo")'));
    expect(read('pubspec.yaml'), contains('name: channel_biseo'));
  });
}
