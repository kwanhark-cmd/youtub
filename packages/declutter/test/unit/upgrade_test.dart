import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:binugi/core/clock.dart';
import 'package:binugi/data/database.dart';
import 'package:binugi/data/models.dart';
import 'package:binugi/services/data_location.dart';
import 'package:binugi/services/secret_store.dart';
import 'package:binugi/services/update_service.dart';
import 'package:binugi/state/app_state.dart';
import 'package:binugi/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../helpers.dart';

/// 이전 버전(1.0.0) 앱이 실제로 만든 자료 위에 새 버전을 올려 봄
Future<Directory> unpackOldData() async {
  final dir = await Directory.systemTemp.createTemp('upgrade_');
  final zip = ZipDecoder().decodeBytes(File('test/fixtures/v1_0_0_자료.zip').readAsBytesSync());
  await extractArchiveToDisk(zip, dir.path);
  return dir;
}

void main() {
  test('업데이트: 이전 버전 자료(물건 41개·사진·사연·판매 상태·설정·열쇠)가 그대로 남음', () async {
    final dir = await unpackOldData();
    final dbFile = p.join(dir.path, 'binugi.db');
    final secrets = MemorySecretStore();
    final (s, _) = await makeState(root: dir, dbPath: dbFile, secrets: secrets, clock: FakeClock(DateTime(2026, 11, 1, 9)));

    // 자료 버전이 새것으로 바뀜
    expect(await s.repo.db.getVersion(), dataVersion);
    // 변환 전 자동 백업 (사진 포함)
    expect(s.preUpgradeBackup, isNotNull);
    final backup = ZipDecoder().decodeBytes(s.preUpgradeBackup!.readAsBytesSync());
    expect(backup.files.where((f) => f.name.startsWith('사진/')).length, 41);
    final data = jsonDecode(utf8.decode(backup.findFile('data.json')!.content)) as Map;
    expect((data['items'] as List).length, 41);
    expect(utf8.decode(backup.findFile('data.json')!.content), isNot(contains('sk-ant')), reason: '백업에 열쇠 없음');

    // 물건·사진·사연·판매 상태
    final items = await s.repo.items(s.uid);
    expect(items.length, 40);
    expect(items.every((i) => i.photoPath != null && File(s.paths.abs(i.photoPath!)).existsSync()), isTrue);
    expect(items.where((i) => i.story.contains('소중한 기억')).length, 4);
    expect(items.where((i) => i.decision == Decision.sell).length, 10);
    expect(items.where((i) => i.saleStatus == SaleStatus.sold).length, 5);
    expect(items.where((i) => i.decision == Decision.discard).length, 10);
    expect(items.firstWhere((i) => i.name == '물건 5').price, 15000);
    expect((await s.repo.shots(s.uid)).length, 1);
    expect(s.users.length, 2, reason: '다른 사용자도 남음');

    // 설정·열쇠
    expect(s.global.onboarded, isTrue, reason: '마법사 다시 안 나옴');
    expect(s.global.textSize, TextSizeChoice.huge);
    expect(s.global.theme, ThemeModeChoice.dark);
    expect(s.user.sigungu, '마포구');
    expect(s.user.dailyHour, 7);
    expect(s.user.apiKey, 'sk-ant-old-version-key');
    expect(secrets.values[apiKeyName(s.uid)], 'sk-ant-old-version-key', reason: '열쇠는 보안 저장소로 옮김');
    expect(await s.repo.getSetting(s.uid, 'apiKey'), isNull, reason: 'DB에서는 지움');

    // 한 번 더 열어도(두 번째 업데이트) 그대로
    await s.repo.db.close();
    final (t, _) = await makeState(root: dir, dbPath: dbFile, secrets: secrets);
    expect(t.preUpgradeBackup, isNull, reason: '변환할 게 없으면 백업 안 함');
    expect((await t.repo.items(t.uid)).length, 40);
    expect(t.user.apiKey, 'sk-ant-old-version-key');
  });

  test('맥 예전 자료 폴더(샌드박스)에서 1회 자동 이전', () async {
    final legacy = await unpackOldData();
    final newRoot = Directory(p.join((await Directory.systemTemp.createTemp('new_')).path, 'binugi'));
    expect(await migrateLegacyData(newRoot, legacyRoot: legacy), isTrue);
    expect(File(p.join(newRoot.path, 'binugi.db')).existsSync(), isTrue);
    expect(Directory(p.join(newRoot.path, '사진')).listSync().length, 41);
    expect(await migrateLegacyData(newRoot, legacyRoot: legacy), isFalse, reason: '두 번 옮기지 않음');
    final (s, _) = await makeState(root: newRoot, dbPath: p.join(newRoot.path, 'binugi.db'));
    expect((await s.repo.items(s.uid)).length, 40);
  });

  test('자동 백업에서 되살리기', () async {
    final (s, _) = await makeState();
    final ph = await s.savePhoto(fakeJpeg(w: 200, h: 150));
    await s.addItem(name: '되살릴 물건', photo: ph);
    final b = await s.backup.createSafetyBackup('시험', appVersion: appVersion);
    await s.resetAll();
    expect(s.items, isEmpty);
    await s.backup.restoreSafetyBackup(b);
    await s.reloadAfterRestore();
    expect(s.items.single.name, '되살릴 물건');
  });

  test('첫 실행 마법사: 처음이면 나오고, 쓰던 자료가 있으면 건너뜀', () async {
    final (s, _) = await makeState();
    expect(s.global.onboarded, isFalse);
    await s.addItem(name: '물건');
    await s.startup();
    expect(s.global.onboarded, isTrue);
  });

  test('버전 비교와 기기별 설치 파일 고르기', () {
    expect(compareVersions('v1.2.0', '1.1.9'), greaterThan(0));
    expect(compareVersions('1.1.0', '1.1.0+2'), 0);
    expect(compareVersions('1.0.9', '1.1.0'), lessThan(0));
    final names = ['binugi-android.apk', 'binugi-windows-setup.exe', 'binugi-macos.zip', 'binugi-linux.tar.gz'];
    expect(pickAssetName(names, 'android'), 'binugi-android.apk');
    expect(pickAssetName(names, 'windows'), 'binugi-windows-setup.exe');
    expect(pickAssetName(names, 'macos'), 'binugi-macos.zip');
    expect(pickAssetName(names, 'linux'), 'binugi-linux.tar.gz');
  });

  test('앱 버전 표시가 pubspec 버전과 같음', () {
    final v = RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(appVersion, v);
  });

  test('업데이트 확인: 새 버전이면 알림, 같거나 없으면 조용히', () async {
    Map<String, Object?> release(String tag) => {
      'tag_name': tag,
      'body': '- 화면이 더 보기 쉬워졌어요',
      'assets': [
        {'name': 'binugi-android.apk', 'browser_download_url': 'https://example.com/a.apk', 'size': 10},
        {'name': 'binugi-linux.tar.gz', 'browser_download_url': 'https://example.com/l.tgz', 'size': 10},
      ],
    };
    var tag = 'v9.0.0';
    final client = MockClient((req) async {
      expect(req.url.host, 'api.github.com');
      return http.Response.bytes(utf8.encode(jsonEncode(release(tag))), 200);
    });
    final (s, dir) = await makeState(httpClient: client);
    final svc = UpdateService(client: client, paths: s.paths, currentVersion: '1.1.0', os: 'android');
    final info = await svc.check();
    expect(info!.version, '9.0.0');
    expect(info.assetName, 'binugi-android.apk');
    expect(info.notes, contains('보기 쉬워'));
    tag = 'v1.1.0';
    expect(await svc.check(), isNull);

    tag = 'v9.0.0';
    await s.quietUpdateCheck();
    expect(s.hasUpdate, isTrue, reason: '홈에 "새 버전 있어요" 배지');
    final none = MockClient((_) async => http.Response('{}', 404));
    expect(await UpdateService(client: none, paths: s.paths, currentVersion: '1.1.0').check(), isNull);
    expect(dir.existsSync(), isTrue);
  });

  test('업데이트 내려받기: 진행률', () async {
    final client = MockClient.streaming(
      (req, _) async => http.StreamedResponse(Stream.fromIterable([List.filled(50, 1), List.filled(50, 2)]), 200, contentLength: 100),
    );
    final (s, _) = await makeState(httpClient: client);
    final svc = UpdateService(client: client, paths: s.paths, currentVersion: '1.1.0', os: 'android');
    final progress = <double>[];
    final f = await svc.download(
      UpdateInfo(version: '2.0.0', notes: '', assetName: 'binugi-android.apk', assetUrl: 'https://example.com/a.apk', assetSize: 100),
      onProgress: progress.add,
    );
    expect(f.lengthSync(), 100);
    expect(progress.last, 1);
  });
}
