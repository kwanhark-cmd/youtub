// 금고 호환 테스트용 "기준 금고"를 만드는 도구(한 번만 실행해 결과를 저장소에 고정).
// 실행: flutter test tool/make_vault_fixture_test.dart --dart-define=FIXTURE_VERSION=1.0.0
// 주의: 이미 만든 기준 금고는 절대 다시 만들지 말 것(이전 버전 형식을 보존하는 것이 목적).
import 'dart:convert';
import 'dart:io';

import 'package:account_vault/core/crypto/vault_crypto.dart';
import 'package:account_vault/data/models.dart';
import 'package:account_vault/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';

const fixturePassword = 'fixture-master-phrase-1.0.0';

VaultData fixtureData() => VaultData(
  subscriptions: [
    Subscription(
      id: 'sub-claude',
      serviceName: 'Claude',
      category: 'AI',
      amount: 2000,
      currency: Currency.usd,
      cycle: BillingCycle.monthly,
      nextRenewal: DateTime(2026, 11, 20),
      cardLast4: '1111',
      accountId: 'acc-claude',
      lastUsedAt: DateTime(2026, 11, 1),
      remindDaysBefore: 3,
      memo: '가짜 메모',
      createdAt: DateTime(2026, 1, 1),
    ),
    Subscription(
      id: 'sub-netflix',
      serviceName: 'Netflix',
      amount: 17000,
      cycle: BillingCycle.monthly,
      nextRenewal: DateTime(2026, 11, 6),
      isCancelCandidate: true,
      cancelUrl: 'https://www.netflix.com/cancelplan',
      createdAt: DateTime(2026, 2, 1),
    ),
    Subscription(
      id: 'sub-figma',
      serviceName: 'Figma',
      category: '디자인',
      amount: 144000,
      cycle: BillingCycle.yearly,
      nextRenewal: DateTime(2027, 3, 1),
      isPaused: true,
      remindDaysBefore: 7,
      createdAt: DateTime(2026, 3, 1),
    ),
  ],
  credits: [
    CreditItem(
      id: 'cr-higgs',
      serviceName: 'Higgsfield',
      kind: CreditKind.freeCredit,
      amountText: '300 크레딧',
      expiresAt: DateTime(2026, 11, 8),
      memo: '가짜',
      createdAt: DateTime(2026, 10, 1),
    ),
    CreditItem(
      id: 'cr-runway',
      serviceName: 'Runway',
      kind: CreditKind.trial,
      expiresAt: DateTime(2026, 11, 30),
      done: true,
      createdAt: DateTime(2026, 10, 2),
    ),
  ],
  accounts: [
    Account(
      id: 'acc-claude',
      serviceName: 'Claude',
      category: 'AI',
      loginId: 'fake.claude.user',
      signupEmail: 'fake.claude@example.com',
      password: 'Fixture-Fake-PW-claude-01',
      passwordChangedAt: DateTime(2026, 5, 5),
      purpose: '업무용',
      loginUrl: 'https://claude.ai/login',
      twoFactor: true,
      memo: '가짜',
      createdAt: DateTime(2026, 1, 1),
    ),
    Account(
      id: 'acc-fb',
      serviceName: 'Facebook',
      category: 'SNS',
      loginId: 'fake.fb',
      signupEmail: 'fake.fb@example.com',
      password: 'Fixture-Fake-PW-fb-02',
      purpose: '가게 홍보',
      createdAt: DateTime(2026, 1, 2),
    ),
    Account(
      id: 'acc-kakao',
      serviceName: '카카오톡',
      category: 'SNS',
      loginId: 'fake_kakao',
      createdAt: DateTime(2026, 1, 3),
    ),
  ],
  prefs: UserPrefs(
    displayName: '기준 사용자',
    aiApiKey: 'fake-ai-key-not-real',
    aiModel: 'claude-haiku-5-5',
    aiMonthlyLimitWon: 5000,
    gmailClientId: 'fake-client-id.apps.googleusercontent.com',
    gmailRefreshToken: 'fake-refresh-token',
    usdToKrw: 1450,
    breachCheckEnabled: true,
    unusedDays: 30,
  ),
  seenAlerts: {'credit:cr-higgs:7:2026-11-08T00:00:00.000'},
);

void main() {
  test('기준 금고 만들기', () async {
    const version = String.fromEnvironment(
      'FIXTURE_VERSION',
      defaultValue: '1.0.0',
    );
    final dir = Directory('test/fixtures/vault_v$version');
    if (dir.existsSync()) fail('이미 있음: ${dir.path} — 기준 금고는 다시 만들지 않습니다.');
    final root = Directory('${dir.path}/store');
    final repo = ProfileRepository(root, kdf: KdfParams.standard);
    final (session, code, info) = await repo.createProfile(
      '기준 사용자',
      fixturePassword,
    );
    await session.save(fixtureData().toJson());
    await session.save(fixtureData().toJson()); // vault.enc.prev 도 만들어지게
    final backup = await BackupService(repo)
        .export(info.id, info.name, version);
    File('${dir.path}/backup.vaultbackup').writeAsStringSync(backup);
    File('${dir.path}/settings.json').writeAsStringSync(
      jsonEncode(DeviceSettings(lastProfileId: info.id).toJson()),
    );
    File('${dir.path}/README.md').writeAsStringSync(
      '# 기준 금고 (앱 버전 $version 으로 만듦)\n\n'
      '- 가짜 자료만 들어 있음. 마스터 비밀번호: `$fixturePassword` (테스트 전용 가짜 값)\n'
      '- 복구 코드: `$code` (테스트 전용)\n'
      '- 사용자 id: `${info.id}`\n'
      '- **절대 수정·재생성 금지**: 새 앱 버전이 이 파일을 그대로 여는지 검사하는 기준입니다.\n',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
