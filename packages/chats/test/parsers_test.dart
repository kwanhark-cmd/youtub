import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_chat_organizer/models/models.dart';
import 'package:ai_chat_organizer/parsers/gemini_parser.dart';
import 'package:ai_chat_organizer/parsers/import_reader.dart';
import 'package:ai_chat_organizer/parsers/parser_common.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_env.dart';

void main() {
  group('클로드 파서', () {
    test('샘플 4개 대화를 읽고 링크·첨부를 만든다', () {
      final r = ImportReader.read('claude_sample.json', sampleBytes('claude_sample.json')).single;
      expect(r.source, AiSource.claude);
      expect(r.conversations.length, 4);
      final first = r.conversations.firstWhere((c) => c.title == '유튜브 앱 기획 회의');
      expect(first.messages.length, 4);
      expect(first.messages.first.role, Role.user);
      expect(first.link, startsWith('https://claude.ai/chat/'));
      final script = r.conversations.firstWhere((c) => c.title.contains('세븐 스플릿'));
      expect(script.hasAttachments, isTrue);
      expect(script.messages[2].attachments, contains('참고자료.pdf'));
      // 제목이 빈 대화는 첫 질문으로 제목을 만든다
      expect(r.conversations.any((c) => c.title.startsWith('혈압에 좋은')), isTrue);
    });
    test('모르는 항목·깨진 항목은 건너뛴다', () {
      final data = jsonEncode([
        {
          'uuid': 'a',
          'name': '정상',
          'chat_messages': [
            {'sender': 'human', 'text': '안녕', 'new_field': 1},
          ],
        },
        {'uuid': 'b', 'name': '깨짐', 'chat_messages': 'oops', 'created_at': 12},
        'string-item',
        {'name': 'id 없음', 'chat_messages': []},
      ]);
      final r = ImportReader.read('conversations.json', Uint8List.fromList(utf8.encode(data))).single;
      expect(r.conversations.map((c) => c.title), containsAll(['정상', '깨짐']));
      expect(r.skipped, 2);
    });
  });

  group('챗GPT 파서', () {
    test('current_node 경로만 읽고 숨김·버려진 답변은 뺀다', () {
      final r = ImportReader.read('chatgpt_sample.json', sampleBytes('chatgpt_sample.json')).single;
      expect(r.source, AiSource.chatgpt);
      expect(r.conversations.length, 3);
      final t = r.conversations.firstWhere((c) => c.title == '유튜브 썸네일 문구 아이디어');
      expect(t.messages.length, 4);
      expect(t.messages.any((m) => m.text.contains('버려진')), isFalse);
      expect(t.link, 'https://chatgpt.com/c/6720a1b2-0001-8000-9000-00000000aa01');
      expect(t.createdAt.year, 2026);
    });
    test('나뉜 파일(conversations-000.json, -001.json)이 든 압축을 합쳐 읽는다', () {
      final all = jsonDecode(utf8.decode(sampleBytes('chatgpt_sample.json'))) as List;
      final a = Archive()
        ..addFile(ArchiveFile.bytes('conversations-000.json', utf8.encode(jsonEncode(all.sublist(0, 2)))))
        ..addFile(ArchiveFile.bytes('conversations-001.json', utf8.encode(jsonEncode(all.sublist(2)))))
        ..addFile(ArchiveFile.bytes('user.json', utf8.encode('{}')));
      final zip = Uint8List.fromList(ZipEncoder().encode(a));
      final r = ImportReader.read('export.zip', zip);
      expect(r.length, 1);
      expect(r.single.conversations.length, 3);
    });
  });

  group('제미나이 파서', () {
    test('HTML 기록을 30분 단위로 묶고 영어·한국어 날짜를 읽는다', () {
      final r = ImportReader.read('gemini_sample.html', sampleBytes('gemini_sample.html')).single;
      expect(r.source, AiSource.gemini);
      expect(r.conversations.length, 3);
      final blog = r.conversations.firstWhere((c) => c.title.contains('블로그'));
      expect(blog.messages.length, 4);
      expect(blog.messages[1].role, Role.assistant);
      expect(r.notices.single, contains('일부만'));
      final ko = r.conversations.firstWhere((c) => c.title.contains('알림 기능'));
      expect(ko.createdAt, DateTime(2026, 10, 15, 10, 5));
      expect(ko.messages[1].text, contains('새 영상 알리미'));
    });
    test('JSON 기록도 읽는다', () {
      final data = jsonEncode([
        {
          'header': 'Gemini Apps',
          'title': 'Prompted 오늘 날씨 어때?',
          'time': '2026-10-01T01:00:00Z',
          'products': ['Gemini Apps'],
          'safeHtmlItem': [
            {'html': '<p>맑아요</p>'},
          ],
          'attachedFiles': ['사진.jpg'],
        },
        {
          'header': 'Gemini Apps',
          'title': 'Prompted 우산 필요해?',
          'time': '2026-10-01T01:10:00Z',
          'products': ['Gemini Apps'],
        },
        {
          'header': 'Gemini Apps',
          'title': 'Prompted 다른 이야기',
          'time': '2026-10-02T01:10:00Z',
          'products': ['Gemini Apps'],
        },
      ]);
      final r = ImportReader.read('MyActivity.json', Uint8List.fromList(utf8.encode(data))).single;
      expect(r.conversations.length, 2);
      expect(r.conversations.first.messages.first.text, '오늘 날씨 어때?');
      expect(r.conversations.first.messages.first.attachments, ['사진.jpg']);
    });
    test('날짜 읽기', () {
      expect(GeminiParser.parseTakeoutDate('2026. 1. 2. 오후 12:30:00 KST'), DateTime(2026, 1, 2, 12, 30));
      expect(GeminiParser.parseTakeoutDate('Jan 2, 2026, 12:05:00 AM KST'), DateTime(2026, 1, 2, 0, 5));
      expect(GeminiParser.parseTakeoutDate('그냥 글자'), isNull);
    });
  });

  group('알 수 없는 파일', () {
    test('읽을 수 없는 파일은 멈추지 않고 안내용 예외를 낸다', () {
      expect(() => ImportReader.read('x.json', Uint8List.fromList(utf8.encode('{"hello": 1}'))), throwsA(isA<UnreadableFileException>()));
      expect(() => ImportReader.read('x.txt', Uint8List.fromList(utf8.encode('그냥 글'))), throwsA(isA<UnreadableFileException>()));
      expect(
        () => ImportReader.read('x.zip', Uint8List.fromList([0x50, 0x4b, 0x03, 0x04, 1, 2, 3])),
        throwsA(isA<UnreadableFileException>()),
      );
      final emptyZip = Uint8List.fromList(ZipEncoder().encode(Archive()..addFile(ArchiveFile.bytes('a.txt', [1]))));
      expect(() => ImportReader.read('e.zip', emptyZip), throwsA(isA<UnreadableFileException>()));
    });
  });

  group('한국어 계정 제미나이 테이크아웃(1.1.0)', () {
    Uint8List zipOf(Map<String, List<int>> files) {
      final a = Archive();
      files.forEach((n, b) => a.addFile(ArchiveFile.bytes(n, b)));
      return Uint8List.fromList(ZipEncoder().encode(a));
    }

    final html = File('test/fixtures/gemini_ko_내활동.html').readAsBytesSync();
    final json = File('test/fixtures/gemini_ko_내활동.json').readAsBytesSync();

    test('한국어 폴더 이름의 HTML을 읽고 한국어 날짜·제목 앞말을 처리', () {
      final r = ImportReader.read('takeout.zip', zipOf({'Takeout/내 활동/Gemini 앱/내활동.html': html})).single;
      expect(r.source, AiSource.gemini);
      expect(r.conversations.length, 2); // 30분 안 질문 2개 묶음 + 따로 1개
      final kimchi = r.conversations.firstWhere((c) => c.title.contains('김장'));
      expect(kimchi.title.startsWith('다음 내용으로'), isFalse);
      expect(kimchi.messages.length, 4);
      expect(kimchi.createdAt, DateTime(2026, 10, 28, 15, 5, 10));
    });

    test('HTML과 JSON이 함께 있으면 JSON만 읽어 겹치지 않음, 모르는 항목은 건너뜀', () {
      final r = ImportReader.read(
        'takeout.zip',
        zipOf({
          'Takeout/내 활동/Gemini 앱/내활동.html': html,
          'Takeout/내 활동/Gemini 앱/내활동.json': json,
          'Takeout/보관 파일_브라우저.html': utf8.encode('<html>안내</html>'),
        }),
      ).single;
      expect(r.conversations.length, 2);
      expect(r.skipped, 2);
    });

    test('만료된 링크 페이지·빈 파일은 알맞은 안내 종류로', () {
      expect(
        () => ImportReader.read(
          'data.zip',
          Uint8List.fromList(
            utf8.encode('<?xml version="1.0"?><Error><Code>AccessDenied</Code><Message>Request has expired</Message></Error>'),
          ),
        ),
        throwsA(isA<UnreadableFileException>().having((e) => e.kind, 'kind', UnreadableKind.expiredLink)),
      );
      expect(
        () => ImportReader.read('x.json', Uint8List(0)),
        throwsA(isA<UnreadableFileException>().having((e) => e.kind, 'kind', UnreadableKind.empty)),
      );
    });

    test('메시지 하나가 깨져도 대화는 가져옴', () {
      final data = jsonEncode([
        {
          'uuid': 'k1',
          'name': '반쯤 깨진 대화',
          'chat_messages': [
            {'sender': 'human', 'text': '정상 질문'},
            {
              'sender': 'assistant',
              'content': [
                {'type': 'text', 'text': 123},
              ],
              'attachments': 'x',
            },
            {'sender': 'assistant', 'text': '정상 답변'},
          ],
        },
      ]);
      final r = ImportReader.read('conversations.json', Uint8List.fromList(utf8.encode(data))).single;
      expect(r.conversations.single.messages.map((m) => m.text), containsAll(['정상 질문', '정상 답변']));
    });
  });
}
