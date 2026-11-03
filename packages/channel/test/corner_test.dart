import 'dart:convert';
import 'dart:io';

import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/app/services.dart';
import 'package:channel_biseo/core/failure.dart';
import 'package:channel_biseo/features/ai/brain.dart';
import 'package:channel_biseo/features/corner/material_source.dart';
import 'package:channel_biseo/features/production/production_service.dart';
import 'package:channel_biseo/stages.dart';
import 'package:channel_biseo/ui/corner_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<(TestKit, UserContext)> setup() async {
  registerStages();
  final k = TestKit();
  final state = AppState(k.env);
  await state.login(k.env.accounts.create('코너', '1234'));
  final u = state.user!;
  await u.youtube.connectGoogle();
  u.settings.produceDailyLimit = 10;
  return (k, u);
}

String tmpFile(String dir, String name, [String content = 'x']) {
  final f = File('$dir/$name')..writeAsStringSync(content);
  return f.path;
}

void main() {
  test('저작권 의심 파일 이름 짐작', () {
    expect(looksCopyrighted('/a/아이유 MV 4K.mp4'), isTrue);
    expect(looksCopyrighted('/a/드라마_1화.mp4'), isTrue);
    expect(looksCopyrighted('/a/youtube_download.mp4'), isTrue);
    expect(looksCopyrighted('/a/우리집 강아지 산책.mp4'), isFalse);
    expect(looksCopyrighted('/a/IMG_2034.MOV'), isFalse);
  });

  test('폴더에서 소재 가져오기: manifest.json 이 있으면 설명·저작권 정보를 읽는다 (3·4번 앱 연동)', () async {
    final dir = Directory.systemTemp.createTempSync('mat').path;
    tmpFile(dir, '여행.mp4');
    tmpFile(dir, '방송 캡처.mp4');
    tmpFile(dir, '사진.jpg');
    tmpFile(dir, '메모.txt', '제주에서 처음 본 바다 이야기');
    tmpFile(dir, '모르는파일.xyz');
    File('$dir/manifest.json').writeAsStringSync(
      jsonEncode({
        'source': '하드 자료 검색',
        'items': [
          {'file': '여행.mp4', 'title': '제주 여행', 'copyright': 'own'},
          {'file': '방송 캡처.mp4', 'copyright': 'own'},
        ],
      }),
    );
    final list = await FolderMaterialSource(dir).list();
    expect(list.length, 4);
    final trip = list.firstWhere((m) => m.title == '제주 여행');
    expect(trip.needsCopyrightCheck, isFalse);
    expect(trip.sourceApp, '하드 자료 검색');
    expect(list.firstWhere((m) => m.path.contains('방송')).needsCopyrightCheck, isTrue); // 이름이 의심스러우면 확인
    expect(list.firstWhere((m) => m.kind == 'image').needsCopyrightCheck, isTrue); // 설명 없으면 확인
    expect(list.firstWhere((m) => m.kind == 'text').note, contains('바다'));
  });

  test('저작권 확인 전에는 만들지 않고, 뺀 소재는 쓰지 않는다', () async {
    final (_, u) = await setup();
    final cs = cornerOf(u);
    final c = cs.create('사장님의 하루', 'UC_mock_cook');
    final dir = Directory.systemTemp.createTempSync('m2').path;
    tmpFile(dir, '아이유 MV.mp4');
    final r = await cs.importFrom(c.id, FolderMaterialSource(dir));
    expect(r.needCheck, 1);
    cs.addText(c.id, '오늘은 가게 문을 열고 첫 손님을 맞았어요. 정말 설렜어요.');
    await expectLater(cs.make(c.id), throwsA(isA<ProductionBlocked>()));
    final item = cs.items(c.id).firstWhere((i) => i.needsCheck);
    cs.decideCopyright(item.id, false);
    final made = await cs.make(c.id, formats: [ContentFormat.shorts]);
    expect(made.single.hasVideo, isFalse); // 뺀 영상은 들어가지 않음
  });

  test('직접 찍은 영상 + 음성 메모 → 자막·제목·설명·키워드·썸네일, 여러 형식', () async {
    final (_, u) = await setup();
    final cs = cornerOf(u);
    final c = cs.create('사장님의 하루', 'UC_mock_cook');
    final dir = Directory.systemTemp.createTempSync('m3').path;
    cs.addOwnVideo(c.id, tmpFile(dir, '가게 오픈.mp4'));
    expect(() => cs.addOwnVideo(c.id, '$dir/없음.mp4'), throwsA(isA<AppFailure>()));
    final memo = u.memos.add('오늘 처음으로 단골손님이 생겼어요. 매일 오시겠대요!');
    cs.addMemo(c.id, memo);
    final made = await cs.make(c.id);
    expect(made.map((p) => p.format), [ContentFormat.shorts, ContentFormat.long, ContentFormat.image]);
    for (final p in made) {
      expect(p.title, isNotEmpty);
      expect(p.description, contains('단골손님'));
      expect(p.tags, isNotEmpty);
      expect(p.thumbnailText, isNotEmpty);
      expect(p.cornerId, c.id);
      expect('${p.extra['srtText']}', contains('-->'));
      expect(File('${p.extra['srt']}').existsSync(), isTrue);
    }
    expect(made[0].hasVideo, isTrue);
    expect(made[1].hasVideo, isTrue);
    expect(made[2].hasVideo, isFalse); // 이미지 게시물은 영상 없음
    // 업로드는 여전히 사용자가 확인해야 함 (자동 업로드 없음)
    expect(made.every((p) => p.status == ProductionStatus.draft), isTrue);
  });

  test('하루 제작 한도를 넘으면 만들지 않는다', () async {
    final (_, u) = await setup();
    u.settings.produceDailyLimit = 2;
    final cs = cornerOf(u);
    final c = cs.create('코너', 'UC_mock_trip');
    cs.addText(c.id, '이야기');
    await expectLater(cs.make(c.id), throwsA(isA<ProductionBlocked>()));
    expect(productionOf2(u), isEmpty);
  });

  test('코너 이름·채널 필수, 삭제', () async {
    final (_, u) = await setup();
    final cs = cornerOf(u);
    expect(() => cs.create(' ', 'UC_mock_cook'), throwsA(isA<AppFailure>()));
    final c = cs.create('a', 'UC_mock_cook');
    cs.addText(c.id, 'x');
    cs.delete(c.id);
    expect(cs.corners(), isEmpty);
    expect(cs.items(c.id), isEmpty);
  });
}

List<Production> productionOf2(UserContext u) => (u.extensions['production']! as ProductionService).list();
