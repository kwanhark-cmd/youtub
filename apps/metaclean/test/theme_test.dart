import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metaclean/main.dart';
import 'package:metaclean/src/app_theme.dart';
import 'package:metaclean/src/edit_screen.dart';
import 'package:metaclean/src/photo_edit.dart';
import 'package:metaclean/src/stamp_screen.dart';

/// 잘 보이게: 단추 52·글자 17 굵게·명암비 7:1(눌렀을 때도)·2px 테두리·본문 16,
/// 그리고 360×740 화면에서 글씨를 키워도(개인비서 "아주 크게" 1.5배까지) 넘치지 않는다.
void main() {
  final theme = MetaTheme.build();
  final s = theme.colorScheme;
  final grounds = MetaTheme.grounds(s);
  const none = <WidgetState>{};
  const pressed = {WidgetState.pressed};
  double cr(Color a, Color b) => MetaTheme.contrast(a, b);

  test('앱이 이 테마를 쓴다', () {
    final app = const MetaCleanApp().build(_FakeContext()) as MaterialApp;
    expect(app.theme!.filledButtonTheme.style!.minimumSize!.resolve(none)!.height, 52);
  });

  test('채운 단추·빨강 단추: 글자/바탕 7:1 이상, 눌렀을 때도 7:1 이고 눈에 띄게 바뀐다', () {
    for (final st in [theme.filledButtonTheme.style!, MetaTheme.danger(s)]) {
      final bg = st.backgroundColor!.resolve(none)!;
      final fg = st.foregroundColor!.resolve(none)!;
      expect(cr(fg, bg), greaterThanOrEqualTo(7));
      final down = Color.alphaBlend(st.overlayColor!.resolve(pressed)!, bg);
      expect(cr(fg, down), greaterThanOrEqualTo(7));
      expect(cr(down, bg), greaterThan(1.15));
    }
    final red = HSVColor.fromColor(MetaTheme.dangerColor());
    expect(red.hue < 20 || red.hue > 340, isTrue);
    expect(red.saturation, greaterThan(0.4));
  });

  test('테두리·글자 단추: 2px 테두리, 글자 7:1 (눌렀을 때도), 초점이면 더 굵게', () {
    final o = theme.outlinedButtonTheme.style!;
    final tb = theme.textButtonTheme.style!;
    expect(o.side!.resolve(none)!.width, greaterThanOrEqualTo(2));
    expect(o.side!.resolve({WidgetState.focused})!.width, greaterThan(2));
    for (final g in grounds) {
      expect(cr(o.side!.resolve(none)!.color, g), greaterThanOrEqualTo(4.5));
      for (final st in [o, tb]) {
        final fg = st.foregroundColor!.resolve(none)!;
        expect(cr(fg, g), greaterThanOrEqualTo(7));
        expect(cr(fg, Color.alphaBlend(st.overlayColor!.resolve(pressed)!, g)), greaterThanOrEqualTo(7));
      }
    }
  });

  test('나뉜 단추: 고른 칸 진한 바탕 7:1 (눌렀을 때도), 안 고른 칸 7:1, 2px 테두리', () {
    final st = theme.segmentedButtonTheme.style!;
    const sel = {WidgetState.selected};
    final bg = st.backgroundColor!.resolve(sel)!;
    final fg = st.foregroundColor!.resolve(sel)!;
    expect(cr(fg, bg), greaterThanOrEqualTo(7));
    expect(cr(fg, Color.alphaBlend(st.overlayColor!.resolve({...sel, ...pressed})!, bg)), greaterThanOrEqualTo(7));
    for (final g in grounds) {
      expect(cr(st.foregroundColor!.resolve(none)!, g), greaterThanOrEqualTo(7));
    }
    expect(st.side!.resolve(none)!.width, greaterThanOrEqualTo(2));
  });

  test('본문 16 이상, 글자색은 바탕과 7:1 이상 (흐린 회색 없음), 탭 글자도 7:1', () {
    final t = theme.textTheme;
    for (final x in [t.bodyLarge!, t.bodyMedium!, t.bodySmall!]) {
      expect(x.fontSize, greaterThanOrEqualTo(16));
      for (final g in grounds) {
        expect(cr(x.color!, g), greaterThanOrEqualTo(7));
      }
    }
    for (final g in grounds) {
      expect(cr(s.onSurfaceVariant, g), greaterThanOrEqualTo(7));
      expect(cr(theme.tabBarTheme.unselectedLabelColor!, g), greaterThanOrEqualTo(7));
      expect(cr(theme.tabBarTheme.labelColor!, g), greaterThanOrEqualTo(7));
    }
    expect(cr(s.onPrimaryContainer, s.primaryContainer), greaterThanOrEqualTo(7));
    expect(cr(s.onSecondaryContainer, s.secondaryContainer), greaterThanOrEqualTo(7));
    expect(theme.listTileTheme.subtitleTextStyle!.fontSize, greaterThanOrEqualTo(16));
  });

  test('단추 크기: 높이 52·너비 48 이상, 글자 17 굵게, 아이콘 단추 48', () {
    for (final st in [
      theme.filledButtonTheme.style!,
      theme.outlinedButtonTheme.style!,
      theme.textButtonTheme.style!,
      theme.elevatedButtonTheme.style!,
    ]) {
      final min = st.minimumSize!.resolve(none)!;
      expect(min.height, greaterThanOrEqualTo(52));
      expect(min.width, greaterThanOrEqualTo(48));
      final ts = st.textStyle!.resolve(none)!;
      expect(ts.fontSize, greaterThanOrEqualTo(17));
      expect(ts.fontWeight, FontWeight.w700);
    }
    expect(theme.segmentedButtonTheme.style!.textStyle!.resolve(none)!.fontSize, greaterThanOrEqualTo(17));
    expect(theme.iconButtonTheme.style!.minimumSize!.resolve(none)!.shortestSide, greaterThanOrEqualTo(48));
  });

  /// 화면에 보이는 단추가 모두 높이 52 이상인지
  void buttonsTall(WidgetTester t) {
    for (final type in ['FilledButton', 'OutlinedButton', 'TextButton', 'SegmentedButton']) {
      for (final e in find.byWidgetPredicate((w) => w.runtimeType.toString().startsWith(type)).evaluate()) {
        final box = e.renderObject as RenderBox?;
        if (box == null || !box.hasSize || !box.attached) continue;
        expect(box.size.height, greaterThanOrEqualTo(51.99), reason: '${e.widget}');
      }
    }
  }

  Future<void> scrollDown(WidgetTester t, Type screen) async {
    final list = find.descendant(of: find.byType(screen), matching: find.byType(Scrollable)).first;
    for (var i = 0; i < 6; i++) {
      await t.drag(list, const Offset(0, -400));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      buttonsTall(t);
    }
  }

  for (final scale in [1.0, 1.25, 1.5]) {
    for (final hosted in [false, true]) {
      testWidgets('360×740 · 글씨 $scale배 · ${hosted ? '개인비서 안' : '단독 앱 + 새 버전 띠'}: 네 탭 모두 넘치지 않는다', (t) async {
        await t.binding.setSurfaceSize(const Size(360, 740));
        addTearDown(() => t.binding.setSurfaceSize(null));
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await t.pumpWidget(MetaCleanApp(
          hostedByAssistant: hosted,
          currentBuild: 60,
          updateFetch: (_) async => '{"build": 61, "version": "2.3.0", "notes": "· 새 기능"}',
        ));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(MediaQuery.textScalerOf(t.element(find.text('사진 지우기'))).scale(10), closeTo(10 * scale, 0.001));
        expect(find.textContaining('새 버전이 나왔어요'), hosted ? findsNothing : findsOneWidget);
        buttonsTall(t);

        // 사진 수정: 세 항목 모두 "바꾸기"로 펼친다
        await t.tap(find.text('사진 수정'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        buttonsTall(t);
        for (final seg in [find.byType(SegmentedButton<DateAction>), find.byType(SegmentedButton<GpsAction>), find.byType(SegmentedButton<DeviceAction>)]) {
          await t.scrollUntilVisible(seg, 200,
              scrollable: find.descendant(of: find.byType(EditScreen), matching: find.byType(Scrollable)).first);
          await t.pumpAndSettle();
          await t.tap(find.descendant(of: seg, matching: find.text('바꾸기')));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          buttonsTall(t);
        }
        await scrollDown(t, EditScreen);

        await t.tap(find.text('문서'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        buttonsTall(t);

        await t.tap(find.text('구매 기록'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        buttonsTall(t);
        await scrollDown(t, StampScreen);

        await t.tap(find.text('사진 지우기'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        // 큰 단추 글자는 17 굵게
        final label = t.widget<RichText>(find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == '사진 고르기 (여러 장 가능)'));
        expect(label.text.style!.fontSize, 17);
        expect(label.text.style!.fontWeight, FontWeight.w700);
      });
    }
  }

  // 사진 수정의 세 갈래 단추: 고른 칸에 체크 표시가 붙으며 "그대/로", "바꾸/기"처럼
  // 두 줄로 꺾이던 문제 (360dp 폰). 한 줄로, 글자는 17 이상으로 보여야 한다.
  for (final scale in [1.0, 1.15, 1.3, 1.5]) {
    testWidgets('360 폭 · 글씨 $scale배: 나뉜 단추 글자가 두 줄로 꺾이지 않는다', (t) async {
      // 폭은 좁은 폰(360)과 같게, 세 단추가 한꺼번에 보이도록 높이만 넉넉하게.
      await t.binding.setSurfaceSize(const Size(360, 2400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpWidget(MaterialApp(
        theme: MetaTheme.build(),
        home: Scaffold(body: EditScreen(deviceLookup: () async => null)),
      ));
      await t.pumpAndSettle();

      Future<void> check() async {
        final segs = find.byWidgetPredicate((w) => w is SegmentedButton);
        expect(segs, findsNWidgets(3));
        // 고른 칸에도 체크 표시가 없다
        expect(find.descendant(of: segs, matching: find.byIcon(Icons.check)), findsNothing);
        final labels = find.descendant(of: segs, matching: find.byType(SegmentLabel));
        expect(labels, findsNWidgets(9));
        for (final e in labels.evaluate()) {
          final para = t.renderObject<RenderParagraph>(
              find.descendant(of: find.byWidget(e.widget), matching: find.byType(RichText)).first);
          final text = para.text.toPlainText();
          final one = TextPainter(
            text: para.text,
            textDirection: TextDirection.ltr,
            textScaler: para.textScaler,
          )..layout();
          // 한 줄 높이 그대로 (두 줄이면 두 배)
          expect(para.size.height, closeTo(one.height, 0.5), reason: text);
          expect(para.didExceedMaxLines, isFalse, reason: text);
          // 칸에 맞추느라 줄였더라도 실제 글자는 17 이상
          final box = e.renderObject as RenderBox;
          final shrink = box.size.width / para.size.width;
          final shown = MetaTheme.labelSize * scale * (shrink < 1 ? shrink : 1);
          expect(shown, greaterThanOrEqualTo(MetaTheme.labelSize), reason: '$text ${shown.toStringAsFixed(1)}');
          // 칸 밖으로 삐져나오지 않는다
          final seg = t.getRect(find.ancestor(of: find.byWidget(e.widget), matching: find.byType(InkWell)).first);
          final r = t.getRect(find.byWidget(e.widget));
          expect(seg.left <= r.left + 0.5 && r.right <= seg.right + 0.5, isTrue, reason: text);
        }
      }

      await check();
      // 모두 "바꾸기"를 골라도 마찬가지
      for (final type in [SegmentedButton<DateAction>, SegmentedButton<GpsAction>, SegmentedButton<DeviceAction>]) {
        final seg = find.byType(type);
        await t.ensureVisible(seg);
        await t.pumpAndSettle();
        await t.tap(find.descendant(of: seg, matching: find.text('바꾸기')));
        await t.pumpAndSettle();
      }
      expect(t.takeException(), isNull);
      await check();
    });
  }

  testWidgets('360×740 · 1.5배: 앱 정보·업데이트 창도 넘치지 않는다', (t) async {
    await t.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => t.binding.setSurfaceSize(null));
    t.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(MetaCleanApp(
      currentBuild: 60,
      currentVersion: '2.2.0',
      updateFetch: (_) async => '{"build": 61, "version": "2.3.0", "notes": "· 새 기능"}',
    ));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('앱 정보·업데이트'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    buttonsTall(t);
  });
}

class _FakeContext extends Fake implements BuildContext {}
