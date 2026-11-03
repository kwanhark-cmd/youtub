import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/ui/assistant_app.dart';

import 'support.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('flow'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> bigScreen(WidgetTester t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
  }

  testWidgets('통합 흐름: 로그인 → 홈 → 모듈 열기·뒤로·홈 → 음성 → 브리핑 → 검색 → 제안', (t) async {
    await bigScreen(t);
    final vault = FakeModule(ModuleId.vault,
        items: const [TodayItem(module: ModuleId.vault, text: '힉스필드 크레딧 2일 뒤 만료', urgency: 95)],
        hits: const [SearchHit(module: ModuleId.vault, title: '넷플릭스 구독'), SearchHit(module: ModuleId.vault, title: '넷플릭스 비밀번호', kind: 'password')],
        reply: '힉스필드는 2일 뒤 끝나요.');
    final channel = FakeModule(ModuleId.channel,
        items: const [TodayItem(module: ModuleId.channel, text: '확인 대기 영상 2개', urgency: 60)],
        hits: const [SearchHit(module: ModuleId.channel, title: '넷플릭스 리뷰 영상')]);
    final s = fakeState(tmp, mods: {ModuleId.vault: vault, ModuleId.channel: channel});
    await t.pumpWidget(AssistantApp(state: s));
    await t.pumpAndSettle();

    // 처음: 사용자 만들기
    expect(find.text('처음 오셨네요! 반가워요'), findsOneWidget);
    await t.enterText(find.byKey(const Key('login-name')), '관학');
    await t.enterText(find.byKey(const Key('login-pw')), '1234');
    await t.enterText(find.byKey(const Key('login-pw2')), '1234');
    await t.tap(find.byKey(const Key('login-go')));
    await t.pumpAndSettle();
    expect(find.text('안녕하세요, 관학님'), findsOneWidget);

    // 오늘 할 일: 가장 급한 것이 크게
    expect(find.descendant(of: find.byKey(const Key('today-top')), matching: find.text('힉스필드 크레딧 2일 뒤 만료')), findsOneWidget);
    expect(find.text('확인 대기 영상 2개'), findsOneWidget);
    for (final m in ModuleId.values) {
      expect(find.byKey(Key('tile-${m.name}')), findsOneWidget);
    }

    // 모듈 열기 → 모듈 안 화면 → 뒤로(모듈 안에서 한 단계) → 개인비서 홈
    await t.tap(find.byKey(const Key('tile-channel')));
    await t.pumpAndSettle();
    expect(find.text('채널 관리 모듈 홈'), findsOneWidget);
    await t.tap(find.text('더 보기'));
    await t.pumpAndSettle();
    expect(find.text('모듈 안 두 번째 화면'), findsOneWidget);
    await t.tap(find.byKey(const Key('module-back')));
    await t.pumpAndSettle();
    expect(find.text('채널 관리 모듈 홈'), findsOneWidget);
    await t.tap(find.byKey(const Key('module-home')));
    await t.pumpAndSettle();
    expect(find.text('안녕하세요, 관학님'), findsOneWidget);
    expect(channel.opened, 1);

    // 음성(글자 입력으로 대체) → 금고 모듈이 답함
    await t.tap(find.byKey(const Key('home-mic')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('voice-text')), '힉스필드 언제 끝나');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pumpAndSettle();
    expect(find.text('힉스필드는 2일 뒤 끝나요.'), findsOneWidget);

    // 브리핑
    await t.enterText(find.byKey(const Key('voice-text')), '아침 브리핑');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pumpAndSettle();
    final answer = t.widget<Text>(find.byKey(const Key('voice-answer'))).data!;
    expect(answer, contains('관학님'));
    expect(answer, contains('확인 대기 영상 2개'));
    expect(answer, contains('힉스필드'));

    // 애매한 말 → 두 버튼
    await t.enterText(find.byKey(const Key('voice-text')), '구독 채널');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '채널 관리'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '계정·구독 금고'), findsOneWidget);

    // 비밀번호는 읽지 않음
    await t.enterText(find.byKey(const Key('voice-text')), '넷플릭스 비밀번호 읽어 줘');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pumpAndSettle();
    expect(find.textContaining('비밀번호는 소리로 읽지 않아요'), findsOneWidget);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    // 통합 검색: 비밀번호 결과는 나오지 않음
    await t.enterText(find.byKey(const Key('home-search')), '넷플릭스');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(find.text('넷플릭스 구독'), findsOneWidget);
    expect(find.text('넷플릭스 리뷰 영상'), findsOneWidget);
    expect(find.text('넷플릭스 비밀번호'), findsNothing);
    t.state<NavigatorState>(find.byType(Navigator).first).pop();
    await t.pumpAndSettle();

    // 모듈 사이 연결: 제안 → 받기 → 받는 모듈에 들어감
    s.links.propose(Suggestion(id: 'd1', kind: LinkKind.declutterToChannel, from: ModuleId.declutter, to: ModuleId.channel, title: '할머니 의자 사연'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('제안함'));
    await t.pumpAndSettle();
    await t.tap(find.text('받기'));
    await t.pumpAndSettle();
    expect(channel.received.single.title, '할머니 의자 사연');
    expect(s.links.pending, isEmpty);
  });

  testWidgets('자동 로그인이면 바로 홈, 로그아웃하면 로그인 화면', (t) async {
    await bigScreen(t);
    final s = fakeState(tmp);
    final u = s.auth.create('관학', '1234');
    await s.auth.setAutoLogin(u, true);
    await s.start();
    await t.pumpWidget(AssistantApp(state: s));
    await t.pumpAndSettle();
    expect(find.text('안녕하세요, 관학님'), findsOneWidget);
    await s.logout();
    await t.pumpAndSettle();
    expect(find.text('다시 만나 반가워요'), findsOneWidget);
    await t.enterText(find.byKey(const Key('login-pw')), '0000');
    await t.tap(find.byKey(const Key('login-go')));
    await t.pumpAndSettle();
    expect(find.text('비밀번호가 맞지 않아요.'), findsOneWidget);
  });

  testWidgets('모듈 열기 실패 → 안내 + 다시 시도', (t) async {
    await bigScreen(t);
    final bad = _Flaky(ModuleId.declutter);
    final s = fakeState(tmp, mods: {ModuleId.declutter: bad});
    await s.login(s.auth.create('관학', '1234'));
    await t.pumpWidget(AssistantApp(state: s));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('tile-declutter')));
    await t.pumpAndSettle();
    expect(find.textContaining('열지 못했어요'), findsOneWidget);
    await t.tap(find.text('다시 시도'));
    await t.pumpAndSettle();
    expect(find.text('물건 비우기 모듈 홈'), findsOneWidget);
  });

  for (final size in [TextSize.huge]) {
    for (final dark in [false, true]) {
      testWidgets('작은 화면 + 아주 큰 글씨 + ${dark ? '어두운' : '밝은'} + 고대비: 넘침 없음', (t) async {
        t.view.physicalSize = const Size(720, 1280);
        t.view.devicePixelRatio = 2.0;
        addTearDown(t.view.reset);
        final s = fakeState(tmp, mods: {
          ModuleId.vault: FakeModule(ModuleId.vault, items: const [TodayItem(module: ModuleId.vault, text: '아주 긴 구독 만료 안내 문장이 여기에 들어가도 잘리지 않고 줄바꿈 되어야 해요', urgency: 90)]),
        });
        s.settings
          ..textSize = size
          ..themeMode = dark ? 'dark' : 'light'
          ..highContrast = true;
        await s.login(s.auth.create('관학', '1234'));
        await t.pumpWidget(AssistantApp(state: s));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.tap(find.byKey(const Key('home-settings')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('업데이트 확인'), findsOneWidget);
      });
    }
  }

  testWidgets('설정의 글씨 크기는 모든 화면에 바로 적용', (t) async {
    await bigScreen(t);
    final s = fakeState(tmp);
    await s.login(s.auth.create('관학', '1234'));
    await t.pumpWidget(AssistantApp(state: s));
    await t.pumpAndSettle();
    s.settings.textSize = TextSize.large;
    await t.pumpAndSettle();
    final ctx = t.element(find.text('안녕하세요, 관학님'));
    expect(MediaQuery.textScalerOf(ctx).scale(10), 12.5);
  });

  testWidgets('홈 스크롤 위치는 설정에 다녀와도 유지', (t) async {
    t.view.physicalSize = const Size(720, 1100);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    final s = fakeState(tmp, mods: {
      ModuleId.vault: FakeModule(ModuleId.vault, items: [for (var i = 0; i < 6; i++) TodayItem(module: ModuleId.vault, text: '할 일 $i', urgency: 50 - i)]),
    });
    await s.login(s.auth.create('관학', '1234'));
    await t.pumpWidget(AssistantApp(state: s));
    await t.pumpAndSettle();
    final list = find.byKey(const PageStorageKey('home-list'));
    await t.drag(list, const Offset(0, -300));
    await t.pumpAndSettle();
    final before = t.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)).first).position.pixels;
    expect(before, greaterThan(0));
    t.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('다른 화면'))));
    await t.pumpAndSettle();
    expect(find.text('다른 화면'), findsOneWidget);
    t.state<NavigatorState>(find.byType(Navigator).first).pop();
    await t.pumpAndSettle();
    final after = t.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)).first).position.pixels;
    expect(after, before);
  });
}

class _Flaky extends FakeModule {
  _Flaky(super.id);
  int n = 0;
  @override
  Future<Widget> open() async {
    if (n++ == 0) throw StateError('처음엔 실패');
    return super.open();
  }
}
