import 'dart:async';
import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metaclean/main.dart';
import 'package:personal_assistant/app/assistant_state.dart';
import 'package:personal_assistant/modules/metaclean_module.dart';
import 'package:personal_assistant/modules/registry.dart';
import 'package:personal_assistant/ui/assistant_app.dart';
import 'package:personal_assistant/ui/module_host.dart';

import 'support.dart';

/// 진짜 메타지우개 플러스 화면(apps/metaclean)을 개인비서 홈에서 열어 본다.
void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pa_meta_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> phone(WidgetTester t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  AssistantState stateWith(AssistantModule meta) => AssistantState(
        root: tmp,
        secrets: MemorySecrets(),
        modules: ModuleRegistry([for (final id in ModuleId.values) id == ModuleId.metaclean ? meta : FakeModule(id)]),
      );

  Future<void> login(WidgetTester t) async {
    await t.enterText(find.byKey(const Key('login-name')), '관학');
    await t.enterText(find.byKey(const Key('login-pw')), '1234');
    await t.enterText(find.byKey(const Key('login-pw2')), '1234');
    await t.tap(find.byKey(const Key('login-go')));
    await t.pumpAndSettle();
  }

  final tile = find.byKey(const Key('tile-metaclean'));

  /// 홈 맨 아래 여섯 번째 타일까지 내려서 누른다 (말로 하기 단추에 가리지 않게 끝까지).
  Future<void> openTile(WidgetTester t) async {
    await t.scrollUntilVisible(tile, 300, scrollable: find.byType(Scrollable).first);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await t.pumpAndSettle();
    expect(find.descendant(of: tile, matching: find.text('메타지우개 플러스')), findsOneWidget);
    await t.tap(tile);
    await t.pumpAndSettle();
  }

  test('모듈 목록에 여섯 번째로 들어 있고, 단독 앱 화면을 hostedByAssistant 로 연다', () async {
    final s = AssistantState(root: tmp, secrets: MemorySecrets(), modules: ModuleRegistry([]));
    final reg = ModuleRegistry.device(s);
    expect(reg.all.map((m) => m.id).toList(), ModuleId.values);
    expect(reg.all.length, 6);
    final m = reg.of(ModuleId.metaclean);
    expect(m, isA<MetacleanModule>());
    final w = await m.open();
    expect(w, isA<MetaCleanApp>());
    expect((w as MetaCleanApp).hostedByAssistant, isTrue);
    expect(ModuleId.metaclean.title, '메타지우개 플러스');
    // 자료가 없어 오늘 할 일·검색은 비어 있고, 말로 부르면 화면을 연다
    expect(await m.today(), isEmpty);
    expect(await m.search('사진'), isEmpty);
    final r = await m.handle(const VoiceCommand('메타지우개 열어 줘'));
    expect(r?.openModule, isTrue);
  });

  testWidgets('홈 타일 → 네 탭이 열리고, 업데이트 띠·ⓘ 단추가 없다 → 뒤로·홈', (t) async {
    await phone(t);
    final s = stateWith(MetacleanModule());
    await t.pumpWidget(AssistantApp(state: s));
    await t.pumpAndSettle();
    await login(t);

    await openTile(t);

    // 개인비서 띠 (뒤로 · 모듈 이름 · 개인비서 홈)
    expect(find.byKey(const Key('module-back')), findsOneWidget);
    expect(find.byKey(const Key('module-home')), findsOneWidget);
    // 네 탭 모두
    for (final tab in ['사진 지우기', '사진 수정', '문서', '구매 기록']) {
      expect(find.text(tab), findsOneWidget, reason: tab);
    }
    expect(find.text('사진 고르기 (여러 장 가능)'), findsOneWidget);
    await t.tap(find.text('사진 수정'));
    await t.pumpAndSettle();
    expect(find.text('촬영 위치'), findsOneWidget);
    await t.tap(find.text('문서'));
    await t.pumpAndSettle();
    expect(find.text('문서 고르기'), findsOneWidget);
    await t.tap(find.text('구매 기록'));
    await t.pumpAndSettle();
    expect(find.text('받은 사진 고르기'), findsOneWidget);

    // 단독 앱 업데이트 UI 없음
    expect(find.byTooltip('앱 정보·업데이트'), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsNothing);
    expect(find.textContaining('새 버전이 나왔어요'), findsNothing);

    // 뒤로 → 개인비서 홈
    await t.tap(find.byKey(const Key('module-back')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('home-mic')), findsOneWidget);
    expect(find.byKey(const Key('module-back')), findsNothing);

    // 다시 열고 개인비서 홈 단추
    await openTile(t);
    expect(find.text('사진 지우기'), findsOneWidget);
    await t.tap(find.byKey(const Key('module-home')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('home-mic')), findsOneWidget);
    expect(find.byKey(const Key('module-back')), findsNothing);
  });

  testWidgets('정식 빌드 번호가 있어도 개인비서 안에서는 새 버전을 묻지 않는다', (t) async {
    await phone(t);
    var asked = 0;
    final s = stateWith(MetacleanModule(
      app: () => MetaCleanApp(
        hostedByAssistant: true,
        currentBuild: 60,
        currentVersion: '2.2.0',
        updateFetch: (_) async {
          asked++;
          return '{"build": 99, "version": "9.0.0", "notes": "새 기능"}';
        },
      ),
    ));
    await t.pumpWidget(AssistantApp(state: s));
    await t.pumpAndSettle();
    await login(t);
    await openTile(t);
    expect(find.text('사진 지우기'), findsOneWidget);
    expect(asked, 0);
    expect(find.textContaining('새 버전이 나왔어요'), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsNothing);
  });

  testWidgets('360 너비 + 아주 큰 글씨 + 어둡게·고대비: 메타지우개 네 탭이 넘치지 않고, 단추는 52·17 굵게', (t) async {
    t.view.physicalSize = const Size(720, 1280); // 360 × 640
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final s = stateWith(MetacleanModule());
    s.settings
      ..textSize = TextSize.huge
      ..themeMode = 'dark'
      ..highContrast = true;
    await s.login(s.auth.create('관학', '1234'));
    await t.pumpWidget(AssistantApp(state: s));
    await t.pumpAndSettle();
    unawaited(ModuleHost.push(t.element(find.byKey(const PageStorageKey('home-list'))), s, ModuleId.metaclean));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    // 개인비서 글씨 크기가 모듈 안까지 그대로 (1.5배)
    expect(MediaQuery.textScalerOf(t.element(find.text('사진 지우기'))).scale(10), closeTo(15, 0.001));
    for (final tab in ['사진 수정', '문서', '구매 기록', '사진 지우기']) {
      await t.tap(find.text(tab));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: tab);
    }
    final pick = find.ancestor(of: find.text('사진 고르기 (여러 장 가능)'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
    expect(t.getSize(pick).height, greaterThanOrEqualTo(52));
    final label = t.widget<RichText>(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == '사진 고르기 (여러 장 가능)'));
    expect(label.text.style!.fontSize, 17);
    expect(label.text.style!.fontWeight, FontWeight.w700);
  });
}
