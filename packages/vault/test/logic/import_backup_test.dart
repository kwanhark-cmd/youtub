import 'dart:convert';
import 'dart:io';

import 'package:account_vault/core/crypto/vault_crypto.dart';
import 'package:account_vault/core/log/app_logger.dart';
import 'package:account_vault/core/vault/vault.dart';
import 'package:account_vault/data/models.dart';
import 'package:account_vault/data/repository.dart';
import 'package:account_vault/logic/csv_import.dart';
import 'package:account_vault/logic/gmail.dart';
import 'package:account_vault/logic/mail_analysis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final now = DateTime(2026, 11, 3);

void main() {
  group('CSV 가져오기', () {
    const csv =
        'name,url,username,password,note\n'
        'facebook.com,https://www.facebook.com/,fake@example.com,FakePw-0001,\n'
        ',https://x.com/login,fake_x,FakePw-0002,메모\n'
        'facebook.com,https://www.facebook.com/,fake@example.com,FakePw-0001,\n'
        'empty,,,,\n'
        'bank,https://bank.example,0012,0034,\n';

    test('구글 비밀번호 관리자 형식', () {
      final r = importPasswordCsv(csv, [], now);
      expect(r.accounts.length, 3);
      expect(r.skippedDuplicates, 1);
      expect(r.skippedInvalid, 1);
      expect(r.accounts.first.serviceName, 'Facebook');
      expect(r.accounts.first.category, 'SNS');
      expect(r.accounts.first.signupEmail, 'fake@example.com');
      expect(r.accounts[1].serviceName, 'X');
      expect(r.accounts[2].password, '0034'); // 앞자리 0 유지
    });

    test('이미 있는 계정은 건너뜀', () {
      final first = importPasswordCsv(csv, [], now).accounts;
      final r = importPasswordCsv(csv, first, now);
      expect(r.accounts, isEmpty);
    });

    test('형식이 다르면 쉬운 안내', () {
      expect(
        () => importPasswordCsv('a,b\n1,2', [], now),
        throwsA(isA<CsvFormatException>()),
      );
    });
  });

  group('결제 메일 분석', () {
    test('카드 번호 가리기', () {
      expect(maskSensitive('카드 1234 5678 9012 3456 결제'), '카드 ****3456 결제');
    });

    test('한국어 영수증', () {
      final s = analyzeWithRules(
        '[넷플릭스] 결제 완료',
        'info@netflix.com',
        '결제 금액: 17,000원\n결제 카드: 신한 ****4321\n다음 결제일 2026년 12월 6일',
        now,
      )!;
      expect(s.serviceName, 'Netflix');
      expect(s.amount, 17000);
      expect(s.cardLast4, '4321');
      expect(s.date, DateTime(2026, 12, 6));
    });

    test('영어 영수증(달러)', () {
      final s = analyzeWithRules(
        'Your receipt from Anthropic',
        'Claude <billing@anthropic.com>',
        'Claude Pro\nTotal \$20.00\nVisa ending in 9876\nNext billing date Dec 5, 2026',
        now,
      )!;
      expect(s.serviceName, 'Claude');
      expect(s.amount, 2000);
      expect(s.currency, Currency.usd);
      expect(s.cardLast4, '9876');
      expect(s.date, DateTime(2026, 12, 5));
    });

    test('크레딧 만료 안내', () {
      final s = analyzeWithRules(
        'Higgsfield credits',
        'team@higgsfield.ai',
        'Your 300 credits will expire on Nov 20, 2026',
        now,
      )!;
      expect(s.isCredit, isTrue);
      expect(s.creditText, '300 크레딧');
      expect(s.date, DateTime(2026, 11, 20));
    });

    test('모르는 메일은 null(수동 입력 안내)', () {
      expect(analyzeWithRules('안녕하세요', 'a@b.c', '점심 드셨어요?', now), isNull);
    });

    test('필요한 부분만 잘라 내고 카드번호 가림', () {
      final t = extractRelevant(
        '제목\n보낸이\n인사\n> 인용\n잡담\n합계 1,000원\n카드 4111111111111111',
      );
      expect(t.contains('잡담'), isFalse);
      expect(t.contains('4111111111111111'), isFalse);
      expect(t, contains('합계 1,000원'));
    });

    test('Claude API 응답 해석(가짜 서버)', () async {
      late Map<String, dynamic> sent;
      final client = MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.headers['anthropic-version'], '2026-10-21');
        return http.Response(
          jsonEncode({
            'stop_reason': 'end_turn',
            'usage': {'input_tokens': 1000, 'output_tokens': 200},
            'content': [
              {
                'type': 'text',
                'text': jsonEncode({
                  'found': true,
                  'kind': 'subscription',
                  'service_name': '피그마',
                  'amount': 15,
                  'currency': 'USD',
                  'cycle': 'monthly',
                  'date': '2026-12-01',
                  'card_last4': '5555',
                  'credit_text': '',
                }),
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final a = ClaudeMailAnalyzer(
        apiKey: 'fake-key',
        model: 'claude-haiku-5-5',
        client: client,
      );
      final (s, cost) = await a.analyze('Figma 영수증', now);
      expect(sent['model'], 'claude-haiku-5-5');
      expect(sent.containsKey('temperature'), isFalse);
      expect(s!.serviceName, 'Figma');
      expect(s.amount, 1500);
      expect(cost, greaterThan(0));
      expect(a.estimateCostWon('x' * 1000), lessThan(10));
    });

    test('Claude API 키 오류는 쉬운 안내', () async {
      final a = ClaudeMailAnalyzer(
        apiKey: 'bad',
        model: 'claude-opus-5-5',
        client: MockClient((_) async => http.Response('{}', 401)),
      );
      expect(() => a.analyze('x', now), throwsA(isA<AiRequestFailed>()));
    });

    test('지메일 메시지 해석(HTML)', () {
      final html = base64Url.encode(
        utf8.encode('<p>합계 <b>17,000원</b></p><style>x{}</style>'),
      );
      final m = GmailClient.parseMessage({
        'id': '1',
        'payload': {
          'headers': [
            {'name': 'Subject', 'value': '영수증'},
            {'name': 'From', 'value': 'a@b.c'},
          ],
          'mimeType': 'multipart/alternative',
          'parts': [
            {
              'mimeType': 'text/html',
              'body': {'data': html},
            },
          ],
        },
      });
      expect(m.subject, '영수증');
      expect(m.body, contains('17,000원'));
      expect(m.body.contains('<b>'), isFalse);
    });
  });

  group('백업', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('backup_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('내보내기 → 검사 → 비밀번호 확인 → 복원(현재 데이터 자동 백업)', () async {
      final repo = ProfileRepository(
        Directory('${tmp.path}/root'),
        kdf: KdfParams.fastForTests,
      );
      final (session, _, info) = await repo.createProfile(
        '가짜 사용자',
        'fake-master-111',
      );
      final d = VaultData(
        accounts: [Account(serviceName: 'A', password: 'Fake-PW-For-Backup')],
      );
      await session.save(d.toJson());
      final svc = BackupService(repo);
      final file = await svc.export(info.id, info.name, '1.0.0');
      expect(file.contains('Fake-PW-For-Backup'), isFalse); // 백업도 암호화
      expect(file.contains('fake-master-111'), isFalse);
      final bi = await svc.inspect(file);
      expect(await svc.verifyPassword(bi, 'wrong', tmp), isFalse);
      expect(await svc.verifyPassword(bi, 'fake-master-111', tmp), isTrue);
      // 현재 데이터를 바꾼 뒤 복원
      await session.save(VaultData().toJson());
      final auto = await svc.restore(bi, '1.0.0');
      expect(auto, isNotNull);
      expect(File(auto!).existsSync(), isTrue);
      final r = await repo
          .storeFor(info.id)
          .unlockWithPassword('fake-master-111');
      final restored = VaultData.fromJson((r as UnlockSuccess).session.data);
      expect(restored.accounts.single.password, 'Fake-PW-For-Backup');
    });

    test('손상·다른 형식·새 버전 백업은 복원 전에 거부', () async {
      final repo = ProfileRepository(
        Directory('${tmp.path}/root'),
        kdf: KdfParams.fastForTests,
      );
      final (_, _, info) = await repo.createProfile('u', 'fake-master-222');
      final svc = BackupService(repo);
      final file = await svc.export(info.id, info.name, '1.0.0');
      final j = jsonDecode(file) as Map<String, dynamic>;
      expect(() => svc.inspect('not json'), throwsA(isA<BackupException>()));
      expect(
        () => svc.inspect('{"format":"other"}'),
        throwsA(isA<BackupException>()),
      );
      final tampered = Map<String, dynamic>.from(j);
      (tampered['payload'] as Map)['data'] = {'x': 1};
      expect(
        () => svc.inspect(jsonEncode(tampered)),
        throwsA(isA<BackupException>()),
      );
      final future = Map<String, dynamic>.from(jsonDecode(file) as Map)
        ..['backupVersion'] = 99;
      await expectLater(
        svc.inspect(jsonEncode(future)),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'm',
            contains('업데이트'),
          ),
        ),
      );
    });

    test('사용자별 금고 분리: 다른 사용자 비밀번호로는 열리지 않음', () async {
      final repo = ProfileRepository(
        Directory('${tmp.path}/root'),
        kdf: KdfParams.fastForTests,
      );
      final (_, _, a) = await repo.createProfile('가', 'fake-master-aaa');
      final (_, _, b) = await repo.createProfile('나', 'fake-master-bbb');
      expect((await repo.list()).length, 2);
      expect(
        await repo.storeFor(a.id).unlockWithPassword('fake-master-bbb'),
        isA<UnlockWrongSecret>(),
      );
      expect(
        await repo.storeFor(b.id).unlockWithPassword('fake-master-bbb'),
        isA<UnlockSuccess>(),
      );
    });
  });

  group('로그', () {
    test('비밀처럼 보이는 값은 가림', () {
      final s = redact(
        'user fake@example.com key sk-ant-abc123 card 4111 1111 1111 1111 password=hunter2 비밀번호: 가짜값',
      );
      expect(s.contains('fake@example.com'), isFalse);
      expect(s.contains('sk-ant-abc123'), isFalse);
      expect(s.contains('4111 1111'), isFalse);
      expect(s.contains('hunter2'), isFalse);
      expect(s.contains('가짜값'), isFalse);
    });

    test('오류 기록에도 가림 적용', () {
      log.error('test', Exception('token: ya29.FAKE_TOKEN'));
      expect(log.lines.last.contains('FAKE_TOKEN'), isFalse);
    });
  });
}
