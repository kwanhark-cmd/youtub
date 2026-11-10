import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metaclean/main.dart';

void main() {
  testWidgets('탭 네 개가 모두 열리고 주요 버튼이 보인다', (tester) async {
    // 작은 스마트폰 화면에서도 넘치는 곳이 없어야 한다 (넘치면 테스트가 실패한다)
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MetaCleanApp());
    expect(find.text('메타지우개 플러스'), findsOneWidget);
    expect(find.text('사진 고르기 (여러 장 가능)'), findsOneWidget);

    await tester.tap(find.text('사진 수정'));
    await tester.pumpAndSettle();
    expect(find.text('촬영 날짜 바꾸기'), findsOneWidget);
    expect(find.text('사진 고르고 수정하기 (여러 장 가능)'), findsOneWidget);

    // 위치 "바꾸기"를 누르면 좌표 입력 칸이 나온다
    expect(find.text('촬영 기기 (스마트폰 제조사·기종)'), findsOneWidget);
    await tester.tap(find.text('바꾸기').first);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('바꾸기').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(4));

    await tester.tap(find.text('문서'));
    await tester.pumpAndSettle();
    expect(find.text('문서 고르기'), findsOneWidget);

    await tester.tap(find.text('구매 기록'));
    await tester.pumpAndSettle();
    expect(find.text('받은 사진 고르기'), findsOneWidget);
  });
}
