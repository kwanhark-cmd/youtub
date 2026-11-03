import 'package:ai_chat_organizer/models/models.dart';
import 'package:ai_chat_organizer/parsers/parser_common.dart';
import 'package:ai_chat_organizer/ui/screens/search_screen.dart';
import 'package:ai_chat_organizer/ui/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  testWidgets('실패 창을 닫은 뒤 사라진 화면으로 "다시 시도"해도 앱이 죽지 않는다', (tester) async {
    await setScreen(tester, const Size(800, 1200));
    final c = (await tester.runAsync(() => readyController()))!;
    late BuildContext sheetContext;
    String? picked;
    await tester.pumpWidget(
      appWith(
        c,
        home: Builder(
          builder: (home) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: home,
                    builder: (sheet) {
                      sheetContext = sheet;
                      return const SizedBox(height: 200, child: Text('작은 창'));
                    },
                  ),
                  child: const Text('열기'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await settle(tester);
    // 작은 창을 닫음 → sheetContext는 사라진 화면
    Navigator.of(sheetContext).pop();
    await settle(tester);
    expect(sheetContext.mounted, isFalse);
    // 사라진 화면으로 실패 안내 → 다시 시도 → 또 대화상자
    final done = showFailure(
      sheetContext,
      title: '가져오지 못했어요',
      message: '파일을 열 수 없어요',
      stage: '파일 열기',
      onRetry: () async {
        picked = await pickOne<String>(sheetContext, title: '어느 AI 파일인가요?', options: const [('claude', '클로드')]);
      },
    );
    await settle(tester);
    expect(find.text('가져오지 못했어요'), findsOneWidget);
    expect(find.text('문제 신고'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await settle(tester);
    expect(find.text('어느 AI 파일인가요?'), findsOneWidget);
    await tester.tap(find.text('클로드'));
    await settle(tester);
    await tester.runAsync(() => done);
    expect(picked, 'claude');
    expect(tester.takeException(), isNull);
    // 안내 띠도 사라진 화면으로 띄워도 안전
    showNotice(sheetContext, '괜찮아요');
    await settle(tester);
    expect(find.text('괜찮아요'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('검색 결과를 내려 보는 중 자료가 갱신돼도 맨 위로 튀지 않는다', (tester) async {
    await setScreen(tester, const Size(500, 900));
    final c = (await tester.runAsync(() async {
      final c = await readyController();
      final many = [
        for (var i = 0; i < 70; i++)
          ParsedConversation(
            source: AiSource.chatgpt,
            externalId: 'scroll-$i',
            title: '스크롤 시험 대화 $i',
            createdAt: DateTime(2026, 9, 1).add(Duration(hours: i)),
            updatedAt: DateTime(2026, 9, 1),
            messages: [Message(role: Role.user, text: '스크롤 확인용 내용 $i')],
          ),
      ];
      await c.session!.store.importResults([ParseResult(source: AiSource.chatgpt, conversations: many)], fileName: 'many');
      return c;
    }))!;
    await tester.pumpWidget(appWith(c, home: const SearchScreen(initialQuery: '스크롤')));
    await settle(tester, rounds: 10);
    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, -2500));
    await settle(tester);
    final before = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(before, greaterThan(1000));
    // 다른 곳에서 자료가 바뀜(분류 진행·별표 등)
    final first = c.session!.store.list().first;
    c.session!.store.setStarred(first.id, true);
    c.touch();
    await settle(tester, rounds: 10);
    final after = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(after, closeTo(before, 1));
    await tester.pumpWidget(const SizedBox());
  });
}
