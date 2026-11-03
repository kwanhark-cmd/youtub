import 'dart:io';

import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/features/ai/brain.dart';
import 'package:channel_biseo/stages.dart';
import 'package:channel_biseo/ui/blog_screen.dart';
import 'package:channel_biseo/ui/calendar_screen.dart';
import 'package:channel_biseo/ui/channels_screen.dart';
import 'package:channel_biseo/ui/corner_screen.dart';
import 'package:channel_biseo/ui/edits_screen.dart';
import 'package:channel_biseo/ui/memos_screen.dart';
import 'package:channel_biseo/ui/produce_screen.dart';
import 'package:channel_biseo/ui/theme.dart';
import 'package:channel_biseo/ui/tools_screen.dart';
import 'package:channel_biseo/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 화면 개선 검증: 대비, 가장 큰 글씨·가장 작은 화면·어두운 모드, 움직임 줄이기.
void main() {
  setUpAll(registerStages);

  group('글자와 바탕의 대비 (WCAG AA 4.5:1 이상)', () {
    final themes = {
      '밝음': AppTokens.light(),
      '어두움': AppTokens.dark(),
      '고대비 밝음': AppTokens.contrast(darkMode: false),
      '고대비 어두움': AppTokens.contrast(darkMode: true),
    };
    themes.forEach((name, t) {
      test(name, () {
        final pairs = <String, (Color, Color)>{
          '본문/바탕': (t.text, t.background),
          '본문/카드': (t.text, t.card),
          '보조 글자/바탕': (t.textSoft, t.background),
          '보조 글자/카드': (t.textSoft, t.card),
          '강조 버튼': (t.onAccent, t.accent),
          '주요 버튼': (t.onPrimary, t.primary),
          '보조 버튼': (t.onTonal, t.tonal),
          '위험 버튼': (t.onDanger, t.danger),
          for (final s in Status.values) '상태 ${s.name}': (t.onStatusFor(s), t.statusColor(s)),
          '연습 모드 띠': (t.onStatusDark, t.warning),
        };
        pairs.forEach((label, p) {
          final r = contrastRatio(p.$1, p.$2);
          expect(r, greaterThanOrEqualTo(4.5), reason: '$name $label: ${r.toStringAsFixed(2)}');
        });
      });
    });
  });

  group('움직임 줄이기', () {
    test('켜면 모든 움직임 시간이 0', () {
      final t = AppTokens.light(reduceMotion: true);
      expect([t.fast, t.normal, t.slow, t.stagger], everyElement(Duration.zero));
      final on = AppTokens.light();
      expect(on.normal, greaterThan(Duration.zero));
      expect(on.normal.inMilliseconds, inInclusiveRange(200, 300)); // 화면 전환 200~300ms
    });

    Future<double?> firstFrameOpacity(WidgetTester t, bool reduce) async {
      await t.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppTokens.light(reduceMotion: reduce), Brightness.light),
          home: const Scaffold(body: Appear(index: 3, child: Text('항목'))),
        ),
      );
      final op = find.ancestor(of: find.text('항목'), matching: find.byType(Opacity));
      final v = op.evaluate().isEmpty ? null : t.widget<Opacity>(op.first).opacity;
      await t.pumpAndSettle();
      return v;
    }

    testWidgets('목록 나타나기 효과: 기본은 움직이고, 줄이기면 바로 보인다', (t) async {
      expect(await firstFrameOpacity(t, false), lessThan(1));
      final reduced = await firstFrameOpacity(t, true);
      expect(reduced == null || reduced == 1.0, isTrue); // 효과 없이 바로 그림
    });

    testWidgets('설정의 "움직임 줄이기" 를 켜면 앱 전체 테마에 반영', (t) async {
      final k = TestKit();
      final state = AppState(k.env);
      await state.login(k.env.accounts.create('a', '1234'));
      state.user!.settings.onboardingDone = true;
      await t.pumpWidget(ChannelBiseoApp(state: state));
      await t.pumpAndSettle();
      BuildContext ctx() => t.element(find.byType(NavigationBar));
      expect(ctx().tokens.reduceMotion, isFalse);
      state.setView(reduceMotion: true);
      await t.pumpAndSettle();
      expect(ctx().tokens.reduceMotion, isTrue);
      expect(ctx().tokens.normal, Duration.zero);
      expect(state.user!.settings.reduceMotion, isTrue);
      await t.pumpWidget(const SizedBox());
    });
  });

  // 가장 작은 화면(320×568) + 가장 큰 글씨 + 어두운 모드(그리고 고대비)에서 모든 화면을 끝까지 내려 보며 잘림 확인
  for (final mode in ['dark', 'contrast']) {
    testWidgets('모든 화면 잘림 없음: 작은 화면 + 아주 큰 글씨 + ${mode == 'dark' ? '어두운 모드' : '고대비 어두운 모드'}', (t) async {
      t.view.physicalSize = const Size(320 * 2, 568 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final k = TestKit();
      final state = AppState(k.env);
      await state.login(k.env.accounts.create('긴이름사용자님', '1234'));
      final u = state.user!;
      u.settings.onboardingDone = true;
      state.setTextScale(1.6);
      state.setView(themeMode: 'dark', highContrast: mode == 'contrast');
      // 자료 채우기
      await u.youtube.connectGoogle();
      await u.youtube.syncChannel('UC_mock_cook');
      await u.edits.apply(await u.edits.plan('UC_mock_cook'));
      final ps = productionOf(u);
      final p1 = await ps.create(
        channelId: 'UC_mock_cook',
        format: ContentFormat.long,
        topic: '아주 긴 주제 이름으로 만든 콘텐츠 제목 시험',
      );
      final v = File('${Directory.systemTemp.createTempSync('v').path}/a.mp4')..writeAsBytesSync([1]);
      ps.attachOwnVideo(p1.id, v.path);
      await ps.uploadPrivate(p1.id, userConfirmed: true, aiLabelMethod: 'setting');
      final site = blogOf(u).addTistory('내 티스토리 블로그', 'https://me.tistory.com');
      await blogOf(u).newPost(site.id, topic: '가을');
      final corner = cornerOf(u).create('사장님의 하루', 'UC_mock_cook');
      cornerOf(u).addText(corner.id, '오늘 가게 문을 열었어요.');
      u.memos.add('메모 하나');

      await t.pumpWidget(ChannelBiseoApp(state: state));
      await t.pumpAndSettle();

      Future<void> scrollAll(String where) async {
        final widgets = find.byType(Scrollable).evaluate().map((e) => e.widget as Scrollable).toList();
        for (final st in widgets) {
          if (st.axisDirection != AxisDirection.down) continue;
          final f = find.byWidget(st);
          if (f.evaluate().isEmpty) continue;
          await t.drag(f.first, const Offset(0, -4000), warnIfMissed: false);
          await t.pumpAndSettle();
        }
        expect(t.takeException(), isNull, reason: where);
      }

      Future<void> push(Widget w, String where) async {
        final nav = t.state<NavigatorState>(find.byType(Navigator).first);
        // ignore: unawaited_futures
        nav.push(MaterialPageRoute<void>(builder: (_) => w));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: '$where 열기');
        await scrollAll(where);
        nav.pop();
        await t.pumpAndSettle();
      }

      // 아래 메뉴 화면들
      final tabs = find.descendant(of: find.byType(NavigationBar), matching: find.byType(NavigationDestination));
      final n = tabs.evaluate().length;
      for (var i = 0; i < n; i++) {
        await t.tap(tabs.at(i));
        await t.pumpAndSettle();
        await scrollAll('메뉴 $i');
      }
      // 하위 화면들
      await push(ChannelDetailScreen(user: u, channelId: 'UC_mock_cook'), '채널 상세');
      await push(EditsScreen(user: u), '수정 내역');
      await push(ProductionDetailScreen(user: u, id: p1.id), '제작 상세');
      await push(ReviewScreen(user: u), '확인 대기');
      await push(BlogDetailScreen(user: u, siteId: site.id), '블로그 상세');
      await push(CornerDetailScreen(user: u, cornerId: corner.id), '코너 상세');
      await push(MemosScreen(user: u), '음성 메모');
      await push(ToolsScreen(user: u), '도구 연결');
      await push(CalendarScreen(user: u), '게시 달력');
      // 첫 실행 안내 4단계
      u.settings.onboardingDone = false;
      state.refresh();
      await t.pumpAndSettle();
      for (var step = 0; step < 4; step++) {
        await scrollAll('첫 실행 안내 ${step + 1}');
        if (step < 3) {
          await t.tap(find.byKey(const Key('wizard-next')));
          await t.pumpAndSettle();
        }
      }
      // 로그인 화면
      state.logout();
      await t.pumpAndSettle();
      await scrollAll('로그인');
      await t.pumpWidget(const SizedBox());
    });
  }
}
