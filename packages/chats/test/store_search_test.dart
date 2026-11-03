import 'dart:io';
import 'dart:typed_data';

import 'package:ai_chat_organizer/core/cancel_token.dart';
import 'package:ai_chat_organizer/data/app_database.dart';
import 'package:ai_chat_organizer/data/content_cipher.dart';
import 'package:ai_chat_organizer/data/korean_tokenizer.dart';
import 'package:ai_chat_organizer/models/models.dart';
import 'package:ai_chat_organizer/parsers/import_reader.dart';
import 'package:ai_chat_organizer/parsers/parser_common.dart';
import 'package:ai_chat_organizer/search/query_parser.dart';
import 'package:ai_chat_organizer/search/search_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_env.dart';

void main() {
  test('본문은 암호화되어 저장된다(DB에 원문이 없음)', () async {
    final s = await storeWithSamples();
    final rows = s.db.select('SELECT body FROM conversations');
    for (final r in rows) {
      final bytes = r['body'] as Uint8List;
      expect(String.fromCharCodes(bytes).contains('안드로이드'), isFalse);
    }
    final c = s.list().firstWhere((c) => c.title == '유튜브 앱 기획 회의');
    final msgs = await s.messages(c.id);
    expect(msgs[2].text, contains('안드로이드'));
  });

  test('같은 파일을 다시 넣어도 중복되지 않고, 늘어난 대화만 갱신된다', () async {
    final s = await storeWithSamples();
    final total = s.count();
    expect(total, 10);
    final again = await s.importResults(ImportReader.read('claude_sample.json', sampleBytes('claude_sample.json')), fileName: 'again');
    expect(again.added, 0);
    expect(again.unchanged, 4);
    expect(s.count(), total);
    final grown = ParsedConversation(
      source: AiSource.claude,
      externalId: 'c1a2b3c4-0003-4000-8000-000000000003',
      title: '제주도 3박 4일 여행 일정',
      createdAt: DateTime(2026, 9, 5),
      updatedAt: DateTime(2026, 9, 6),
      messages: const [
        Message(role: Role.user, text: '하나'),
        Message(role: Role.assistant, text: '둘'),
        Message(role: Role.user, text: '셋 추가 질문 한라봉'),
      ],
    );
    final r = await s.importResults([
      ParseResult(source: AiSource.claude, conversations: [grown]),
    ], fileName: 'grow');
    expect(r.updated, 1);
    final hits = await SearchService(s).search(QueryParser.parse('한라봉'));
    expect(hits.hits.length, 1);
  });

  test('가져오기 취소', () async {
    final s = memoryStore();
    final many = List.generate(
      200,
      (i) => ParsedConversation(
        source: AiSource.claude,
        externalId: 'id$i',
        title: '대화 $i',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        messages: [Message(role: Role.user, text: '내용 $i')],
      ),
    );
    final token = CancelToken();
    final r = await s.importResults(
      [ParseResult(source: AiSource.claude, conversations: many)],
      fileName: 'x',
      cancel: token,
      onProgress: (d, t) {
        if (d >= 50) token.cancel();
      },
    );
    expect(r.cancelled, isTrue);
    expect(s.count(), 50);
  });

  group('검색', () {
    late SearchService search;
    setUpAll(() async => search = SearchService(await storeWithSamples()));

    test('세 AI 대화 본문을 한꺼번에 찾는다', () async {
      final p = await search.search(QueryParser.parse('유튜브'));
      final sources = p.hits.map((h) => h.conversation.source).toSet();
      expect(sources, containsAll([AiSource.claude, AiSource.chatgpt, AiSource.gemini]));
      expect(p.hits.first.snippet, contains('유튜브'));
    });
    test('붙여 쓴 한글 안의 낱말도 찾는다(본문)', () async {
      final p = await search.search(QueryParser.parse('일출봉'));
      expect(p.hits.single.conversation.title, contains('제주도'));
    });
    test('한 글자 검색', () async {
      final p = await search.search(QueryParser.parse('앱'));
      expect(p.hits.length, greaterThanOrEqualTo(3));
    });
    test('정확히 일치 켜기', () async {
      final loose = await search.search(QueryParser.parse('원칙 수익'));
      final exact = await search.search(QueryParser.parse('원칙이 수익을', exact: true));
      expect(exact.hits.length, 1);
      expect(loose.hits.length, greaterThanOrEqualTo(exact.hits.length));
      expect(exact.hits.single.snippet, contains('원칙이 수익을'));
    });
    test('비슷한 말도 찾기(어플 → 앱)', () async {
      final off = await search.search(QueryParser.parse('어플'));
      final on = await search.search(QueryParser.parse('어플', similar: true));
      expect(off.hits, isEmpty);
      expect(on.hits, isNotEmpty);
    });
    test('음성 문장: 지난달에 유튜브 앱 얘기한 대화 찾아줘', () async {
      final q = QueryParser.parse('지난달에 유튜브 앱 얘기한 대화 찾아줘', now: DateTime(2026, 11, 3));
      expect(q.keywords, ['유튜브', '앱']);
      expect(q.dateLabel, '지난달');
      final p = await search.search(q);
      expect(p.hits, isNotEmpty);
      for (final h in p.hits) {
        expect(h.conversation.createdAt.month, 10);
      }
    });
    test('AI 이름으로 거르기', () async {
      final q = QueryParser.parse('제미나이에서 유튜브');
      expect(q.source, AiSource.gemini);
      final p = await search.search(q);
      expect(p.hits.every((h) => h.conversation.source == AiSource.gemini), isTrue);
    });
    test('영어 낱말 앞부분 검색', () async {
      final s = memoryStore();
      await s.importResults([
        ParseResult(
          source: AiSource.claude,
          conversations: [
            ParsedConversation(
              source: AiSource.claude,
              externalId: 'e',
              title: 'Flutter 질문',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
              messages: const [Message(role: Role.user, text: 'flutter_secure_storage 설치 오류')],
            ),
          ],
        ),
      ], fileName: 'e');
      final p = await SearchService(s).search(QueryParser.parse('flut'));
      expect(p.hits.length, 1);
      final p2 = await SearchService(s).search(QueryParser.parse('설치 오류'));
      expect(p2.hits.length, 1);
    });
    test('관련된 지난 대화 추천', () async {
      final store = search.store;
      final c = store.list().firstWhere((c) => c.title == '유튜브 앱 기획 회의');
      final rel = await search.related(c.id);
      expect(rel.any((r) => r.title.contains('유튜브')), isTrue);
      expect(rel.any((r) => r.id == c.id), isFalse);
    });
  });

  group('자연어 날짜', () {
    final now = DateTime(2026, 11, 3, 15);
    test('여러 표현', () {
      expect(QueryParser.parse('어제 대화', now: now).from, DateTime(2026, 11, 2));
      expect(QueryParser.parse('올해 여행', now: now).from, DateTime(2026));
      final m = QueryParser.parse('12월에 얘기한 투자', now: now);
      expect(m.from, DateTime(2025, 12));
      expect(m.keywords, ['투자']);
      expect(QueryParser.parse('최근 7일', now: now).from, DateTime(2026, 10, 28));
      expect(QueryParser.parse('지난주 식단', now: now).from, DateTime(2026, 10, 26));
    });
  });

  test('한글 색인', () {
    expect(KoreanTokenizer.bigramIndex('유튜브앱').trim(), '유튜 튜브 브앱 |');
    expect(KoreanTokenizer.termQuery('앱'), 'u : "앱"');
    expect(KoreanTokenizer.termQuery('유튜브'), '{t b} : "유튜 튜브"');
  });

  test('데이터 버전 변환: 이전 버전 DB를 열면 최신으로 바뀌고 백업이 남는다', () async {
    final dir = await Directory.systemTemp.createTemp('mig');
    final path = '${dir.path}/data.db';
    final d = AppDatabase.openFile(path);
    expect(d.version, AppDatabase.currentVersion);
    // 1.0.0(자료 버전 2) 상태로 되돌림
    d.db.execute("UPDATE meta SET value='2' WHERE key='schema_version'");
    d.db.execute('DROP INDEX idx_conv_sample');
    d.db.execute('ALTER TABLE conversations DROP COLUMN sample');
    d.close();
    final d2 = AppDatabase.openFile(path);
    expect(d2.version, AppDatabase.currentVersion);
    d2.close();
    expect(dir.listSync().any((f) => f.path.contains('.bak-v2-')), isTrue);
  });

  test('비밀번호 암호화 왕복', () async {
    final enc = await PasswordCipher.encrypt([1, 2, 3, 4], '비밀번호1234');
    expect(await PasswordCipher.decrypt(enc, '비밀번호1234'), [1, 2, 3, 4]);
    expect(() => PasswordCipher.decrypt(enc, '틀림'), throwsA(anything));
  });
}
