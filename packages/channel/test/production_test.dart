import 'dart:io';

import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/app/services.dart';
import 'package:channel_biseo/core/failure.dart';
import 'package:channel_biseo/features/ai/brain.dart';
import 'package:channel_biseo/features/production/production_service.dart';
import 'package:channel_biseo/features/tools/tools_service.dart';
import 'package:channel_biseo/stages.dart';
import 'package:channel_biseo/ui/produce_screen.dart';
import 'package:channel_biseo/ui/tools_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<(TestKit, UserContext)> setup({bool desktop = true}) async {
  registerStages();
  final k = TestKit(isDesktop: desktop);
  final state = AppState(k.env);
  await state.login(k.env.accounts.create('제작자', '1234'));
  final u = state.user!;
  await u.youtube.connectGoogle();
  for (final c in u.youtube.channels()) {
    await u.youtube.syncChannel(c.channelId);
  }
  return (k, u);
}

File fakeVideo() => File('${Directory.systemTemp.createTempSync('vid').path}/my.mp4')..writeAsBytesSync([0, 1, 2]);

void main() {
  group('콘텐츠 만들기', () {
    test('다섯 가지 형식 모두 제목·설명·키워드·썸네일·대본을 함께 만든다', () async {
      final (_, u) = await setup();
      u.settings.produceDailyLimit = 10;
      final ps = productionOf(u);
      final topics = ['김치찌개 끓이기', '부산 바다 산책', '연말정산 꿀팁', '봄 소풍 도시락', '할머니 손맛 이야기'];
      for (var i = 0; i < ContentFormat.values.length; i++) {
        final f = ContentFormat.values[i];
        final p = await ps.create(channelId: 'UC_mock_cook', format: f, topic: topics[i]);
        expect(p.format, f);
        expect(p.title, isNotEmpty);
        expect(p.description, isNotEmpty);
        expect(p.tags, isNotEmpty);
        expect(p.thumbnailText, isNotEmpty);
        expect(p.script, isNotEmpty);
        expect(p.status, ProductionStatus.draft);
      }
    });

    test('하루 제작 한도', () async {
      final (k, u) = await setup();
      u.settings.produceDailyLimit = 2;
      final ps = productionOf(u);
      await ps.create(channelId: 'UC_mock_cook', format: ContentFormat.shorts, topic: '불고기');
      await ps.create(channelId: 'UC_mock_trip', format: ContentFormat.long, topic: '제주 여행');
      await expectLater(
        ps.create(channelId: 'UC_mock_money', format: ContentFormat.shorts, topic: '적금'),
        throwsA(isA<ProductionBlocked>()),
      );
      k.clock.advance(const Duration(days: 1));
      await ps.create(channelId: 'UC_mock_money', format: ContentFormat.shorts, topic: '적금');
    });

    test('같은 채널에 비슷한 콘텐츠를 반복해서 만들지 않는다', () async {
      final (_, u) = await setup();
      final ps = productionOf(u);
      await ps.create(channelId: 'UC_mock_cook', format: ContentFormat.shorts, topic: '김치찌개');
      await expectLater(
        ps.create(channelId: 'UC_mock_cook', format: ContentFormat.shorts, topic: '김치찌개'),
        throwsA(isA<ProductionBlocked>()),
      );
      // 다른 채널이면 괜찮다
      await ps.create(channelId: 'UC_mock_trip', format: ContentFormat.shorts, topic: '김치찌개');
    });

    test('음성 메모를 소재로 쓰면 사용 표시', () async {
      final (_, u) = await setup();
      final id = u.memos.add('할머니가 알려 주신 잡채 비법');
      final p = await productionOf(u).create(channelId: 'UC_mock_cook', format: ContentFormat.talk, memoId: id);
      expect(p.description, contains('잡채'));
      expect(u.memos.byId(id)!.used, isTrue);
    });

    test('음성으로 "요리 채널에 쇼츠 하나 만들어"', () async {
      final (_, u) = await setup();
      final r = await u.voice.handle('요리 채널에 쇼츠 하나 만들어');
      expect(r.spoken, contains('집밥 요리 교실'));
      expect(productionOf(u).list().single.format, ContentFormat.shorts);
    });
  });

  group('업로드 (항상 비공개)', () {
    test('확인 없이는 올리지 않고, 영상 파일이 없으면 안내', () async {
      final (k, u) = await setup();
      final ps = productionOf(u);
      final p = await ps.create(channelId: 'UC_mock_cook', format: ContentFormat.shorts, topic: '계란말이');
      await expectLater(
        ps.uploadPrivate(p.id, userConfirmed: false, aiLabelMethod: 'setting'),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        ps.uploadPrivate(p.id, userConfirmed: true, aiLabelMethod: 'setting'),
        throwsA(isA<ProductionBlocked>()),
      );
      expect(k.mockYt.uploadCalls, 0);
    });

    test('내가 만든 영상 → 비공개 업로드 → 확인 대기 목록 → 사용자가 확인 완료', () async {
      final (k, u) = await setup();
      final ps = productionOf(u);
      final p = await ps.create(channelId: 'UC_mock_trip', format: ContentFormat.shorts, topic: '경주 야경');
      expect(() => ps.attachOwnVideo(p.id, '/없는/파일.mp4'), throwsA(isA<AppFailure>()));
      ps.attachOwnVideo(p.id, fakeVideo().path);
      final st = await ps.uploadPrivate(p.id, userConfirmed: true, aiLabelMethod: 'setting');
      expect(st, ProductionStatus.uploadedPrivate);
      final pr = ps.byId(p.id)!;
      final v = k.mockYt.videos[pr.uploadedVideoId]!;
      expect(v.privacy, 'private');
      expect(v.channelId, 'UC_mock_trip');
      expect(ps.reviewList().single.id, p.id);
      expect((await u.voice.handle('비공개 영상 목록 읽어줘')).spoken, contains('1개'));
      expect(u.briefing.compose().today.join(), contains('확인을 기다리는 비공개 영상이 1개'));
      expect(pr.studioUrl, contains(pr.uploadedVideoId));
      ps.markDoneByUser(p.id);
      expect(ps.reviewList(), isEmpty);
      // 앱은 공개 전환을 하지 않았다
      expect(k.mockYt.videos[pr.uploadedVideoId]!.privacy, 'private');
    });

    test('AI 표시: 설명 글 방식이면 설명에 문구 추가', () async {
      final (k, u) = await setup();
      final ps = productionOf(u);
      final p = await ps.create(channelId: 'UC_mock_cook', format: ContentFormat.long, topic: '된장국');
      ps.attachOwnVideo(p.id, fakeVideo().path);
      await ps.uploadPrivate(p.id, userConfirmed: true, aiLabelMethod: 'description');
      expect(k.mockYt.videos[ps.byId(p.id)!.uploadedVideoId]!.description, contains('AI의 도움'));
    });

    test('유튜브 한도가 모자라면 자동으로 올리지 않고 "내일 올리기" 로 준비', () async {
      final (k, u) = await setup();
      final ps = productionOf(u);
      final p = await ps.create(channelId: 'UC_mock_cook', format: ContentFormat.shorts, topic: '떡볶이');
      ps.attachOwnVideo(p.id, fakeVideo().path);
      u.quota.reserve(u.quota.remaining - 100);
      final st = await ps.uploadPrivate(p.id, userConfirmed: true, aiLabelMethod: 'setting');
      expect(st, ProductionStatus.uploadTomorrow);
      expect(k.mockYt.uploadCalls, 0);
      // 다음 날 자동 작업을 돌려도 업로드는 하지 않는다
      k.clock.advance(const Duration(days: 1));
      await u.runner.runNow();
      expect(k.mockYt.uploadCalls, 0);
      expect(u.briefing.compose().today.join(), contains('미뤄 둔 업로드 1개'));
      expect(
        await ps.uploadPrivate(p.id, userConfirmed: true, aiLabelMethod: 'setting'),
        ProductionStatus.uploadedPrivate,
      );
    });

    test('사진·이미지 게시물은 업로드 대상이 아니다', () async {
      final (_, u) = await setup();
      final ps = productionOf(u);
      final p = await ps.create(channelId: 'UC_mock_cook', format: ContentFormat.image, topic: '김밥');
      expect(p.isUploadable, isFalse);
      await expectLater(
        ps.uploadPrivate(p.id, userConfirmed: true, aiLabelMethod: 'setting'),
        throwsA(isA<AppFailure>()),
      );
    });
  });

  group('힉스필드와 도구 연결', () {
    test('승인 없이는 크레딧을 쓰지 않는다, 승인하면 영상이 붙는다', () async {
      final (_, u) = await setup();
      final ps = productionOf(u);
      final gen = u.tools.mockGenerator as MockVideoGenerator;
      final p = await ps.create(channelId: 'UC_mock_cook', format: ContentFormat.shorts, topic: '잡채');
      final q = await ps.higgsfieldQuote(p.id);
      expect(q.estimate, greaterThan(0));
      expect(q.left, 500);
      await expectLater(ps.generateWithHiggsfield(p.id, userApproved: false), throwsA(isA<AppFailure>()));
      expect(gen.started, 0);
      await ps.generateWithHiggsfield(p.id, userApproved: true);
      expect(gen.started, 1);
      expect(ps.byId(p.id)!.hasVideo, isTrue);
      expect(ps.byId(p.id)!.videoSource, 'higgsfield');
    });

    test('크레딧이 모자라면 만들지 않는다', () async {
      final (_, u) = await setup();
      final gen = u.tools.mockGenerator as MockVideoGenerator..left = 1;
      final p = await productionOf(u).create(channelId: 'UC_mock_cook', format: ContentFormat.shorts, topic: '잡채');
      await expectLater(
        productionOf(u).generateWithHiggsfield(p.id, userApproved: true),
        throwsA(isA<ProductionBlocked>()),
      );
      expect(gen.started, 0);
    });

    test('도구 상태: 연결 안 됨 / 연결됨 / 준비 중 / 해제, 키는 보안 저장소에만', () async {
      final (k, u) = await setup();
      var all = await u.tools.all();
      expect(all.firstWhere((t) => t.id == ToolId.higgsfield).state, ToolState.notConnected);
      expect(all.firstWhere((t) => t.id == ToolId.googleVids).state, ToolState.preparing);
      expect(all.firstWhere((t) => t.id == ToolId.vrew).state, ToolState.preparing);
      await u.tools.connectHiggsfield('hf-secret-key');
      all = await u.tools.all();
      expect(all.firstWhere((t) => t.id == ToolId.higgsfield).state, ToolState.connected);
      expect(k.secrets.data.values, contains('hf-secret-key'));
      expect(await u.tools.videoGenerator(), isA<HiggsfieldGenerator>());
      await u.tools.disconnect(ToolId.higgsfield);
      expect((await u.tools.all()).firstWhere((t) => t.id == ToolId.higgsfield).state, ToolState.notConnected);
      expect(k.secrets.data.values, isNot(contains('hf-secret-key')));
      expect(u.tools.vault.available, isFalse);
    });
  });
}
