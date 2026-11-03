import 'dart:io';

import 'package:binugi/core/clock.dart';
import 'package:binugi/data/database.dart';
import 'package:binugi/data/models.dart';
import 'package:binugi/services/video_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers.dart';

void main() {
  test('데이터 버전 1 → 2 자동 변환 (기존 물건 유지)', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('mig');
    final path = p.join(dir.path, 'm.db');
    final v1 = await openAppDatabase(databaseFactoryFfiNoIsolate, path, version: 1);
    await v1.insert('items', {'user_id': 1, 'name': '오래된 물건', 'created_at': 1});
    await v1.close();
    final v2 = await openAppDatabase(databaseFactoryFfiNoIsolate, path);
    expect(await v2.getVersion(), dataVersion);
    final rows = await v2.query('items');
    expect(rows.single['name'], '오래된 물건');
    expect(rows.single['digital_keep'], 0);
    await v2.query('timelapse');
    await v2.close();
  });

  test('사용자마다 자료가 분리됨', () async {
    final (s, _) = await makeState();
    final first = s.uid;
    await s.addItem(name: '내 물건');
    await s.addUser('엄마');
    expect(s.uid, isNot(first));
    expect(s.items, isEmpty, reason: '다른 사용자 자료는 보이지 않음');
    await s.addItem(name: '엄마 물건');
    expect(await s.repo.items(first), hasLength(1));
    expect((await s.repo.items(first)).single.name, '내 물건');
    expect(await s.repo.item(s.uid, (await s.repo.items(first)).single.id!), isNull, reason: '다른 사용자 id로 꺼낼 수 없음');
    await s.switchUser(first);
    expect(s.items.single.name, '내 물건');
  });

  test('사진은 줄여서 저장, 원본은 선택 시에만', () async {
    final (s, dir) = await makeState();
    final saved = await s.savePhoto(fakeJpeg(w: 4000, h: 3000));
    expect(saved.width, 1568);
    expect(saved.originalPath, isNull);
    final thumb = img.decodeJpg(await File(s.paths.abs(saved.thumbPath)).readAsBytes())!;
    expect(thumb.width, 300);
    s.user.keepOriginals = true;
    final kept = await s.savePhoto(fakeJpeg(w: 800, h: 600), ext: '.jpg');
    expect(kept.originalPath, isNotNull);
    expect(File(s.paths.abs(kept.originalPath!)).existsSync(), isTrue);
    expect(dir.existsSync(), isTrue);
  });

  test('영상 장면 뽑기: 진행률·취소', () async {
    final ext = FakeExtractor(5);
    final (s, _) = await makeState(extractor: ext);
    final progress = <double>[];
    final frames = await s.video.extractFrames('/가짜/영상.mp4', onProgress: progress.add);
    expect(frames.length, 5);
    expect(progress.last, 1);
    final cancel = CancelToken()..cancel();
    expect(await s.video.extractFrames('/가짜/영상.mp4', cancel: cancel), isEmpty);
  });

  test('백업·복원: 사진 포함, 비밀번호 틀리면 거부, AI 키는 백업에 안 들어감', () async {
    final (s, _) = await makeState();
    s.user.apiKey = 'sk-ant-SECRET';
    await s.saveUser();
    final photo = await s.savePhoto(fakeJpeg(w: 400, h: 300));
    await s.addItem(name: '백업할 물건', photo: photo, decision: Decision.sell);
    final bytes = await s.backup.createBytes('1234', appVersion: 't');
    expect(String.fromCharCodes(bytes).contains('SECRET'), isFalse);

    final (t, _) = await makeState();
    await expectLater(t.backup.restoreBytes(bytes, '틀림'), throwsA(anything));
    t.user.apiKey = 'sk-ant-MINE';
    await t.saveUser();
    await t.backup.restoreBytes(bytes, '1234');
    await t.reloadAfterRestore();
    final it = t.items.single;
    expect(it.name, '백업할 물건');
    expect(File(t.paths.abs(it.photoPath!)).existsSync(), isTrue, reason: '사진도 복원');
    expect(t.user.apiKey, 'sk-ant-MINE', reason: '이 기기의 키는 지킴');
  });

  test('사연·디지털 기록 내보내기 폴더', () async {
    final (s, _) = await makeState();
    final photo = await s.savePhoto(fakeJpeg(w: 200, h: 150));
    final it = await s.addItem(name: '여행 기념품', photo: photo);
    final dir = await s.saveStory(it, '제주도에서 산 기념품');
    expect(File(p.join(dir.path, '사진.jpg')).existsSync(), isTrue);
    expect(File(p.join(dir.path, '사연.txt')).readAsStringSync(), contains('제주도'));
    expect(dir.path, contains('1번앱_사연'));
    final d2 = await s.keepDigitallyAndDiscard(it);
    expect(d2.path, contains('3번앱_디지털기록'));
    expect((await s.repo.item(s.uid, it.id!))!.decision, Decision.discard);
  });

  test('타임랩스 움직이는 그림 만들기', () async {
    final (s, _) = await makeState();
    final paths = <String>[];
    for (var i = 0; i < 3; i++) {
      paths.add((await s.savePhoto(fakeJpeg(w: 320, h: 240, seed: i))).photoPath);
    }
    final f = await s.timelapse.makeGif(paths, spot: '거실', side: 120);
    expect(f.path, contains('1번앱_타임랩스'));
    final gif = img.decodeGif(await f.readAsBytes())!;
    expect(gif.numFrames, 3);
  });

  test('밀린 알림: 아침 알림 시각이 지나면 앱 안 알림이 생김 (하루 한 번)', () async {
    final clock = FakeClock(DateTime(2026, 3, 1, 7));
    final (s, _) = await makeState(clock: clock);
    await s.addItem(name: '정할 물건');
    await s.runDailyChecks();
    expect((await s.repo.notices(s.uid)).where((n) => n.kind == 'daily'), isEmpty, reason: '8시 전');
    clock.advance(const Duration(hours: 2));
    await s.runDailyChecks();
    await s.runDailyChecks();
    expect((await s.repo.notices(s.uid)).where((n) => n.kind == 'daily').length, 1);
  });

  test('초기화는 모든 자료를 지움', () async {
    final (s, _) = await makeState();
    await s.addItem(name: '지울 물건', photo: await s.savePhoto(fakeJpeg(w: 100, h: 100)));
    await s.resetAll();
    expect(s.items, isEmpty);
    expect(s.global.onboarded, isFalse);
  });
}
