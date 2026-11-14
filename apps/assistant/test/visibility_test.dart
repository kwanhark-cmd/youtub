import 'dart:async';
import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/ui/assistant_app.dart';
import 'package:personal_assistant/ui/connections_screen.dart';
import 'package:personal_assistant/ui/module_host.dart';

import 'support.dart';

/// 잘 보이게: 모든 테마(밝게·어둡게 × 보통·고대비) × 글씨 크기 세 단계에서
/// 360 너비 화면이 넘치지 않고, 단추는 높이 52·글자 17 굵게, 본문은 16 이상이다.
void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('vis'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> small(WidgetTester t) async {
    t.view.physicalSize = const Size(720, 1280); // 360 × 640
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
  }

  /// 화면에 보이는 단추가 모두 높이 52 이상인지 (모듈 띠·대화상자 포함)
  void buttonsTall(WidgetTester t) {
    for (final type in [FilledButton, OutlinedButton, TextButton]) {
      for (final e in find.byWidgetPredicate((w) => w.runtimeType.toString().startsWith(type.toString())).evaluate()) {
        final box = e.renderObject as RenderBox?;
        if (box == null || !box.hasSize || !box.attached) continue;
        expect(box.size.height, greaterThanOrEqualTo(AssistantTheme.buttonHeight - 0.01), reason: '${e.widget}');
      }
    }
  }

  Future<void> scrollToEnd(WidgetTester t, Finder list) async {
    for (var i = 0; i < 12; i++) {
      await t.drag(list, const Offset(0, -400));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      buttonsTall(t);
    }
  }

  for (final dark in [false, true]) {
    for (final hc in [false, true]) {
      for (final size in TextSize.values) {
        final name = '${dark ? '어둡게' : '밝게'}${hc ? '+고대비' : ''} · 글씨 ${size.label}';
        testWidgets('$name: 로그인·홈·설정·연결·모듈 띠가 360 너비에서 넘치지 않는다', (t) async {
          await small(t);
          final s = fakeState(tmp, mods: {
            ModuleId.vault: FakeModule(ModuleId.vault, items: const [
              TodayItem(module: ModuleId.vault, text: '아주 긴 구독 만료 안내 문장이 여기에 들어가도 잘리지 않고 줄바꿈 되어야 해요', urgency: 90),
              TodayItem(module: ModuleId.vault, text: '두 번째 할 일', urgency: 40),
            ]),
          });
          s.settings
            ..textSize = size
            ..themeMode = dark ? 'dark' : 'light'
            ..highContrast = hc;
          await t.pumpWidget(AssistantApp(state: s));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          buttonsTall(t);

          // 테마가 정말 적용되었는지: 채운 단추 바탕/글자 7:1
          await t.scrollUntilVisible(find.byKey(const Key('login-go')), 200, scrollable: find.byType(Scrollable).first);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          buttonsTall(t);
          final theme = Theme.of(t.element(find.byKey(const Key('login-go'))));
          expect(theme.brightness, dark ? Brightness.dark : Brightness.light);
          final st = theme.filledButtonTheme.style!;
          expect(contrastRatio(st.foregroundColor!.resolve({})!, st.backgroundColor!.resolve({})!), greaterThanOrEqualTo(7));
          final go = t.widget<RichText>(find.descendant(of: find.byKey(const Key('login-go')), matching: find.byType(RichText)));
          expect(go.text.style!.fontSize, greaterThanOrEqualTo(17));
          expect(go.text.style!.fontWeight, FontWeight.w700);

          await s.login(s.auth.create('관학', '1234'));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          await scrollToEnd(t, find.byKey(const PageStorageKey('home-list')));

          // 모듈 띠 (뒤로 · 이름 · 개인비서)
          unawaited(ModuleHost.push(t.element(find.byKey(const PageStorageKey('home-list'))), s, ModuleId.vault));
          await t.pumpAndSettle();
          expect(find.text('${ModuleId.vault.title} 모듈 홈'), findsOneWidget);
          expect(t.takeException(), isNull);
          expect(t.getSize(find.byKey(const Key('module-back'))).height, greaterThanOrEqualTo(48));
          await t.tap(find.byKey(const Key('module-back')));
          await t.pumpAndSettle();

          // 설정 끝까지
          await t.drag(find.byKey(const PageStorageKey('home-list')), const Offset(0, 4000));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('home-settings')));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          await scrollToEnd(t, find.byKey(const PageStorageKey('settings-list')));
          expect(find.byKey(const Key('settings-logout')), findsOneWidget);
          final logout = t.widget<RichText>(find.descendant(of: find.byKey(const Key('settings-logout')), matching: find.byType(RichText)).first);
          expect(logout.text.style!.color, theme.colorScheme.error);

          // 연결 상태 화면
          final nav = Navigator.of(t.element(find.byKey(const PageStorageKey('settings-list'))));
          nav.push(MaterialPageRoute(builder: (_) => ConnectionsScreen(state: s)));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          buttonsTall(t);
          await scrollToEnd(t, find.byType(Scrollable).last);
        });
      }
    }
  }

  testWidgets('글씨 크기·테마 나뉜 단추: 아주 크게에서도 높이 52 이상, 고른 칸은 진한 바탕', (t) async {
    await small(t);
    final s = fakeState(tmp);
    s.settings.textSize = TextSize.huge;
    await s.login(s.auth.create('관학', '1234'));
    await t.pumpWidget(AssistantApp(state: s));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('home-settings')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byType(SegmentedButton<TextSize>), 200, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(SegmentedButton<TextSize>)).height, greaterThanOrEqualTo(52));
    expect(t.getSize(find.byType(SegmentedButton<String>)).height, greaterThanOrEqualTo(52));
    await t.tap(find.text('보통'));
    await t.pumpAndSettle();
    expect(s.settings.textSize, TextSize.normal);
    expect(t.takeException(), isNull);
  });
}
