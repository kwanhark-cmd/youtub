import 'dart:convert';
import 'dart:io';

import 'package:account_vault/core/clock.dart';
import 'package:account_vault/core/crypto/password_tools.dart';
import 'package:account_vault/core/crypto/recovery_code.dart';
import 'package:account_vault/core/vault/vault.dart';
import 'package:account_vault/data/models.dart';
import 'package:account_vault/logic/alerts.dart';
import 'package:account_vault/logic/voice_assistant.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const fakeMaster = 'fake-master-phrase-777';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('전체 흐름: 설정→복구코드→잠금·해제→구독→만료 알림→계정→비밀번호 생성→복사→자동 삭제→백업·복원', () async {
    final rig = await TestRig.create(clipboardSeconds: 1);
    final app = rig.controller;
    try {
      // 1. 마스터 비밀번호 설정 + 복구 코드
      final code = await app.createProfile('테스트', fakeMaster);
      expect(RecoveryCode.isWellFormed(code), isTrue);
      expect(app.isUnlocked, isTrue);

      // 2. 잠금 → 데이터 접근 불가 → 해제
      await app.lock();
      expect(app.isUnlocked, isFalse);
      expect(() => app.data, throwsStateError);
      final info = app.profileList.single;
      expect(
        await app.unlockWithPassword(info, 'wrong-guess'),
        isA<UnlockWrongSecret>(),
      );
      expect(app.isUnlocked, isFalse);
      expect(
        await app.unlockWithPassword(info, fakeMaster),
        isA<UnlockSuccess>(),
      );

      // 3. 구독 추가
      final now = app.now();
      await app.mutate(
        (d) => d.subscriptions.add(
          Subscription(
            serviceName: '넷플릭스',
            amount: 17000,
            nextRenewal: now.add(const Duration(days: 2)),
            cardLast4: '9999-8888-7777-6666',
          ),
        ),
      );
      expect(app.data.subscriptions.single.cardLast4, '6666');

      // 4. 만료 알림
      await app.mutate(
        (d) => d.credits.add(
          CreditItem(
            serviceName: '힉스필드',
            expiresAt: now.add(const Duration(days: 1)),
          ),
        ),
      );
      final alerts = computeAlerts(app.data, now);
      expect(
        alerts.any((a) => a.isCredit && a.level == AlertLevel.danger),
        isTrue,
      );
      // OS 알림 예약(시각과 무관하게: 10일 뒤 만료 → 7일 전 알림은 항상 미래)
      await app.mutate(
        (d) => d.credits.add(
          CreditItem(
            serviceName: 'Runway',
            expiresAt: now.add(const Duration(days: 10)),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(rig.notifications.scheduled, isNotEmpty);

      // 5. 계정 추가 + 비밀번호 생성
      final pw = PasswordTools.generate();
      await app.mutate(
        (d) => d.accounts.add(
          Account(
            serviceName: '페이스북',
            signupEmail: 'fake@example.com',
            password: pw,
          ),
        ),
      );

      // 6. 복사 → 시간이 지나면 클립보드 자동 삭제
      await app.copySecret(pw);
      expect(rig.clipboard.value, pw);
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      expect(rig.clipboard.value, '');

      // 음성은 비밀번호를 읽지 않음
      final r = VoiceAssistant().handle('페이스북 비밀번호 알려줘', app.data, now);
      expect(r.text.contains(pw), isFalse);

      // 7. 백업 내보내기 → 데이터 변경 → 가져오기
      final backup = await app.backups.export(info.id, info.name, '1.0.0');
      expect(backup.contains(pw), isFalse);
      await app.mutate((d) => d.accounts.clear());
      final bi = await app.backups.inspect(backup);
      expect(
        await app.backups.verifyPassword(
          bi,
          fakeMaster,
          rig.services.scratchDir,
        ),
        isTrue,
      );
      await app.backups.restore(bi, '1.0.0');
      await app.lock(reason: 'restore');
      expect(
        await app.unlockWithPassword(info, fakeMaster),
        isA<UnlockSuccess>(),
      );
      expect(app.data.accounts.single.password, pw);
    } finally {
      await app.lock();
      rig.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('자동 잠금: 정한 시간 동안 아무것도 안 하면 잠김', () async {
    final rig = await TestRig.create();
    final app = rig.controller;
    try {
      await app.updateSettings((s) => s.autoLockSeconds = 1);
      await app.createProfile('a', fakeMaster);
      expect(app.isUnlocked, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(app.isUnlocked, isFalse);
    } finally {
      rig.dispose();
    }
  });

  test('백그라운드에 오래 있다 돌아오면 잠김', () async {
    final clock = FixedClock(DateTime(2026, 11, 3, 9));
    final rig = await TestRig.create(clock: clock);
    final app = rig.controller;
    try {
      await app.createProfile('a', fakeMaster);
      app.didChangeAppLifecycleState(AppLifecycleState.paused);
      clock.advance(const Duration(minutes: 3));
      app.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(app.isUnlocked, isFalse);
    } finally {
      rig.dispose();
    }
  });

  test('잠그면 복사해 둔 비밀번호도 즉시 지움', () async {
    final rig = await TestRig.create();
    final app = rig.controller;
    try {
      await app.createProfile('a', fakeMaster);
      await app.copySecret('fake-secret-copy');
      await app.lock();
      expect(rig.clipboard.value, '');
    } finally {
      rig.dispose();
    }
  });

  test('클립보드 30초 카운트다운(가짜 시계)', () async {
    final rig = await TestRig.create();
    final app = rig.controller;
    try {
      fakeAsync((fa) {
        app.copySecret('fake-value');
        fa.flushMicrotasks();
        expect(app.clipboardRemaining.value, 30);
        fa.elapse(const Duration(seconds: 29));
        expect(rig.clipboard.value, 'fake-value');
        fa.elapse(const Duration(seconds: 2));
        fa.flushMicrotasks();
        expect(rig.clipboard.value, '');
        // 다른 것을 복사한 경우
        app.copySecret('fake-value-2');
        fa.flushMicrotasks();
        rig.clipboard.value = 'user copied other text';
        fa.elapse(const Duration(seconds: 31));
        fa.flushMicrotasks();
        expect(rig.clipboard.value, 'user copied other text');
      });
    } finally {
      rig.dispose();
    }
  });

  test('생체 인증 실패 → 열리지 않고 비밀번호로 안내, 성공 → 열림', () async {
    final rig = await TestRig.create();
    final app = rig.controller;
    try {
      await app.createProfile('a', fakeMaster);
      await app.setBiometric(true);
      await app.lock();
      final info = app.profileList.single;
      expect(await app.hasBiometric(info), isTrue);
      rig.biometric.succeed = false;
      expect(await app.unlockWithBiometric(info), isA<UnlockUnavailable>());
      expect(app.isUnlocked, isFalse);
      rig.biometric.succeed = true;
      expect(await app.unlockWithBiometric(info), isA<UnlockSuccess>());
    } finally {
      rig.dispose();
    }
  });

  test('복구 코드로 열면 비밀번호 재설정 필요 상태', () async {
    final rig = await TestRig.create();
    final app = rig.controller;
    try {
      final code = await app.createProfile('a', fakeMaster);
      await app.lock();
      await app.unlockWithRecovery(app.profileList.single, code);
      expect(app.isUnlocked, isTrue);
      expect(app.mustResetPassword, isTrue);
    } finally {
      rig.dispose();
    }
  });

  test('초기화: 금고 파일과 기기 키 삭제', () async {
    final rig = await TestRig.create();
    final app = rig.controller;
    try {
      await app.createProfile('a', fakeMaster);
      await app.setBiometric(true);
      await app.deleteCurrentProfile();
      expect(app.profileList, isEmpty);
      expect((rig.services.keyStore as FakeKeyStore).map, isEmpty);
    } finally {
      rig.dispose();
    }
  });

  test('로그·설정 파일에 비밀번호·계정 정보가 남지 않음', () async {
    final rig = await TestRig.create();
    final app = rig.controller;
    try {
      await app.createProfile('a', fakeMaster);
      await app.mutate(
        (d) => d.accounts.add(
          Account(
            serviceName: 'x',
            loginId: 'fake-login-id-xyz',
            signupEmail: 'fake-mail@example.com',
            password: 'Fake-Leak-Check-PW',
          ),
        ),
      );
      await app.lock();
      await app.unlockWithPassword(app.profileList.single, 'wrong-once');
      for (final f in rig.dir.listSync(recursive: true).whereType<File>()) {
        final text = latin1.decode(f.readAsBytesSync());
        for (final secret in [
          fakeMaster,
          'Fake-Leak-Check-PW',
          'fake-login-id-xyz',
          'fake-mail@example.com',
          'wrong-once',
        ]) {
          expect(text.contains(secret), isFalse, reason: '${f.path} 에 $secret');
        }
      }
    } finally {
      rig.dispose();
    }
  });

  test('화면 캡처 방지가 켜짐(테스트 환경 ALLOW_SCREENSHOT 아니면)', () async {
    final rig = await TestRig.create();
    expect((rig.services.secureScreen as FakeSecureScreen).on, isTrue);
    rig.dispose();
  });
}
