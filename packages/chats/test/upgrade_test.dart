import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_chat_organizer/core/app_info.dart';
import 'package:ai_chat_organizer/data/app_database.dart';
import 'package:ai_chat_organizer/data/key_store.dart';
import 'package:ai_chat_organizer/models/models.dart';
import 'package:ai_chat_organizer/parsers/parser_common.dart';
import 'package:ai_chat_organizer/search/query_parser.dart';
import 'package:ai_chat_organizer/services/app_controller.dart';
import 'package:ai_chat_organizer/services/data_location.dart';
import 'package:ai_chat_organizer/services/settings.dart';
import 'package:ai_chat_organizer/services/update_service.dart';
import 'package:ai_chat_organizer/ui/screens/home_screen.dart';
import 'package:ai_chat_organizer/ui/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers/app_harness.dart';

http.Response utf8Json(Object o) =>
    http.Response.bytes(utf8.encode(jsonEncode(o)), 200, headers: {'content-type': 'application/json; charset=utf-8'});

void copyDir(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final e in from.listSync()) {
    final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (e is Directory) {
      copyDir(e, Directory('${to.path}/$name'));
    } else if (e is File) {
      e.copySync('${to.path}/$name');
    }
  }
}

/// 1.0.0으로 만든 실제 자료 폴더를 복사해, 새 버전 코드로 엽니다.
Future<(AppController, Directory)> openV1Data() async {
  final dir = Directory.systemTemp.createTempSync('upgrade');
  copyDir(Directory('test/fixtures/v1_0_0'), dir);
  final keys = MemoryKeyStore();
  final saved = jsonDecode(File('${dir.path}/secure_store.json').readAsStringSync()) as Map<String, dynamic>;
  for (final e in saved.entries) {
    await keys.write(e.key, e.value as String);
  }
  final c = AppController(root: dir, keys: keys, voice: FakeVoice(), autoUpdateCheck: false, loadAsset: fileAsset);
  await c.init();
  return (c, dir);
}

void main() {
  group('업그레이드: 1.0.0 자료 위에 새 버전', () {
    test('설정·열쇠·대화·주제·별표·태그·메모가 모두 남고, 변환 전 백업이 생긴다', () async {
      final (c, dir) = await openV1Data();
      final s = c.session!;
      expect(s.user.name, '할머니');
      expect(s.database.version, AppDatabase.currentVersion);
      final userDir = Directory('${dir.path}/users/${s.user.id}');
      expect(userDir.listSync().any((f) => f.path.contains('data.db.bak-v2-')), isTrue, reason: '변환 전 자동 백업');
      // 설정
      expect(s.settings.fontSize, FontSize.large);
      expect(s.settings.theme, ThemeChoice.dark);
      expect(s.settings.aiMode, AiMode.claude);
      expect(s.settings.onboardingDone, isTrue);
      expect(s.settings.showSamples, isFalse); // 새 설정은 기본값으로 채워짐
      // 열쇠
      expect(await c.hasApiKey(), isTrue);
      // 대화(암호화 본문까지 읽힘)
      expect(s.store.count(), 10);
      final yt = s.store.list().firstWhere((x) => x.title == '유튜브 앱 기획 회의');
      expect(yt.starred, isTrue);
      expect(s.store.tagsOf(yt.id), ['중요']);
      expect((await s.store.notes(yt.id)).single.text, '다음 주에 다시 보기');
      expect((await s.store.messages(yt.id)).length, 4);
      // 주제(사용자가 옮긴 것)
      final jeju = s.store.list().firstWhere((x) => x.title.contains('제주도'));
      expect(s.topics.topicsOf(jeju.id).map((t) => t.name), ['가족 일정']);
      // 1.0.0 샘플은 샘플로 표시됨
      expect(s.store.sampleCount(), 10);
      // 검색 색인도 그대로
      final hits = await s.search.search(QueryParser.parse('일출봉'));
      expect(hits.hits.length, 1);
      c.signOut();
    });

    test('실제 대화가 들어오면 샘플은 자동으로 숨고, 설정에서 다시 보인다', () async {
      final (c, _) = await openV1Data();
      final s = c.session!;
      await s.store.importResults([
        ParseResult(
          source: AiSource.claude,
          conversations: [
            ParsedConversation(
              source: AiSource.claude,
              externalId: 'real-1',
              title: '진짜 대화',
              createdAt: DateTime(2026, 11, 1),
              updatedAt: DateTime(2026, 11, 1),
              messages: const [Message(role: Role.user, text: '진짜 질문')],
            ),
          ],
        ),
      ], fileName: 'real.zip');
      c.applySampleVisibility();
      expect(c.samplesHidden, isTrue);
      expect(s.store.count(), 1);
      expect(s.topics.all().every((t) => t.count == 0 || t.name.isNotEmpty), isTrue);
      c.updateSettings((x) => x.showSamples = true);
      expect(s.store.count(), 11);
      c.signOut();
    });

    testWidgets('이미 설정이 있으면 첫 안내 마법사를 건너뛴다', (tester) async {
      await setScreen(tester, const Size(900, 1400));
      final (c, _) = (await tester.runAsync(openV1Data))!;
      await tester.pumpWidget(appWith(c));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    test('설정 파일만 있고 onboarding 표시가 빠졌어도 대화가 있으면 건너뜀', () async {
      final (c, dir) = await openV1Data();
      final id = c.session!.user.id;
      c.signOut();
      final f = File('${dir.path}/users/$id/settings.json');
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>..remove('onboardingDone');
      f.writeAsStringSync(jsonEncode(j));
      await c.signIn(c.profiles.single);
      expect(c.session!.settings.onboardingDone, isTrue);
      c.signOut();
    });
  });

  group('업데이트 확인·내려받기', () {
    Map<String, dynamic> release(String tag) => {
      'tag_name': tag,
      'body': '- 화면을 새로 꾸몄어요',
      'html_url': 'https://github.com/kwanhark-cmd/2222/releases/tag/$tag',
      'assets': [
        {'name': 'ai-chat-organizer-$tag-android.apk', 'browser_download_url': 'https://x/a.apk', 'size': 5},
        {'name': 'ai-chat-organizer-$tag-windows.zip', 'browser_download_url': 'https://x/w.zip', 'size': 5},
        {'name': 'ai-chat-organizer-$tag-macos.zip', 'browser_download_url': 'https://x/m.zip', 'size': 5},
        {'name': 'ai-chat-organizer-$tag-linux.zip', 'browser_download_url': 'https://x/l.zip', 'size': 5},
      ],
    };

    test('버전 비교', () {
      expect(compareVersions('1.10.0', '1.9.9'), 1);
      expect(compareVersions('v1.1.0', '1.1.0'), 0);
      expect(compareVersions('1.0.0', '1.0.1'), -1);
      expect(compareVersions('1.2', '1.2.0+5'), 0);
    });

    test('새 버전이 있으면 이 기기용 파일을 고른다', () async {
      for (final (platform, file) in [('android', 'a.apk'), ('windows', 'w.zip'), ('macos', 'm.zip'), ('linux', 'l.zip')]) {
        final u = UpdateService(client: MockClient((_) async => utf8Json(release('v9.0.0'))), currentVersion: '1.1.0', platform: platform);
        final info = (await u.check())!;
        expect(info.version, '9.0.0');
        expect(info.downloadUrl, endsWith(file));
        expect(info.notes, contains('새로'));
      }
    });

    test('같은 버전이면 없음, 릴리스가 없으면·인터넷이 없으면 안내', () async {
      final same = UpdateService(client: MockClient((_) async => utf8Json(release('v${AppInfo.version}'))));
      expect(await same.check(), isNull);
      final none = UpdateService(client: MockClient((_) async => http.Response('{}', 404)));
      expect(() => none.check(), throwsA(isA<UpdateError>().having((e) => e.kind, 'kind', UpdateErrorKind.noRelease)));
      final net = UpdateService(client: MockClient((_) async => throw http.ClientException('없음')));
      expect(() => net.check(), throwsA(isA<UpdateError>().having((e) => e.kind, 'kind', UpdateErrorKind.network)));
      final ios = UpdateService(client: MockClient((_) async => utf8Json(release('v9.0.0'))), platform: 'ios');
      expect((await ios.check())!.downloadUrl, isNull);
    });

    test('내려받기와 크기 확인', () async {
      final u = UpdateService(client: MockClient((_) async => http.Response.bytes([1, 2, 3, 4, 5], 200)), platform: 'android');
      final info = const UpdateInfo(version: '9.0.0', notes: '', downloadUrl: 'https://x/a.apk', fileName: 'a.apk', size: 5, pageUrl: '');
      final dir = Directory.systemTemp.createTempSync('dl');
      final f = await u.download(info, dir);
      expect(f.readAsBytesSync(), Uint8List.fromList([1, 2, 3, 4, 5]));
      final bad = const UpdateInfo(version: '9.0.0', notes: '', downloadUrl: 'https://x/a.apk', fileName: 'b.apk', size: 99, pageUrl: '');
      expect(() => u.download(bad, dir), throwsA(isA<UpdateError>()));
    });

    test('업데이트 전 자동 백업이 사용자 폴더에 생긴다', () async {
      final (c, dir) = await openV1Data();
      final b = (await c.backupBeforeUpdate('9.0.0'))!;
      expect(File('${b.path}/data.db').existsSync(), isTrue);
      expect(File('${b.path}/settings.json').existsSync(), isTrue);
      expect(b.path, startsWith(dir.path));
      c.signOut();
    });

    test('하루 한 번 조용히 확인하고 배지를 띄운다', () async {
      final (c, _) = await openV1Data();
      var calls = 0;
      c.updateServiceFactory = () => UpdateService(
        client: MockClient((_) async {
          calls++;
          return utf8Json(release('v9.0.0'));
        }),
      );
      await c.checkForUpdate(silent: true);
      expect(c.hasUpdateBadge, isTrue);
      await c.checkForUpdate(silent: true); // 24시간 안에는 다시 안 함
      expect(calls, 1);
      c.signOut();
    });
  });

  test('자료 폴더 대체 경로는 임시 폴더가 아니다', () {
    expect(DataLocation.fallback(env: {'HOME': '/home/kim'}).path, '/home/kim/.ai_chat_organizer');
    expect(DataLocation.fallback(env: {'APPDATA': r'C:\Users\kim\AppData\Roaming'}).path, contains('AppData'));
  });
}
