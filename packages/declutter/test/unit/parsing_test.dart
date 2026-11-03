import 'package:binugi/core/logger.dart';
import 'package:binugi/data/models.dart';
import 'package:binugi/services/gemini_import.dart';
import 'package:binugi/services/knowledge.dart';
import 'package:binugi/services/voice_commands.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('제미나이 정리 글 가져오기', () {
    test('여러 형식의 목록을 읽음', () {
      const text = '''
## 거실
- 커피 머신: 판매 (잘 작동함)
- 낡은 의자 → 폐기
* **책상** / 지금 사용
1. 요가 매트 - 나눔
2) 오래된 잡지 묶음: 버리기
[안방]
• 겨울 패딩: 당근에 팔기
그냥 메모 한 줄
''';
      final r = parseImportText(text);
      final byName = {for (final l in r) l.name: l};
      expect(byName['커피 머신']!.decision, Decision.sell);
      expect(byName['커피 머신']!.note, contains('잘 작동함'));
      expect(byName['커피 머신']!.room, '거실');
      expect(byName['낡은 의자']!.decision, Decision.discard);
      expect(byName['책상']!.decision, Decision.use);
      expect(byName['요가 매트']!.decision, Decision.discard);
      expect(byName['오래된 잡지 묶음']!.decision, Decision.discard);
      expect(byName['겨울 패딩']!.decision, Decision.sell);
      expect(byName['겨울 패딩']!.room, '안방');
      expect(byName['그냥 메모 한 줄']!.decision, isNull, reason: '분류 없는 줄은 사용자가 확인');
    });

    test('표 형식(csv) 목록 파일', () {
      final r = parseImportText('이름,분류,방,메모\n커피 머신,판매,주방,잘 작동함\n의자,폐기,거실,\n책상,,서재,');
      expect(r.map((l) => l.name), ['커피 머신', '의자', '책상']);
      expect(r[0].decision, Decision.sell);
      expect(r[0].room, '주방');
      expect(r[0].note, '잘 작동함');
      expect(r[1].decision, Decision.discard);
      expect(r[2].decision, isNull);
    });

    test('빈 글은 빈 목록', () {
      expect(parseImportText('  \n\n'), isEmpty);
    });
  });

  group('음성 명령', () {
    test('분류 명령', () {
      expect(parseVoiceCommand('이건 판매').decision, Decision.sell);
      expect(parseVoiceCommand('이건 폐기').decision, Decision.discard);
      expect(parseVoiceCommand('버려 주세요').decision, Decision.discard);
      expect(parseVoiceCommand('지금 쓰는 거야').decision, Decision.use);
    });
    test('판매·폐기는 확인 필요, 지금 쓰는 것은 바로', () {
      expect(parseVoiceCommand('이건 판매').needsConfirm, isTrue);
      expect(parseVoiceCommand('이건 폐기').needsConfirm, isTrue);
      expect(parseVoiceCommand('지금 쓰는 것').needsConfirm, isFalse);
    });
    test('읽어주기 명령과 모르는 말', () {
      expect(parseVoiceCommand('오늘 할 일 알려줘').kind, VoiceCommandKind.readToday);
      expect(parseVoiceCommand('진행 현황').kind, VoiceCommandKind.readProgress);
      expect(parseVoiceCommand('음 글쎄').kind, VoiceCommandKind.unknown);
    });
  });

  group('분류 규칙', () {
    Item item(String name, {String cond = '', String desc = ''}) => Item(userId: 1, name: name, condition: cond, description: desc, createdAt: DateTime(2026));
    test('고장 → 폐기, 잘 작동 → 판매, 매일 씀 → 지금 쓰는 것', () {
      expect(ruleSuggest(item('커피 머신', cond: '고장')), Decision.discard);
      expect(ruleSuggest(item('커피 머신', desc: '10년 된 커피 머신, 잘 작동함')), Decision.sell);
      expect(ruleSuggest(item('밥솥', desc: '매일 씀')), Decision.use);
    });
    test('분류는 세 가지뿐', () {
      expect(Decision.values.length, 3);
      expect(Decision.values.map((d) => d.label).toSet(), {'지금 쓰는 것', '판매', '폐기'});
    });
    test('결정 도움 질문', () {
      expect(helpQuestions.length, inInclusiveRange(2, 3));
      expect(decideFromAnswers([true, true, true]), Decision.use);
      expect(decideFromAnswers([false, false, true]), Decision.sell);
      expect(decideFromAnswers([false, false, false]), Decision.discard);
    });
  });

  group('기록에서 민감 정보 지우기', () {
    test('API 키·긴 사진 데이터·이메일을 지움', () {
      final r = AppLogger.redact('key=sk-ant-api03-ABCdef_123-xyz x-api-key: secret123 ${'A' * 300} me@example.com');
      expect(r, isNot(contains('sk-ant')));
      expect(r, isNot(contains('secret123')));
      expect(r, isNot(contains('A' * 300)));
      expect(r, isNot(contains('me@example.com')));
    });
    test('로그 파일에도 키가 남지 않음', () {
      log.info('연결 키 sk-ant-api03-SECRETSECRET');
      expect(log.recent.last, isNot(contains('SECRETSECRET')));
    });
  });
}
