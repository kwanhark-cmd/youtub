import 'dart:io';

import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/app/services.dart';
import 'package:channel_biseo/features/ai/ai_service.dart';
import 'package:channel_biseo/features/ai/brain.dart';
import 'package:channel_biseo/features/production/desc_template.dart';
import 'package:channel_biseo/features/youtube/trending.dart';
import 'package:channel_biseo/core/db.dart';
import 'package:channel_biseo/core/failure.dart';
import 'package:channel_biseo/features/production/calendar.dart';
import 'package:channel_biseo/features/production/thumbnail.dart';
import 'package:channel_biseo/stages.dart';
import 'package:channel_biseo/ui/blog_screen.dart';
import 'package:channel_biseo/ui/calendar_screen.dart';
import 'package:channel_biseo/ui/channels_screen.dart';
import 'package:channel_biseo/ui/edits_screen.dart';
import 'package:channel_biseo/ui/produce_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 화면 개선 뒤 추가 기능 (TubeBuddy·vidIQ·Metricool 비교에서 가져온 것)
Future<(TestKit, AppState, UserContext)> setup() async {
  registerStages();
  final k = TestKit();
  final s = AppState(k.env);
  await s.login(k.env.accounts.create('기능', '1234'));
  final u = s.user!;
  u.settings.onboardingDone = true;
  u.settings.produceDailyLimit = 20;
  await u.youtube.connectGoogle();
  for (final c in u.youtube.channels()) {
    await u.youtube.syncChannel(c.channelId);
  }
  return (k, s, u);
}

void main() {
  group('채널별 설명 템플릿', () {
    test('고정 문구·링크·해시태그를 새 영상 설명에 자동으로 붙이고, 두 번 붙지 않는다', () async {
      final (_, _, u) = await setup();
      final store = DescTemplateStore(u.db);
      expect(store.get('UC_mock_cook').isEmpty, isTrue);
      store.save(
        'UC_mock_cook',
        DescTemplate(
          fixed: '구독과 좋아요 부탁드려요',
          links: ['https://blog.example.com'],
          hashtags: DescTemplate.cleanTags(['#집밥 #요리, 집밥']),
        ),
      );
      final t = store.get('UC_mock_cook');
      expect(t.hashtags, ['집밥', '요리']);
      final p = await productionOf(u).create(channelId: 'UC_mock_cook', format: ContentFormat.shorts, topic: '계란말이');
      expect(p.description, contains('구독과 좋아요 부탁드려요'));
      expect(p.description, contains('https://blog.example.com'));
      expect(p.description, endsWith('#집밥 #요리'));
      expect(t.applyTo(p.description), p.description); // 두 번 붙지 않음
      // 다른 채널에는 붙지 않음
      final q = await productionOf(u).create(channelId: 'UC_mock_trip', format: ContentFormat.shorts, topic: '바다');
      expect(q.description, isNot(contains('구독과 좋아요 부탁드려요')));
    });

    testWidgets('채널 화면에서 템플릿 만들기', (t) async {
      final (_, s, u) = await setup();
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(ChannelBiseoApp(state: s));
      await t.pumpAndSettle();
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      // ignore: unawaited_futures
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => ChannelDetailScreen(user: u, channelId: 'UC_mock_trip'),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('tpl-edit')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('tpl-fixed')), '여행 이야기는 매주 금요일!');
      await t.enterText(find.byKey(const Key('tpl-tags')), '#여행 #국내여행');
      await t.tap(find.byKey(const Key('tpl-save')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('tpl-edit'))); // 다시 열면 "자동으로 붙어요" 표시
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tpl-preview')), findsOneWidget);
      await t.tap(find.text('취소'));
      await t.pumpAndSettle();
      expect(DescTemplateStore(u.db).get('UC_mock_trip').hashtags, ['여행', '국내여행']);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('일괄 수정 미리보기', () {
    testWidgets('한 화면에서 보고, 체크를 뺀 것은 적용하지 않고, 방금 적용한 것을 한 번에 되돌린다', (t) async {
      final (k, s, u) = await setup();
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final before = {for (final v in k.mockYt.videos.values) v.videoId: v.meta};
      await t.pumpWidget(ChannelBiseoApp(state: s));
      await t.pumpAndSettle();
      final ctx = t.element(find.byType(NavigationBar));
      // ignore: unawaited_futures
      runEditsFlow(ctx, u);
      await t.pumpAndSettle();
      expect(find.text('이렇게 수정할게요'), findsOneWidget);
      expect(find.text('고른 6개 적용하기'), findsOneWidget);
      await t.tap(find.byKey(const Key('batch-0')));
      await t.pumpAndSettle();
      expect(find.text('고른 5개 적용하기'), findsOneWidget);
      await t.tap(find.byKey(const Key('apply-edits')));
      await t.pumpAndSettle();
      expect(u.editLog.list().where((e) => e.status.name == 'applied').length, 5);
      // 완료 알림의 "방금 것 모두 되돌리기"
      await t.tap(find.text('방금 것 모두 되돌리기'));
      await t.pumpAndSettle();
      expect(u.editLog.list().where((e) => e.status.name == 'applied'), isEmpty);
      for (final v in k.mockYt.videos.values) {
        expect(v.meta.sameAs(before[v.videoId]!), isTrue);
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('모두 빼면 적용 버튼이 꺼지고, 닫으면 아무것도 바뀌지 않는다', (t) async {
      final (k, s, u) = await setup();
      await t.pumpWidget(ChannelBiseoApp(state: s));
      await t.pumpAndSettle();
      // ignore: unawaited_futures
      runEditsFlow(t.element(find.byType(NavigationBar)), u);
      await t.pumpAndSettle();
      await t.tap(find.text('모두 빼기'));
      await t.pumpAndSettle();
      expect(find.text('고른 0개 적용하기'), findsOneWidget);
      await t.tap(find.byKey(const Key('apply-edits')));
      await t.pumpAndSettle();
      expect(find.text('이렇게 수정할게요'), findsOneWidget); // 눌러도 닫히지 않음
      await t.tap(find.byIcon(Icons.close));
      await t.pumpAndSettle();
      expect(u.editLog.list(), isEmpty);
      expect(k.mockYt.updateCalls, 0);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('주목할 영상', () {
    Future<void> nextDay(TestKit k, UserContext u, Map<String, int> boost) async {
      k.clock.advance(const Duration(days: 1));
      k.mockYt.videos.updateAll((id, v) => v.copyWith(viewCount: v.viewCount + (boost[id] ?? 10)));
      for (final c in u.youtube.channels()) {
        await u.youtube.syncChannel(c.channelId);
      }
    }

    test('평소보다 갑자기 많이 늘어난 영상만 찾는다', () async {
      final (k, _, u) = await setup();
      final svc = TrendingService(u.db, u.youtube);
      expect(svc.find(), isEmpty); // 기록이 하루뿐이면 비교 못 함
      await nextDay(k, u, {'UC_mock_cook_v5': 3000, 'UC_mock_trip_v3': 40});
      final list = svc.find();
      expect(list.single.videoId, 'UC_mock_cook_v5');
      expect(list.single.perDay, 3000);
      expect(list.single.ratio, greaterThanOrEqualTo(3));
      // 모두 똑같이 늘면 주목할 영상 없음
      await nextDay(k, u, {});
      expect(svc.find(), isEmpty);
    });

    testWidgets('홈에 주목할 영상 카드가 나온다', (t) async {
      final (k, s, u) = await setup();
      await nextDay(k, u, {'UC_mock_trip_v7': 5000});
      t.view.physicalSize = const Size(390 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(ChannelBiseoApp(state: s));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('trending-card')), findsOneWidget);
      expect(find.textContaining('하루 +5,000회'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('검색어 추천', () {
    test('연습 모드: 기존 키워드와 겹치지 않는 추천, 비용 0', () async {
      final (_, _, u) = await setup();
      final style = Brain.mockStyle('집밥 요리 교실', ['김치찌개 만들기']);
      final list = await u.brain.suggestKeywords('김치찌개 끓이기', ['김치찌개 만들기'], style);
      expect(list, isNotEmpty);
      expect(list.length, lessThanOrEqualTo(8));
      expect(list, isNot(contains('김치찌개 만들기')));
      expect(u.ai.monthCostUsd, 0);
    });

    test('인공지능이 켜져 있으면 실제로 묻고 비용이 기록된다', () async {
      registerStages();
      final k = TestKit(aiProviders: {'claude': FakeAiProvider((r) => '{"keywords":["집밥 레시피","김치찌개 황금레시피","집밥"]}')});
      final s = AppState(k.env);
      await s.login(k.env.accounts.create('ai', '1234'));
      final u = s.user!;
      await u.ai.setKey('sk-ant-test');
      final list = await u.brain.suggestKeywords('김치찌개', ['집밥'], Brain.mockStyle('요리', const []));
      expect(list, ['집밥 레시피', '김치찌개 황금레시피']);
      expect(u.ai.monthCostUsd, greaterThan(0));
    });

    testWidgets('제작 상세에서 골라 키워드에 더하기', (t) async {
      final (_, s, u) = await setup();
      final p = await productionOf(u).create(channelId: 'UC_mock_cook', format: ContentFormat.shorts, topic: '잡채');
      await t.pumpWidget(ChannelBiseoApp(state: s));
      await t.pumpAndSettle();
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      // ignore: unawaited_futures
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => ProductionDetailScreen(user: u, id: p.id),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const Key('suggest-keywords')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byKey(const Key('suggest-keywords')));
      await t.pumpAndSettle();
      expect(find.text('연습 모드라 비용이 들지 않았어요'), findsOneWidget);
      final chip = find.byType(FilterChip).first;
      final label = ((t.widget<FilterChip>(chip).label) as Text).data!;
      await t.tap(chip);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('kw-add')));
      await t.pumpAndSettle();
      expect(productionOf(u).byId(p.id)!.tags, contains(label));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('게시 달력', () {
    test('만듦·예약·확인 대기·공개함·블로그 글을 날짜별로 모은다', () async {
      final (k, _, u) = await setup();
      final ps = productionOf(u);
      final a = await ps.create(channelId: 'UC_mock_cook', format: ContentFormat.shorts, topic: '만든 것');
      final b = await ps.create(channelId: 'UC_mock_trip', format: ContentFormat.long, topic: '올린 것');
      final v = File('${Directory.systemTemp.createTempSync('v').path}/a.mp4')..writeAsBytesSync([1]);
      ps.attachOwnVideo(b.id, v.path);
      await ps.uploadPrivate(b.id, userConfirmed: true, aiLabelMethod: 'setting');
      final c = await ps.create(channelId: 'UC_mock_money', format: ContentFormat.long, topic: '내일 올릴 것');
      ps.attachOwnVideo(c.id, v.path);
      u.quota.reserve(u.quota.remaining);
      await ps.uploadPrivate(c.id, userConfirmed: true, aiLabelMethod: 'setting');
      final site = blogOf(u).addTistory('티', '');
      await blogOf(u).newPost(site.id, topic: '가을');
      final today = dayKey(k.clock());
      final tomorrow = dayKey(k.clock().add(const Duration(days: 1)));
      final m = CalendarService(u.db).byDay(k.clock().year, k.clock().month);
      final kinds = m[today]!.map((e) => e.kind).toSet();
      expect(kinds, containsAll([CalKind.made, CalKind.waiting, CalKind.blogWaiting]));
      expect(m[today]!.where((e) => e.productionId == a.id).single.kind, CalKind.made);
      expect(m[tomorrow]!.single.kind, CalKind.scheduled);
      ps.markDoneByUser(b.id);
      expect(
        CalendarService(u.db)
            .byDay(k.clock().year, k.clock().month)[today]!
            .where((e) => e.productionId == b.id)
            .single
            .kind,
        CalKind.published,
      );
    });

    testWidgets('달력 화면: 날짜를 누르면 그날 일이 보이고, 달을 넘길 수 있다', (t) async {
      final (k, s, u) = await setup();
      await productionOf(u).create(channelId: 'UC_mock_cook', format: ContentFormat.shorts, topic: '달력 시험');
      t.view.physicalSize = const Size(320 * 2, 568 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      s.setTextScale(1.6);
      await t.pumpWidget(ChannelBiseoApp(state: s));
      await t.pumpAndSettle();
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      // ignore: unawaited_futures
      nav.push(MaterialPageRoute<void>(builder: (_) => CalendarScreen(user: u)));
      await t.pumpAndSettle();
      expect(find.text('2026년 11월'), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const Key('cal-event-0')), 200, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('달력 시험'), findsOneWidget);
      await t.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('cal-day-1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('cal-next')));
      await t.pumpAndSettle();
      expect(find.text('2026년 12월'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('썸네일 비교 선택', () {
    test('문구와 색이 다른 2개를 만들고, 고른 것만 썸네일이 된다', () async {
      final (_, _, u) = await setup();
      final ps = productionOf(u);
      final p = await ps.create(channelId: 'UC_mock_cook', format: ContentFormat.shorts, topic: '부대찌개 끓이기 아주 쉽게');
      final seen = <(String, int)>[];
      final paths = await ps.makeThumbnailChoices(p.id, (text, seed) async {
        seen.add((text, seed));
        return [seed];
      });
      expect(paths.length, 2);
      expect(seen[0].$1, isNot(seen[1].$1)); // 문구가 다름
      expect(seen[0].$2, isNot(seen[1].$2)); // 색(seed)이 다름
      expect(() => ps.chooseThumbnail(p.id, '/다른/파일.png'), throwsA(isA<AppFailure>()));
      ps.chooseThumbnail(p.id, paths[1]);
      final after = ps.byId(p.id)!;
      expect(after.thumbPath, paths[1]);
      expect(after.extra['thumbChosen'], 'B');
    });

    testWidgets('제작 상세에서 2개 중 하나를 눌러 고르기', (t) async {
      final (_, s, u) = await setup();
      thumbRenderer = (text, seed) async => [1, 2, 3];
      addTearDown(() => thumbRenderer = (text, seed) => renderThumbnail(text, seed: seed));
      final p = await productionOf(u).create(channelId: 'UC_mock_cook', format: ContentFormat.long, topic: '고르기 시험');
      await t.pumpWidget(ChannelBiseoApp(state: s));
      await t.pumpAndSettle();
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      // ignore: unawaited_futures
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => ProductionDetailScreen(user: u, id: p.id),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const Key('thumb-compare')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(find.byKey(const Key('thumb-compare')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('thumb-compare')));
      await t.pumpAndSettle();
      expect(find.text('어느 썸네일이 더 좋아요?'), findsOneWidget);
      await t.tap(find.byKey(const Key('thumb-choice-0')));
      await t.pumpAndSettle();
      expect(productionOf(u).byId(p.id)!.extra['thumbChosen'], 'A');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  });
}
