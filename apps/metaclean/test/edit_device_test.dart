import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metaclean/src/device_info.dart';
import 'package:metaclean/src/edit_screen.dart';

Future<void> _open(WidgetTester tester, DeviceLookup lookup) async {
  // 화면 전체가 한 번에 그려지도록 길게 잡는다.
  await tester.binding.setSurfaceSize(const Size(400, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: EditScreen(deviceLookup: lookup)),
  ));
}

/// 날짜·위치·기기 순서로 '바꾸기'가 세 개 있다. 세 번째가 기기.
Finder get _deviceChange => find.text('바꾸기').at(2);

void main() {
  testWidgets('기기 "바꾸기"를 누르면 지금 쓰는 폰의 제조사·기종이 자동으로 들어간다',
      (tester) async {
    await _open(tester, () async => (make: 'samsung', model: 'SM-S918N'));
    expect(find.text('samsung'), findsNothing);

    await tester.tap(_deviceChange);
    await tester.pumpAndSettle();

    expect(find.text('samsung'), findsOneWidget);
    expect(find.text('SM-S918N'), findsOneWidget);
  });

  testWidgets('이미 적어 둔 값이 있으면 자동 입력이 덮어쓰지 않는다', (tester) async {
    var calls = 0;
    await _open(tester, () async {
      calls++;
      return (make: 'samsung', model: 'SM-S918N');
    });
    await tester.tap(_deviceChange);
    await tester.pumpAndSettle();
    expect(calls, 1);

    // 사용자가 다른 기기로 고쳐 쓴 뒤 '그대로'로 갔다가 다시 '바꾸기'
    await tester.enterText(find.widgetWithText(TextField, 'samsung'), 'Canon');
    await tester.tap(find.text('그대로').at(2));
    await tester.pumpAndSettle();
    await tester.tap(_deviceChange);
    await tester.pumpAndSettle();

    expect(calls, 1); // 다시 조회하지 않음
    expect(find.text('Canon'), findsOneWidget);
  });

  testWidgets('"이 폰 정보로 채우기" 버튼은 적어 둔 값을 이 폰 정보로 되돌린다',
      (tester) async {
    await _open(tester, () async => (make: 'samsung', model: 'SM-S918N'));
    await tester.tap(_deviceChange);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'samsung'), 'Canon');
    await tester.pump();
    expect(find.text('samsung'), findsNothing);

    await tester.tap(find.text('이 폰 정보로 채우기'));
    await tester.pumpAndSettle();
    expect(find.text('samsung'), findsOneWidget);
  });

  testWidgets('기종을 읽지 못하면: 자동일 땐 조용히, 버튼을 눌렀을 땐 알려 준다',
      (tester) async {
    await _open(tester, () async => null);
    await tester.tap(_deviceChange);
    await tester.pumpAndSettle();
    expect(find.textContaining('읽지 못했어요'), findsNothing);

    await tester.tap(find.text('이 폰 정보로 채우기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('읽지 못했어요'), findsOneWidget);
  });
}
