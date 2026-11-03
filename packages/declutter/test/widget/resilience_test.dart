import 'package:binugi/app.dart';
import 'package:binugi/data/models.dart';
import 'package:binugi/services/media_picker.dart';
import 'package:binugi/state/app_state.dart';
import 'package:binugi/ui/screens/item_list_screen.dart';
import 'package:binugi/ui/screens/register_screen.dart';
import 'package:binugi/ui/screens/review_screen.dart';
import 'package:binugi/ui/widgets/common.dart';
import 'package:binugi/ui/widgets/status_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Future<AppState> setup(WidgetTester tester, {int items = 0, FakePicker? picker}) async {
  late AppState s;
  await tester.runAsync(() async {
    final (st, _) = await makeState();
    s = st;
    s.global.onboarded = true;
    for (var i = 0; i < items; i++) {
      await s.addItem(name: '물건 $i', room: '거실');
    }
  });
  await tester.pumpWidget(BinugiApp(state: s, picker: picker ?? FakePicker(), listenShares: false));
  await tester.pump(const Duration(milliseconds: 300));
  return s;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('목록을 내려 보는 중 갱신(사진 처리·AI 완료)이 있어도 맨 위로 튀지 않음', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = await setup(tester, items: 30);
    navKey.currentState!.push(MaterialPageRoute(builder: (_) => const ItemListScreen()));
    await settle(tester);
    final list = find.byType(Scrollable).last;
    await tester.drag(list, const Offset(0, -1500));
    await settle(tester);
    final before = tester.state<ScrollableState>(list).position.pixels;
    expect(before, greaterThan(500));
    // 다른 곳에서 물건이 추가되고 목록이 다시 그려짐
    await tester.runAsync(() => s.addItem(name: '새로 인식된 물건'));
    await s.refresh();
    await settle(tester);
    final after = tester.state<ScrollableState>(find.byType(Scrollable).last).position.pixels;
    expect(after, closeTo(before, 300), reason: '위치 유지 (새 카드 1개 높이 이내)');
    expect(after, greaterThan(500));
  });

  testWidgets('실패 창 → 다시 시도: 처음 화면이 사라져도 앱이 죽지 않고 다음 창이 뜸', (tester) async {
    await setup(tester);
    late BuildContext pageContext;
    navKey.currentState!.push(
      MaterialPageRoute(
        builder: (ctx) {
          pageContext = ctx;
          return const Scaffold(body: Text('작업 화면'));
        },
      ),
    );
    await settle(tester);
    var retried = 0;
    showFailure(
      pageContext,
      stage: 'AI 인식',
      message: '첫 번째 실패',
      onRetry: () async {
        retried++;
        // 재시도 중에 원래 화면이 닫힘 → 사라진 context로 다시 실패 창
        navKey.currentState!.pop();
        await Future<void>.delayed(Duration.zero);
        await showFailure(pageContext, stage: 'AI 인식', message: '두 번째 실패');
      },
    );
    await settle(tester);
    expect(find.text('첫 번째 실패'), findsOneWidget);
    expect(find.text('문제 신고'), findsOneWidget, reason: '모든 오류 창에 문제 신고');
    await tester.tap(find.text('다시 시도'));
    await settle(tester);
    expect(retried, 1);
    expect(tester.takeException(), isNull);
    expect(find.text('두 번째 실패'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await settle(tester);
  });

  testWidgets('카메라 권한 거부 → 오류 대신 안내하고 사진 파일 고르기로 자동 대체', (tester) async {
    final picker = FakePicker(
      camera: true,
      cameraError: PickException(PickError.denied, 'camera_access_denied'),
      photos: [PickedFile('/가짜/사진.jpg', fakeJpeg(w: 320, h: 240))],
    );
    await setup(tester, picker: picker);
    navKey.currentState!.push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
    await settle(tester);
    await tester.tap(find.text('사진 찍기'));
    for (var i = 0; i < 40 && find.byType(ReviewScreen).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(picker.pickCalls, 1, reason: '파일 고르기로 넘어감');
    expect(find.byType(ReviewScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('연결 상태 표시: AI·사진 전송·지메일이 따로, 저장하면 바로 바뀜', (tester) async {
    final s = await setup(tester, items: 1);
    navKey.currentState!.push(MaterialPageRoute(builder: (_) => const Scaffold(body: StatusChips())));
    await settle(tester);
    expect(find.text('AI: 연습 모드'), findsOneWidget);
    expect(find.text('사진 AI 전송: 꺼짐'), findsOneWidget);
    expect(find.text('지메일: 연결 안 됨'), findsOneWidget);
    s.user
      ..aiProvider = 'claude'
      ..apiKey = 'sk-ant-x'
      ..sendPhotosToAi = true;
    await tester.runAsync(() => s.saveUser());
    await settle(tester);
    expect(find.text('AI: 연결됨'), findsOneWidget);
    expect(find.text('사진 AI 전송: 켜짐'), findsOneWidget);
  });

  test('연습 물건은 실제 물건이 등록되면 자동으로 숨김', () async {
    final (s, _) = await makeState();
    await s.addItem(name: '커피 머신', isPractice: true);
    expect(s.items.length, 1, reason: '실제 물건이 없을 때는 연습 물건을 보여 줌');
    await s.addItem(name: '진짜 내 의자');
    expect(s.items.map((i) => i.name), ['진짜 내 의자']);
    expect(s.stats!.total, 1);
    expect(await s.repo.deletePracticeItems(s.uid), 1);
  });

  test('분류 결과 확인 화면: 연습 이름을 고치면 실제 물건', () {
    final d = DetectedItem(name: '커피 머신', practice: true);
    d.name = '우리집 커피 머신';
    expect(d.practice && d.name == d.originalName, isFalse);
  });
}
