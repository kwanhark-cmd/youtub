import 'package:account_vault/data/migrations.dart';
import 'package:account_vault/data/models.dart';
import 'package:account_vault/logic/alerts.dart';
import 'package:account_vault/logic/cleanup.dart';
import 'package:account_vault/logic/dates.dart';
import 'package:account_vault/logic/money.dart';
import 'package:account_vault/logic/services_catalog.dart';
import 'package:account_vault/core/crypto/password_tools.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 11, 3, 10);

VaultData sample() => VaultData(
  subscriptions: [
    Subscription(
      serviceName: 'Claude',
      category: 'AI',
      amount: 2000,
      currency: Currency.usd,
      nextRenewal: DateTime(2026, 11, 5),
      cardLast4: '1234',
    ),
    Subscription(
      serviceName: 'ChatGPT',
      category: 'AI',
      amount: 29000,
      nextRenewal: DateTime(2026, 10, 20),
    ),
    Subscription(
      serviceName: '넷플릭스',
      amount: 120000,
      cycle: BillingCycle.yearly,
      nextRenewal: DateTime(2027, 2, 1),
      createdAt: DateTime(2026, 1, 1),
    ),
  ],
  credits: [
    CreditItem(
      serviceName: '힉스필드',
      amountText: '300 크레딧',
      expiresAt: DateTime(2026, 11, 9),
    ),
    CreditItem(
      serviceName: 'Runway',
      kind: CreditKind.trial,
      expiresAt: DateTime(2026, 11, 4),
    ),
    CreditItem(serviceName: '먼 미래', expiresAt: DateTime(2027, 1, 1)),
  ],
  accounts: [
    Account(
      serviceName: '페이스북',
      loginId: 'fake_user',
      signupEmail: 'fake@example.com',
      password: 'Fake-Pass-Shared-1',
      passwordChangedAt: DateTime(2025, 1, 1),
    ),
    Account(
      serviceName: 'X',
      password: 'Fake-Pass-Shared-1',
      passwordChangedAt: DateTime(2026, 10, 1),
    ),
    Account(
      serviceName: '스레드',
      password: 'abc',
      passwordChangedAt: DateTime(2026, 10, 1),
    ),
    Account(serviceName: '카카오톡'),
  ],
);

void main() {
  group('모델', () {
    test('카드 번호 전체를 넣어도 끝 4자리만 저장', () {
      final s = Subscription(
        serviceName: 'a',
        amount: 1,
        nextRenewal: now,
        cardLast4: '1234-5678-9012-3456',
      );
      expect(s.cardLast4, '3456');
      expect(s.toJson().toString().contains('1234-5678'), isFalse);
      expect(sanitizeCardLast4('12'), isNull);
    });

    test('JSON 왕복', () {
      final d = sample();
      final back = VaultData.fromJson(d.toJson());
      expect(back.subscriptions.length, 3);
      expect(back.subscriptions.first.currency, Currency.usd);
      expect(back.accounts.first.password, 'Fake-Pass-Shared-1');
      expect(back.credits[1].kind, CreditKind.trial);
    });

    test('옛 버전(1) 데이터 자동 변환', () {
      final v1 = {
        'subscriptions': [
          {
            'serviceName': '넷플릭스',
            'price': 17000,
            'nextRenewal': '2026-11-10T00:00:00.000',
          },
        ],
        'accounts': [
          {
            'serviceName': '유튜브',
            'channels': ['채널A', '채널B'],
          },
        ],
      };
      final d = loadVaultData(v1);
      expect(d.subscriptions.first.amount, 17000);
      expect(d.subscriptions.first.currency, Currency.krw);
      expect(d.accounts.first.purpose, '채널A, 채널B');
    });

    test('더 새 버전 데이터는 거부(안전하게 실패)', () {
      expect(
        () => migrateToLatest({'schemaVersion': 99}),
        throwsA(isA<FutureDataVersionException>()),
      );
    });
  });

  group('금액·날짜', () {
    test('월·연 합계(달러 환산, 연간 구독 월할)', () {
      final s = summarize(sample());
      // 20달러*1400=28000 + 29000 + 120000/12=10000
      expect(s.monthly.round(), 67000);
      expect(s.yearly.round(), 804000);
      expect(formatWon(67000), '67,000원');
    });

    test('지난 갱신일은 다음 주기로 굴림, 말일 처리', () {
      final s = Subscription(
        serviceName: 'a',
        amount: 1,
        nextRenewal: DateTime(2026, 10, 20),
      );
      expect(upcomingRenewal(s, now), DateTime(2026, 11, 20));
      expect(
        addCycle(DateTime(2026, 1, 31), BillingCycle.monthly),
        DateTime(2026, 2, 28),
      );
      expect(daysUntil(DateTime(2026, 11, 4), now), 1);
    });

    test('이번 달 타임라인', () {
      final t = renewalsInMonth(sample(), now);
      expect(t.map((e) => e.$2.serviceName).toList(), ['Claude', 'ChatGPT']);
      expect(t.first.$1, DateTime(2026, 11, 5));
    });
  });

  group('알림', () {
    test('7일 전·1일 전·갱신 전 알림, 위험 먼저', () {
      final a = computeAlerts(sample(), now);
      expect(a.first.title, contains('Runway'));
      expect(a.first.level, AlertLevel.danger);
      expect(
        a.any((x) => x.title.contains('힉스필드') && x.level == AlertLevel.warning),
        isTrue,
      );
      expect(a.any((x) => x.title.contains('Claude') && !x.isCredit), isTrue);
      expect(a.any((x) => x.title.contains('먼 미래')), isFalse);
    });

    test('밀린 알림은 한 번 보면 사라짐', () {
      final d = sample();
      final u = unseenAlerts(d, now);
      expect(u, isNotEmpty);
      markSeen(d, u);
      expect(unseenAlerts(d, now), isEmpty);
    });

    test('만료 지난 크레딧도 빨강으로', () {
      final d = VaultData(
        credits: [
          CreditItem(serviceName: 'a', expiresAt: DateTime(2026, 11, 1)),
        ],
      );
      final a = computeAlerts(d, now).single;
      expect(a.level, AlertLevel.danger);
      expect(a.detail, contains('만료되었어요'));
    });

    test('다시 알림: 그날 전에는 조용히, 그날이 되면 다시(만료 14일 지나도)', () {
      final c = CreditItem(
        serviceName: 'a',
        expiresAt: DateTime(2026, 10, 1),
        snoozeUntil: DateTime(2026, 11, 5),
      );
      final d = VaultData(credits: [c]);
      expect(computeAlerts(d, now), isEmpty); // 11/3 < 11/5
      final later = computeAlerts(d, DateTime(2026, 11, 5, 9));
      expect(later.single.level, AlertLevel.danger);
      markSeen(d, later);
      expect(unseenAlerts(d, DateTime(2026, 11, 5, 10)), isEmpty);
      expect(
        notificationTimes(
          VaultData(
            credits: [
              CreditItem(
                serviceName: 'b',
                expiresAt: DateTime(2027, 1, 1),
                snoozeUntil: DateTime(2026, 11, 10),
              ),
            ],
          ),
          now,
        ),
        contains(DateTime(2026, 11, 10, 9)),
      );
      expect(
        CreditItem.fromJson(c.toJson()).snoozeUntil,
        DateTime(2026, 11, 5),
      );
    });

    test('만료 후 14일이 지나면 더 이상 알리지 않음', () {
      final d = VaultData(
        credits: [
          CreditItem(serviceName: 'a', expiresAt: DateTime(2026, 10, 1)),
        ],
      );
      expect(computeAlerts(d, now), isEmpty);
    });

    test('알림 예약 시각은 미래의 오전 9시만', () {
      final t = notificationTimes(sample(), now);
      expect(t.every((x) => x.isAfter(now) && x.hour == 9), isTrue);
    });
  });

  group('정리 도우미', () {
    test('오래 안 쓴 구독, 중복 구독', () {
      final d = sample();
      d.subscriptions[0].lastUsedAt = DateTime(2026, 11, 1);
      d.subscriptions[1].lastUsedAt = DateTime(2026, 8, 1);
      final unused = unusedSubscriptions(d, now);
      expect(
        unused.map((u) => u.subscription.serviceName),
        containsAll(['ChatGPT', '넷플릭스']),
      );
      expect(
        unused.map((u) => u.subscription.serviceName),
        isNot(contains('Claude')),
      );
      final dup = duplicateSubscriptions(d);
      expect(dup.single.group, 'AI 대화');
    });

    test('건강 보고서: 재사용·약함·오래됨·미등록', () {
      final r = vaultHealth(sample(), now);
      final a = sample();
      expect(r.count(HealthIssue.reused), 2);
      expect(r.count(HealthIssue.weak), greaterThanOrEqualTo(1));
      expect(r.count(HealthIssue.old), 1);
      expect(r.count(HealthIssue.missing), 1);
      expect(r.score, lessThan(100));
      expect(r.issues.toString().contains(a.accounts.first.password!), isFalse);
    });

    test('서비스 별명 인식', () {
      expect(findKnownService('힉스필드')?.key, 'higgsfield');
      expect(findKnownService('챗GPT')?.key, 'chatgpt');
      expect(findKnownService('넷플릭스 프리미엄')?.key, 'netflix');
      expect(findKnownService('아무거나'), isNull);
    });
  });

  group('비밀번호 도구', () {
    test('생성기: 길이·종류·무작위', () {
      final a = PasswordTools.generate(length: 20);
      final b = PasswordTools.generate(length: 20);
      expect(a.length, 20);
      expect(a, isNot(b));
      expect(
        RegExp(r'[A-Z]').hasMatch(a) &&
            RegExp(r'[0-9]').hasMatch(a) &&
            RegExp(r'[^A-Za-z0-9]').hasMatch(a),
        isTrue,
      );
      expect(PasswordTools.strength(a).score, greaterThanOrEqualTo(3));
      final simple = PasswordTools.generate(
        length: 12,
        upper: false,
        digits: false,
        symbols: false,
      );
      expect(RegExp(r'^[a-z]+$').hasMatch(simple), isTrue);
    });

    test('강도: 흔한 비밀번호는 약함', () {
      expect(PasswordTools.strength('123456').score, 0);
      expect(PasswordTools.strength('qwerty123').isWeak, isTrue);
      expect(PasswordTools.strength('').score, 0);
    });
  });
}
