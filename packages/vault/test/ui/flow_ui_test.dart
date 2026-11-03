import 'package:account_vault/logic/breach.dart';
import 'package:account_vault/core/crypto/vault_crypto.dart';
import 'package:account_vault/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fakes.dart';

/// 실제 화면을 눌러 가며: 첫 실행 마법사 → 홈 → 구독 추가 → 잠금 → 잠금 화면.
Future<void> realWait(WidgetTester tester, [int ms = 1500]) async {
  // 실제 파일·계산 작업과 화면 시계를 번갈아 진행시킨다.
  final rounds = (ms / 100).ceil().clamp(3, 40);
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text).last;
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('화면 흐름: 마법사 → 복구 코드 확인 → 홈 → 구독 추가 → 잠그기', (tester) async {
    tester.view.physicalSize = const Size(
      420,
      4000,
    ); // 흐름 검사용(배치는 design_test 에서 검사)
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late TestRig rig;
    await tester.runAsync(() async {
      rig = await TestRig.create();
      await rig.controller.updateSettings((s) => s.autoLockSeconds = 0);
    });
    addTearDown(rig.dispose);
    rig.biometric.available = false;

    await tester.pumpWidget(VaultApp(controller: rig.controller));
    await realWait(tester, 200);

    // 1단계: 글씨 크기
    expect(find.text('반가워요!'), findsOneWidget);
    await tapText(tester, '다음');

    // 2단계: 마스터 비밀번호(약한 비밀번호는 거절)
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '1234');
    await tester.enterText(fields.at(2), '1234');
    await tapText(tester, '금고 만들기');
    expect(find.text('마스터 비밀번호는 8글자 이상으로 정해 주세요.'), findsOneWidget);
    await tester.enterText(fields.at(1), 'fake-Master-Phrase-91');
    await tester.enterText(fields.at(2), 'fake-Master-Phrase-91');
    await tapText(tester, '금고 만들기');
    await realWait(tester, 4000);

    // 3단계: 복구 코드 — 체크 전에는 다음으로 못 감
    expect(find.text('복구 코드 보관하기'), findsOneWidget);
    await tapText(tester, '다음');
    expect(find.text('복구 코드 보관하기'), findsOneWidget);
    await tapText(tester, '복구 코드를 적어 두었습니다');
    await tapText(tester, '다음');

    // 4단계: 생체 인증(이 기기 불가) → 5단계 → 시작
    expect(find.text('지문·얼굴로 열기'), findsOneWidget);
    await tapText(tester, '다음');
    await tapText(tester, '시작하기');
    await realWait(tester, 300);

    // 홈
    expect(find.text('오늘 할 일'), findsOneWidget);
    expect(rig.controller.isUnlocked, isTrue);

    // 구독 추가
    await tapText(tester, '구독 결제');
    await realWait(tester, 1200);
    await tapText(tester, '구독 추가');
    await realWait(tester, 1200);
    await tester.enterText(find.byType(TextField).at(0), '넷플릭스');
    await tester.enterText(find.byType(TextField).at(1), '17000');
    await tester.enterText(find.byType(TextField).at(2), '1234');
    await tapText(tester, '저장');
    await realWait(tester, 3000);
    expect(rig.controller.data.subscriptions.single.serviceName, 'Netflix');
    expect(rig.controller.data.subscriptions.single.cardLast4, '1234');
    expect(find.text('Netflix'), findsWidgets);

    // 홈으로 → 잠그기 → 잠금 화면, 데이터 안 보임
    await tester.tap(find.byIcon(Icons.home_rounded).last);
    await realWait(tester, 1200);
    await tapText(tester, '잠그기');
    await realWait(tester, 300);
    expect(find.text('금고가 잠겨 있어요'), findsOneWidget);
    expect(find.text('Netflix'), findsNothing);
    expect(rig.controller.isUnlocked, isFalse);

    // 틀린 비밀번호 → 안내, 맞는 비밀번호 → 홈
    await tester.enterText(find.byType(TextField).first, 'wrong-pass');
    await tapText(tester, '열기');
    await realWait(tester, 3000);
    expect(find.textContaining('맞지 않아요'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).first,
      'fake-Master-Phrase-91',
    );
    await tapText(tester, '열기');
    await realWait(tester, 3000);
    expect(rig.controller.isUnlocked, isTrue);
    expect(tester.takeException(), isNull);
  });

  test('유출 확인: 비밀번호 대신 해시 앞 5글자만 보냄', () async {
    final hash = await VaultCrypto().sha1HexUpper('fake-breach-pw');
    late Uri asked;
    final client = MockClient((req) async {
      asked = req.url;
      return http.Response(
        '${hash.substring(5)}:42\nABCDEF0123456789ABCDEF0123456789ABC:1',
        200,
      );
    });
    final n = await BreachChecker(client: client).pwnedCount('fake-breach-pw');
    expect(n, 42);
    expect(asked.path, '/range/${hash.substring(0, 5)}');
    expect(asked.toString().contains('fake-breach-pw'), isFalse);
    expect(asked.toString().contains(hash.substring(5)), isFalse);
  });
}
