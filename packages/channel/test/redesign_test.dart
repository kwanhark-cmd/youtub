import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/stages.dart';
import 'package:channel_biseo/ui/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 화면 재설계(6-1) 검증: 크기로 중요도, 채운 색 타일, 설정 묶음, 채널 카드.
final themes = <String, AppTokens>{
  '밝음': AppTokens.light(),
  '어두움': AppTokens.dark(),
  '고대비 밝음': AppTokens.contrast(darkMode: false),
  '고대비 어두움': AppTokens.contrast(darkMode: true),
};

Future<AppState> start(WidgetTester t, {double w = 390, double h = 844, String theme = 'light'}) async {
  registerStages();
  t.view.physicalSize = Size(w * 2, h * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final k = TestKit();
  final s = AppState(k.env);
  await s.login(k.env.accounts.create('재설계', '1234'));
  final u = s.user!;
  u.settings.onboardingDone = true;
  await u.youtube.connectGoogle();
  for (final c in u.youtube.channels()) {
    await u.youtube.syncChannel(c.channelId);
  }
  s.setView(themeMode: theme);
  await t.pumpWidget(ChannelBiseoApp(state: s));
  await t.pumpAndSettle();
  return s;
}

/// 화면의 세로 목록을 위에서부터 내리며 [f] 가 보이게 한다.
Future<void> reveal(WidgetTester t, Finder f) async {
  final list = find.byType(Scrollable).first;
  t.state<ScrollableState>(list).position.jumpTo(0);
  await t.pumpAndSettle();
  await t.scrollUntilVisible(f, 200, scrollable: list);
  await t.pumpAndSettle();
}

void main() {
  group('색', () {
    for (final e in themes.entries) {
      test('${e.key}: 영역 색 타일 위 글자 대비 4.5:1 이상, 진한 아이콘 칩 위 흰 아이콘 3:1 이상', () {
        final t = e.value;
        for (final h in Hue.values) {
          expect(contrastRatio(t.tileBg(h), t.onTile(h)), greaterThanOrEqualTo(4.5), reason: '$h 글자');
          expect(contrastRatio(t.hueStrong(h), t.onHueStrong(h)), greaterThanOrEqualTo(3), reason: '$h 아이콘');
        }
      });
    }

    test('어두운 모드: 타일은 바탕보다 확실히 밝음 (어두운 바탕 위 어두운 상자 금지), 카드는 바탕보다 한 단계 밝음', () {
      final t = AppTokens.dark();
      final bg = t.background.computeLuminance();
      expect(t.card.computeLuminance(), greaterThan(bg));
      for (final h in Hue.values) {
        expect(contrastRatio(t.tileBg(h), t.background), greaterThanOrEqualTo(2.4), reason: '$h');
      }
    });

    test('글씨 크기 4단계 이상, 카드 사이 간격은 예전(16)의 1.5배', () {
      final sizes = {
        AppTokens.fontHero,
        AppTokens.fontTitle,
        AppTokens.fontSection,
        AppTokens.fontBody,
        AppTokens.fontSmall,
      };
      expect(sizes.length, greaterThanOrEqualTo(4));
      expect(AppTokens.cardGap, 16 * 1.5);
    });
  });

  group('홈', () {
    testWidgets('가장 먼저 눈에 띄는 것 = 오늘 할 일 (가득 찬 폭, 가장 큰 카드)', (t) async {
      await start(t);
      final today = t.getRect(find.byKey(const Key('today-card')));
      final screenW = t.view.physicalSize.width / t.view.devicePixelRatio;
      expect(today.width, greaterThan(screenW - 40));
      for (final k in ['tile-channels', 'tile-produce', 'usage-strip']) {
        final f = find.byKey(Key(k));
        await reveal(t, f);
        final r = t.getRect(f);
        expect(r.width * r.height, lessThan(today.width * today.height), reason: k);
      }
      // 사용량 띠는 작음 (오늘 할 일보다 낮음)
      expect(t.getRect(find.byKey(const Key('usage-strip'))).height, lessThan(today.height));
    });

    testWidgets('같은 크기 상자가 3개 이상 한 줄에 놓이지 않음', (t) async {
      await start(t, w: 900, h: 1200);
      final tiles = find.byType(HueTile);
      final rows = <double, int>{};
      for (final e in tiles.evaluate()) {
        final r = t.getRect(find.byWidget(e.widget));
        rows.update(r.top.roundToDouble(), (n) => n + 1, ifAbsent: () => 1);
      }
      expect(rows.values.every((n) => n <= 2), isTrue, reason: '$rows');
    });

    testWidgets('채널·제작 타일은 숫자 카드 (큰 숫자)', (t) async {
      await start(t);
      await reveal(t, find.byKey(const Key('tile-channels')));
      final ch = find.descendant(of: find.byKey(const Key('tile-channels')), matching: find.text('3'));
      expect(ch, findsOneWidget);
      expect(t.widget<Text>(ch).style!.fontSize, AppTokens.fontHero);
    });
  });

  group('설정', () {
    testWidgets('묶음 카드 5개 (계정 연결·인공지능·자동 작업·보기·자료 관리) + 맨 아래 빨간 초기화 카드', (t) async {
      await start(t, h: 1400);
      await t.tap(find.byIcon(Icons.settings).last);
      await t.pumpAndSettle();
      // 목록을 내려 가며 묶음 이름 모으기 (화면 밖 항목은 만들어지지 않으므로)
      final titles = <String>[];
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 60; i++) {
        for (final e in find.byType(SettingsGroup).evaluate()) {
          final title = (e.widget as SettingsGroup).title;
          if (!titles.contains(title)) titles.add(title);
        }
        if (find.byKey(const Key('danger-card')).evaluate().isNotEmpty) break;
        await t.drag(list, const Offset(0, -400));
        await t.pumpAndSettle();
      }
      expect(titles, ['계정 연결', '인공지능', '자동 작업', '보기와 듣기', '자료 관리']);
      await reveal(t, find.byKey(const Key('danger-card')));
      final danger = t.getRect(find.byKey(const Key('danger-card')));
      final lastGroup = t.getRect(find.byType(SettingsGroup).last);
      expect(danger.top, greaterThanOrEqualTo(lastGroup.bottom)); // 마지막 묶음 아래
      expect(
        find.descendant(of: find.byKey(const Key('danger-card')), matching: find.byKey(const Key('reset'))),
        findsOneWidget,
      );
    });
  });

  group('채널 목록', () {
    for (final w in [390.0, 900.0]) {
      testWidgets('썸네일 폭 160 이상, 왼쪽 색 띠, 숫자 3개 한 줄 (폭 $w)', (t) async {
        await start(t, w: w, h: 1400);
        await t.tap(find.byIcon(Icons.video_library).last);
        await t.pumpAndSettle();
        final card = find.byKey(const Key('channel-UC_mock_cook'));
        await reveal(t, card);
        final thumb = find.descendant(
          of: card,
          matching: find.byWidgetPredicate((x) => x is Container && x.constraints?.maxWidth == 160),
        );
        expect(t.getSize(thumb.first).width, greaterThanOrEqualTo(160));
        final icons = [Icons.people_alt, Icons.play_circle_fill, Icons.visibility];
        final tops = {
          for (final i in icons) t.getRect(find.descendant(of: card, matching: find.byIcon(i))).center.dy.round(),
        };
        expect(tops.length, 1, reason: '한 줄');
        expect(t.takeException(), isNull);
      });
    }
  });
}
