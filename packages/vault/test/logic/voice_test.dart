import 'package:account_vault/data/models.dart';
import 'package:account_vault/logic/voice_assistant.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 11, 3, 8);

VaultData data() => VaultData(
  subscriptions: [
    Subscription(
      serviceName: '넷플릭스',
      amount: 17000,
      nextRenewal: DateTime(2026, 11, 6),
    ),
    Subscription(
      serviceName: 'Claude',
      amount: 2000,
      currency: Currency.usd,
      nextRenewal: DateTime(2026, 11, 20),
    ),
  ],
  credits: [
    CreditItem(
      serviceName: 'Higgsfield',
      amountText: '300 크레딧',
      expiresAt: DateTime(2026, 11, 8),
    ),
  ],
  accounts: [
    Account(
      serviceName: 'Facebook',
      loginId: 'fake.id',
      signupEmail: 'fake@example.com',
      password: 'Fake-Secret-Value-77',
      passwordChangedAt: DateTime(2026, 5, 1),
    ),
  ],
);

void main() {
  final va = VoiceAssistant();

  test('이번 달 구독료', () {
    final r = va.handle('이번 달 구독료 얼마야?', data(), now);
    expect(r.intent, VoiceIntent.monthlyTotal);
    expect(r.text, contains('45,000원'));
  });

  test('한국어 별명으로 크레딧 만료일 질문', () {
    final r = va.handle('힉스필드 크레딧 언제 끝나?', data(), now);
    expect(r.text, contains('2026년 11월 8일'));
    expect(r.text, contains('5일 남음'));
  });

  test('가입 이메일 질문', () {
    final r = va.handle('페이스북 어떤 이메일로 가입했어?', data(), now);
    expect(r.text, contains('fake@example.com'));
  });

  test('비밀번호는 절대 읽지 않음', () {
    for (final q in [
      '페이스북 비밀번호 뭐야',
      '페이스북 비번 알려줘',
      'facebook password',
      '페이스북 암호 읽어줘',
    ]) {
      final r = va.handle(q, data(), now);
      expect(r.text, passwordRefusal, reason: q);
      expect(r.text.contains('Fake-Secret-Value-77'), isFalse);
    }
    final r = va.handle('페이스북 비밀번호 언제 바꿨어', data(), now);
    expect(r.text, contains('2026년 5월 1일'));
  });

  test('어떤 질문에도 비밀번호가 섞이지 않음(퍼징)', () {
    final d = data();
    d.accounts.first.loginId = 'Fake-Secret-Value-77'; // 일부러 같게
    final r = va.handle('페이스북 아이디 뭐야', d, now);
    expect(r.text.contains('Fake-Secret-Value-77'), isFalse);
  });

  test('만료일 등록 명령은 확인 후 실행', () {
    final d = data();
    final r = va.handle('힉스필드 크레딧 만료일 11월 5일로 등록해 줘', d, now);
    expect(r.action, isNotNull);
    expect(d.credits.first.expiresAt, DateTime(2026, 11, 8)); // 아직 그대로
    r.action!.apply(d);
    expect(d.credits.first.expiresAt, DateTime(2026, 11, 5));
  });

  test('없는 서비스 크레딧은 새로 등록', () {
    final d = data();
    final r = va.handle('런웨이 체험판 만료일 12월 1일로 등록해 줘', d, now);
    r.action!.apply(d);
    expect(d.credits.last.serviceName, 'Runway');
    expect(d.credits.last.kind, CreditKind.trial);
  });

  test('해지 후보 명령', () {
    final d = data();
    final r = va.handle('넷플릭스 해지 후보에 넣어', d, now);
    expect(r.action, isNotNull);
    r.action!.apply(d);
    expect(d.subscriptions.first.isCancelCandidate, isTrue);
    expect(va.handle('넷플릭스 해지 후보에 넣어', d, now).action, isNull);
  });

  test('아침 브리핑', () {
    final r = va.handle('아침 브리핑 해 줘', data(), now);
    expect(r.text, contains('만료가 다가오는 항목 1건'));
    expect(r.text, contains('넷플릭스'));
  });

  test('날짜 해석', () {
    expect(parseKoreanDate('11월 5일', now), DateTime(2026, 11, 5));
    expect(parseKoreanDate('1월 5일', now), DateTime(2027, 1, 5));
    expect(parseKoreanDate('2027년 3월 2일', now), DateTime(2027, 3, 2));
    expect(parseKoreanDate('2026-12-24', now), DateTime(2026, 12, 24));
    expect(parseKoreanDate('내일', now), DateTime(2026, 11, 4));
    expect(parseKoreanDate('2월 30일', now), isNull);
    expect(parseKoreanDate('아무 말', now), isNull);
  });

  test('모르는 말·빈 말', () {
    expect(va.handle('', data(), now).text, contains('다시'));
    expect(va.handle('날씨 어때', data(), now).intent, VoiceIntent.unknown);
  });
}
