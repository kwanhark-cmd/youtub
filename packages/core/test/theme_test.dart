import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 개인비서 모든 테마(밝게·어둡게 × 보통·고대비)에서 "잘 보이게" 규칙을 지키는지.
void main() {
  const pressed = {WidgetState.pressed};
  const none = <WidgetState>{};

  for (final dark in [false, true]) {
    for (final hc in [false, true]) {
      final name = '${dark ? '어둡게' : '밝게'}${hc ? '+고대비' : ''}';
      final theme = AssistantTheme.build(brightness: dark ? Brightness.dark : Brightness.light, highContrast: hc);
      final s = theme.colorScheme;
      final grounds = AssistantTheme.grounds(s, highContrast: hc);

      group(name, () {
        test('채운 단추: 글자/바탕 7:1 이상 (눌렀을 때도)', () {
          final st = theme.filledButtonTheme.style!;
          final bg = st.backgroundColor!.resolve(none)!;
          final fg = st.foregroundColor!.resolve(none)!;
          expect(contrastRatio(fg, bg), greaterThanOrEqualTo(7));
          final down = Color.alphaBlend(st.overlayColor!.resolve(pressed)!, st.backgroundColor!.resolve(pressed)!);
          expect(contrastRatio(st.foregroundColor!.resolve(pressed)!, down), greaterThanOrEqualTo(7));
          // 눌렀다는 것이 눈에 보인다
          expect(contrastRatio(down, bg), greaterThan(1.15));
          expect(contrastRatio(st.foregroundColor!.resolve(pressed)!, down), greaterThanOrEqualTo(7));
        });

        test('빨강(지우기) 단추: 7:1 이상, 눌러도 7:1, 분명한 빨강', () {
          final st = AssistantTheme.danger(s);
          final bg = st.backgroundColor!.resolve(none)!;
          final fg = st.foregroundColor!.resolve(none)!;
          expect(contrastRatio(fg, bg), greaterThanOrEqualTo(7));
          final down = Color.alphaBlend(st.overlayColor!.resolve(pressed)!, bg);
          expect(contrastRatio(fg, down), greaterThanOrEqualTo(7));
          final hsv = HSVColor.fromColor(bg);
          expect(hsv.hue < 20 || hsv.hue > 340, isTrue, reason: 'hue ${hsv.hue}');
          expect(hsv.saturation, greaterThan(0.4));
        });

        test('테두리·글자 단추: 2px 진한 테두리, 바탕 위 글자 7:1 (눌렀을 때도)', () {
          final o = theme.outlinedButtonTheme.style!;
          final side = o.side!.resolve(none)!;
          expect(side.width, greaterThanOrEqualTo(2));
          final tb = theme.textButtonTheme.style!;
          for (final g in grounds) {
            expect(contrastRatio(side.color, g), greaterThanOrEqualTo(4.5));
            for (final st in [o, tb]) {
              final fg = st.foregroundColor!.resolve(none)!;
              expect(contrastRatio(fg, g), greaterThanOrEqualTo(7));
              final down = Color.alphaBlend(st.overlayColor!.resolve(pressed)!, g);
              expect(contrastRatio(st.foregroundColor!.resolve(pressed)!, down), greaterThanOrEqualTo(7));
            }
          }
          expect(o.side!.resolve({WidgetState.focused})!.width, greaterThan(side.width));
        });

        test('나뉜 단추(SegmentedButton): 고른 칸 7:1, 안 고른 칸 7:1, 2px 테두리', () {
          final st = theme.segmentedButtonTheme.style!;
          const sel = {WidgetState.selected};
          final bg = st.backgroundColor!.resolve(sel)!;
          expect(contrastRatio(st.foregroundColor!.resolve(sel)!, bg), greaterThanOrEqualTo(7));
          final down = Color.alphaBlend(st.overlayColor!.resolve({...sel, ...pressed})!, bg);
          expect(contrastRatio(st.foregroundColor!.resolve(sel)!, down), greaterThanOrEqualTo(7));
          for (final g in grounds) {
            expect(contrastRatio(st.foregroundColor!.resolve(none)!, g), greaterThanOrEqualTo(7));
          }
          expect(st.side!.resolve(none)!.width, greaterThanOrEqualTo(2));
        });

        test('본문·보조 글: 16 이상, 바탕과 7:1 이상 (흐린 회색 없음)', () {
          final t = theme.textTheme;
          for (final x in [t.bodyLarge, t.bodyMedium, t.bodySmall]) {
            expect(x!.fontSize, greaterThanOrEqualTo(16));
            for (final g in grounds) {
              expect(contrastRatio(x.color!, g), greaterThanOrEqualTo(7));
            }
          }
          for (final g in grounds) {
            expect(contrastRatio(s.onSurfaceVariant, g), greaterThanOrEqualTo(7));
            expect(contrastRatio(s.onSurface, g), greaterThanOrEqualTo(7));
          }
          expect(theme.listTileTheme.subtitleTextStyle!.fontSize, greaterThanOrEqualTo(16));
          expect(contrastRatio(s.onSecondaryContainer, s.secondaryContainer), greaterThanOrEqualTo(7));
          expect(contrastRatio(s.onPrimaryContainer, s.primaryContainer), greaterThanOrEqualTo(7));
        });

        test('단추 크기: 높이 52, 글자 17 굵게, 누르는 자리 48 이상', () {
          for (final st in [
            theme.filledButtonTheme.style!,
            theme.outlinedButtonTheme.style!,
            theme.textButtonTheme.style!,
            theme.segmentedButtonTheme.style!,
            theme.elevatedButtonTheme.style!,
          ]) {
            final min = st.minimumSize!.resolve(none)!;
            expect(min.height, greaterThanOrEqualTo(52));
            expect(min.width, greaterThanOrEqualTo(48));
            final ts = st.textStyle!.resolve(none)!;
            expect(ts.fontSize, greaterThanOrEqualTo(17));
            expect(ts.fontWeight!.value, greaterThanOrEqualTo(700));
          }
          expect(theme.iconButtonTheme.style!.minimumSize!.resolve(none)!.shortestSide, greaterThanOrEqualTo(48));
          expect(theme.textTheme.labelLarge!.fontSize, greaterThanOrEqualTo(17));
        });

        for (final size in TextSize.values) {
          testWidgets('360 너비 + 글씨 ${size.label}: 단추가 52 이상이고 넘치지 않는다', (tester) async {
            tester.view.physicalSize = const Size(720, 1480);
            tester.view.devicePixelRatio = 2;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(MaterialApp(
              theme: theme,
              builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(size.scale)), child: child!),
              home: Scaffold(
                body: ListView(padding: const EdgeInsets.all(16), children: [
                  FilledButton(key: const Key('f'), onPressed: () {}, child: const Text('저장')),
                  OutlinedButton(key: const Key('o'), onPressed: () {}, child: const Text('갤러리에 저장')),
                  TextButton(key: const Key('t'), onPressed: () {}, child: const Text('취소')),
                  FilledButton(key: const Key('d'), style: AssistantTheme.danger(s), onPressed: () {}, child: const Text('지우기')),
                  IconButton(key: const Key('i'), onPressed: () {}, icon: const Icon(Icons.settings)),
                  SegmentedButton<int>(
                    key: const Key('seg'),
                    segments: [for (final v in TextSize.values) ButtonSegment(value: v.index, label: Text(v.label))],
                    selected: const {0},
                    onSelectionChanged: (_) {},
                  ),
                ]),
              ),
            ));
            expect(tester.takeException(), isNull);
            for (final k in ['f', 'o', 't', 'd']) {
              expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(52), reason: k);
            }
            expect(tester.getSize(find.byKey(const Key('i'))).shortestSide, greaterThanOrEqualTo(48));
            expect(tester.getSize(find.byKey(const Key('seg'))).height, greaterThanOrEqualTo(52));
            // 단추 글자는 17 굵게
            final label = tester.widget<RichText>(find.descendant(of: find.byKey(const Key('f')), matching: find.byType(RichText)));
            expect(label.text.style!.fontSize, greaterThanOrEqualTo(17));
            expect(label.text.style!.fontWeight, FontWeight.w700);
          });
        }
      });
    }
  }

  test('명암비 도우미', () {
    expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
    final c = ensureContrast(const Color(0xFF8888FF), [Colors.white]);
    expect(contrastRatio(c, Colors.white), greaterThanOrEqualTo(7));
    expect(ensureContrast(Colors.black, [Colors.white]), Colors.black);
  });
}
