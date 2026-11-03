import 'package:binugi/app.dart';
import 'package:binugi/data/models.dart';
import 'package:binugi/services/image_service.dart';
import 'package:binugi/state/app_state.dart';
import 'package:binugi/theme/app_theme.dart';
import 'package:binugi/ui/screens/classify_screen.dart';
import 'package:binugi/ui/screens/discard_screen.dart';
import 'package:binugi/ui/screens/home_screen.dart';
import 'package:binugi/ui/screens/import_screen.dart';
import 'package:binugi/ui/screens/item_detail_screen.dart';
import 'package:binugi/ui/screens/item_list_screen.dart';
import 'package:binugi/ui/screens/notices_screen.dart';
import 'package:binugi/ui/screens/progress_screen.dart';
import 'package:binugi/ui/screens/register_screen.dart';
import 'package:binugi/ui/screens/review_screen.dart';
import 'package:binugi/ui/screens/sell_screen.dart';
import 'package:binugi/ui/screens/settings_screen.dart';
import 'package:binugi/ui/screens/timelapse_screen.dart';
import 'package:binugi/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// 디자인 자동 검사: 가장 큰 글씨 · 가장 작은 화면(360×640) · 어두운 · 고대비에서
/// 모든 화면이 잘리거나 겹치지 않는지(넘침 오류가 없는지) 확인합니다.
class Ctx {
  late AppState s;
  late Item sell;
  late Item discard;
  late Item undecided;
  late SavedPhoto photo;
}

Future<Ctx> seed(WidgetTester tester) async {
  final c = Ctx();
  await tester.runAsync(() async {
    final (s, _) = await makeState();
    c.s = s;
    c.photo = await s.savePhoto(fakeJpeg(w: 400, h: 300));
    c.undecided = await s.addItem(
      name: '아주아주 긴 이름을 가진 오래된 원목 책장과 그 위의 작은 장식품 묶음',
      room: '거실',
      spot: 'TV 옆 수납장',
      photo: c.photo,
      suggestion: Decision.sell,
      reason: '아직 쓸 만해 보여요. 팔면 다른 사람이 잘 쓸 수 있어요.',
    );
    c.sell = await s.addItem(name: '커피 머신', condition: '잘 작동함', photo: c.photo);
    await s.decide(c.sell, Decision.sell);
    c.sell
      ..listingTitle = '커피 머신 팝니다 (작동 잘 됨)'
      ..listingBody = '커피 머신 팝니다.\n· 상태: 잘 작동함'
      ..priceLow = 10000
      ..priceHigh = 30000;
    await s.sales.startSelling(c.sell, price: 30000);
    c.discard = await s.addItem(name: '낡은 매트리스', kind: '가구', photo: c.photo);
    await s.decide(c.discard, Decision.discard);
    c.s.user.sido = '서울특별시';
    c.s.user.sigungu = '마포구';
    await s.saveUser();
    final shot = await s.savePhoto(fakeJpeg(w: 200, h: 150, seed: 3));
    await s.repo.addShot(TimelapseShot(userId: s.uid, spot: '거실 창가', path: shot.photoPath, takenAt: DateTime(2026)));
    await s.repo.addNotice(
      Notice(userId: s.uid, kind: 'one_year_warn', title: '곧 폐기 목록으로 옮겨져요', body: '"스탠드"가 판매 1년이 다 돼 가요. 7일 뒤 폐기 목록으로 옮겨요.', createdAt: DateTime(2026)),
    );
    s.global.onboarded = true;
    await s.refresh();
  });
  return c;
}

Future<void> pumpApp(WidgetTester tester, Ctx c, {required ThemeModeChoice theme, required TextSizeChoice text, bool reduce = false}) async {
  c.s.global
    ..theme = theme
    ..textSize = text
    ..reduceMotion = reduce;
  await tester.pumpWidget(BinugiApp(state: c.s, picker: FakePicker(), listenShares: false));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// 화면을 끝까지 내려 보며 모든 부분을 그려 봄
Future<void> scrollAll(WidgetTester tester) async {
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) return;
  for (var i = 0; i < 12; i++) {
    await tester.drag(scrollables.first, const Offset(0, -500), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Map<String, Widget Function(Ctx)> screens = {
  '홈': (c) => const SizedBox.shrink(),
  '등록': (c) => const RegisterScreen(),
  '찾은 물건 확인': (c) => ReviewScreen(
    batches: [
      DetectionBatch(c.photo, [DetectedItem(name: '커피 머신', condition: '잘 작동함', suggestion: Decision.sell, reason: '아직 쓸 만해요')]),
      DetectionBatch(c.photo, [DetectedItem(name: '')], error: '사진에서 물건을 알아보지 못했어요. 직접 이름을 적어주세요.'),
    ],
  ),
  '정리하기': (c) => const ClassifyScreen(),
  '모든 물건': (c) => const ItemListScreen(),
  '물건 자세히': (c) => ItemDetailScreen(itemId: c.undecided.id!),
  '판매 목록': (c) => const SellScreen(),
  '판매 자세히': (c) => SellDetailScreen(itemId: c.sell.id!),
  '폐기 목록': (c) => const DiscardScreen(),
  '폐기 자세히': (c) => DiscardDetailScreen(itemId: c.discard.id!),
  '진행 현황': (c) => const ProgressScreen(),
  '타임랩스': (c) => const TimelapseScreen(),
  '타임랩스 보기': (c) => const TimelapsePlayer(spot: '거실 창가'),
  '알림': (c) => const NoticesScreen(),
  '설정': (c) => const SettingsScreen(),
  '가져오기': (c) => const ImportScreen(initialText: '- 커피 머신: 판매 (잘 작동함)\n- 아주 오래되고 낡은 나무 의자 → 폐기'),
};

Finder sellButton() => find.byWidgetPredicate((w) => w is Semantics && w.properties.button == true && w.properties.label == '판매');

void main() {
  final configs = <(String, Size, ThemeModeChoice, TextSizeChoice)>[
    ('가장 작은 화면·가장 큰 글씨·밝게', const Size(360, 640), ThemeModeChoice.light, TextSizeChoice.huge),
    ('가장 작은 화면·가장 큰 글씨·어둡게', const Size(360, 640), ThemeModeChoice.dark, TextSizeChoice.huge),
    ('가장 작은 화면·크게·고대비', const Size(360, 640), ThemeModeChoice.highContrast, TextSizeChoice.large),
    ('큰 화면·보통', const Size(1280, 800), ThemeModeChoice.light, TextSizeChoice.normal),
  ];

  for (final (label, size, theme, text) in configs) {
    for (final entry in screens.entries) {
      testWidgets('[$label] ${entry.key} 화면이 넘치지 않음', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final c = await seed(tester);
        await pumpApp(tester, c, theme: theme, text: text);
        if (entry.key != '홈') {
          navKey.currentState!.push(MaterialPageRoute(builder: (_) => entry.value(c)));
        }
        await settle(tester);
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
        await settle(tester);
        await scrollAll(tester);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 6));
      });
    }
  }

  for (var step = 0; step < 4; step++) {
    testWidgets('[가장 작은 화면·가장 큰 글씨] 첫 실행 마법사 ${step + 1}단계', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await seed(tester);
      c.s.global.onboarded = false;
      await pumpApp(tester, c, theme: ThemeModeChoice.light, text: TextSizeChoice.huge);
      for (var i = 0; i < step; i++) {
        await tester.tap(find.text('다음'));
        await settle(tester);
      }
      await scrollAll(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('${step + 1} / 4', findRichText: true, skipOffstage: false), findsNothing); // 제목은 "n / 4  이름" 형태
      expect(find.textContaining('${step + 1} / 4'), findsOneWidget);
    });
  }

  testWidgets('움직임 줄이기를 켜면 축하 애니메이션이 나오지 않음', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await seed(tester);
    await pumpApp(tester, c, theme: ThemeModeChoice.light, text: TextSizeChoice.normal, reduce: true);
    await tester.ensureVisible(sellButton().first);
    await tester.tap(sellButton().first);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.text('판매(으)로 정했어요'), findsNothing);
    expect(find.text('되돌리기'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('움직임 줄이기를 끄면 축하 애니메이션이 나옴', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await seed(tester);
    await pumpApp(tester, c, theme: ThemeModeChoice.light, text: TextSizeChoice.normal);
    await tester.ensureVisible(sellButton().first);
    await tester.tap(sellButton().first);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.text('판매(으)로 정했어요'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('글씨 크기 3단계가 실제로 적용됨', (tester) async {
    final c = await seed(tester);
    final heights = <double>[];
    for (final t in TextSizeChoice.values) {
      await pumpApp(tester, c, theme: ThemeModeChoice.light, text: t);
      heights.add(tester.getSize(find.text('오늘 할 일')).height);
    }
    expect(heights[0] < heights[1] && heights[1] < heights[2], isTrue, reason: '$heights');
  });

  testWidgets('버튼 최소 높이 56', (tester) async {
    final c = await seed(tester);
    await pumpApp(tester, c, theme: ThemeModeChoice.light, text: TextSizeChoice.normal);
    for (final e in find.byType(BigButton).evaluate()) {
      final box = e.renderObject as RenderBox;
      expect(box.size.height, greaterThanOrEqualTo(AppSizes.buttonMinHeight));
    }
  });

  testWidgets('가장 먼저 눈에 띄는 것이 가장 중요한 것: 오늘 할 일이 맨 위에 가장 크게', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await seed(tester);
    await pumpApp(tester, c, theme: ThemeModeChoice.light, text: TextSizeChoice.normal);
    await settle(tester);
    final hero = tester.getRect(find.byType(TodayHero));
    final strip = tester.getRect(find.byType(StatStrip));
    final tiles = find.byType(CategoryTile).evaluate().map((e) => tester.getRect(find.byWidget(e.widget))).toList();
    expect(tiles.length, 3);
    expect(hero.top, lessThan(strip.top), reason: '오늘 할 일이 숫자 띠보다 위');
    expect(strip.top, lessThan(tiles.first.top), reason: '숫자 띠 다음에 분류 타일');
    final area = hero.width * hero.height;
    for (final r in [strip, ...tiles]) {
      expect(area, greaterThan(r.width * r.height * 2), reason: '오늘 할 일이 다른 카드보다 훨씬 큼');
    }
    expect(hero.width, closeTo(390 - 32, 1), reason: '화면 폭 전체');
    // 분류 타일 3개는 색이 서로 다름 (같은 상자 나란히 금지의 예외)
    final colors = find.byType(CategoryTile).evaluate().map((e) => (e.widget as CategoryTile).decision).toSet();
    expect(colors.length, 3);
  });

  testWidgets('성능: 앱 준비와 첫 화면 그리기 시간 측정', (tester) async {
    late Duration open;
    late Ctx c;
    await tester.runAsync(() async {
      final sw = Stopwatch()..start();
      c = Ctx();
      final (s, _) = await makeState();
      c.s = s;
      for (var i = 0; i < 60; i++) {
        await s.addItem(name: '물건 $i');
      }
      s.global.onboarded = true;
      final sw2 = Stopwatch()..start();
      await s.startup();
      open = sw2.elapsed;
      sw.stop();
    });
    final sw = Stopwatch()..start();
    await tester.pumpWidget(BinugiApp(state: c.s, picker: FakePicker(), listenShares: false));
    await tester.pump();
    final firstFrame = sw.elapsed;
    // ignore: avoid_print
    print('성능 측정: 자료 준비(물건 60개) ${open.inMilliseconds}ms, 첫 화면 ${firstFrame.inMilliseconds}ms');
    expect(open.inMilliseconds, lessThan(3000));
    expect(firstFrame.inMilliseconds, lessThan(3000));
  });
}
