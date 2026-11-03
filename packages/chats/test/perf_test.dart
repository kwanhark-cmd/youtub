import 'dart:io';

import 'package:ai_chat_organizer/models/models.dart';
import 'package:ai_chat_organizer/parsers/parser_common.dart';
import 'package:ai_chat_organizer/search/query_parser.dart';
import 'package:ai_chat_organizer/search/search_service.dart';
import 'package:ai_chat_organizer/ui/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';
import 'helpers/test_env.dart';

/// 수천 개 대화에서도 느려지지 않는지 재고, 결과를 docs/검증/성능측정.md에 남깁니다.
void main() {
  final results = <String, int>{};

  test('대화 3000개: 가져오기·목록·검색 시간', () async {
    final s = memoryStore();
    final topics = ['유튜브 앱 기능', '분할 매수 원칙', '제주도 여행', '혈압 식단', '블로그 글쓰기', '엑셀 가계부'];
    final convs = [
      for (var i = 0; i < 3000; i++)
        ParsedConversation(
          source: AiSource.values[i % 3],
          externalId: 'perf-$i',
          title: '${topics[i % topics.length]} $i',
          createdAt: DateTime(2024).add(Duration(hours: i * 7)),
          updatedAt: DateTime(2024).add(Duration(hours: i * 7)),
          messages: [
            for (var m = 0; m < 6; m++)
              Message(
                role: m.isEven ? Role.user : Role.assistant,
                text: '${topics[(i + m) % topics.length]}에 대해 이야기했어요. 번호 $i-$m 내용이 조금 길게 이어집니다.',
              ),
          ],
        ),
    ];
    var sw = Stopwatch()..start();
    await s.importResults([ParseResult(source: AiSource.claude, conversations: convs)], fileName: 'perf');
    results['가져오기 3000개(ms)'] = sw.elapsedMilliseconds;
    sw = Stopwatch()..start();
    final page = s.list(limit: 40);
    results['목록 첫 쪽 40개(ms)'] = sw.elapsedMilliseconds;
    expect(page.length, 40);
    final search = SearchService(s);
    sw = Stopwatch()..start();
    final hits = await search.search(QueryParser.parse('제주도'), limit: 30);
    results['본문 검색 첫 쪽 30개(ms)'] = sw.elapsedMilliseconds;
    expect(hits.hits.length, 30);
    sw = Stopwatch()..start();
    s.months();
    results['타임라인 월 묶음(ms)'] = sw.elapsedMilliseconds;
    expect(results['목록 첫 쪽 40개(ms)']!, lessThan(300));
    expect(results['본문 검색 첫 쪽 30개(ms)']!, lessThan(3000));
  });

  testWidgets('홈 화면 첫 그리기 시간(대화가 많아도 빠르게)', (tester) async {
    await setScreen(tester, const Size(390, 844));
    final c = (await tester.runAsync(() => readyController()))!;
    final sw = Stopwatch()..start();
    await tester.pumpWidget(appWith(c, home: const HomeScreen()));
    await tester.pump();
    results['홈 첫 그리기(ms, 시험 환경)'] = sw.elapsedMilliseconds;
    await tester.pumpWidget(const SizedBox());
  });

  tearDownAll(() {
    final f = File('../docs/검증/성능측정.md');
    if (!f.parent.existsSync()) return;
    final b = StringBuffer('# 성능 측정(자동 테스트가 기록)\n\n측정 환경: 개발용 리눅스 서버, 시험용 화면(실제 기기보다 느릴 수 있음)\n\n| 항목 | 시간 |\n|---|---|\n');
    results.forEach((k, v) => b.writeln('| $k | $v |'));
    b.writeln('\n기준: 목록 첫 쪽 300ms 미만, 검색 첫 쪽 3초 미만(테스트가 확인).');
    f.writeAsStringSync(b.toString());
  });
}
