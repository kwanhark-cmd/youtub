import 'package:account_vault/core/log/app_logger.dart';
import 'package:account_vault/ui/app.dart';
import 'package:account_vault/ui/screens/mail_screens.dart';
import 'package:account_vault/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Future<void> realWait(WidgetTester tester, [int rounds = 15]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<TestRig> openRig(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late TestRig rig;
  await tester.runAsync(() async {
    rig = await TestRig.create();
    await rig.controller.updateSettings((s) {
      s.autoLockSeconds = 0;
      s.tipsShown = {'home'};
    });
    await rig.controller.createProfile('a', 'fake-master-phrase-1');
    await rig.controller.mutate((d) {
      d.prefs.gmailClientId = 'fake-client';
      d.prefs.gmailRefreshToken = 'fake-refresh'; // 가짜 → 연결 실패가 나야 함
    });
  });
  addTearDown(rig.dispose);
  await tester.pumpWidget(VaultApp(controller: rig.controller));
  await realWait(tester, 5);
  return rig;
}

void main() {
  testWidgets('실패 → 다시 시도 → 또 실패 → 닫기: 앱이 멈추지 않고 실패가 기록됨', (tester) async {
    final rig = await openRig(tester);
    rig.controller.navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const MailImportScreen()),
    );
    await realWait(tester, 5);
    await tester.tap(find.text('지메일에서 최근 결제 메일 찾기'));
    await realWait(tester, 20);
    expect(find.text('지메일에 실패했어요'), findsOneWidget);
    expect(find.text('문제 신고'), findsOneWidget); // 금고가 열렸을 때만
    await tester.tap(find.text('다시 시도'));
    await realWait(tester, 20);
    expect(find.text('지메일에 실패했어요'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await realWait(tester, 5);
    expect(find.text('지메일에 실패했어요'), findsNothing);
    expect(log.lines.any((l) => l.contains('실패[지메일]')), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('이미 닫힌 화면의 context 로 실패 창을 띄워도 앱이 죽지 않음', (tester) async {
    final rig = await openRig(tester);
    late BuildContext dead;
    rig.controller.navigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (c) {
          dead = c;
          return const Scaffold(body: Text('잠깐 보이는 화면'));
        },
      ),
    );
    await realWait(tester, 5);
    rig.controller.navigatorKey.currentState!.pop();
    await realWait(tester, 20);
    expect(dead.mounted, isFalse);
    // 1번 앱에서 실제로 앱을 죽인 패턴: 사라진 context 로 showDialog
    showErrorDialog(
      dead,
      stage: FailStage.backup,
      message: '가짜 실패',
      onRetry: () async {},
    );
    await realWait(tester, 5);
    expect(find.text('백업에 실패했어요'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await realWait(tester, 5);
    dead.toast('사라진 화면의 안내도 안전');
    await realWait(tester, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('문제 신고 기록에 비밀번호·계정·카드 정보가 없음', (tester) async {
    final rig = await openRig(tester);
    log.info(
      '카드 4111 1111 1111 1111 email fake@example.com password=fake-secret',
    );
    await tester.runAsync(
      () => reportProblem(rig.controller.navigatorKey.currentContext!),
    );
    final txt = rig.files.saved['문제신고기록.txt']!;
    expect(txt.contains('4111 1111'), isFalse);
    expect(txt.contains('fake@example.com'), isFalse);
    expect(txt.contains('fake-secret'), isFalse);
    expect(txt.contains('fake-master-phrase-1'), isFalse);
  });
}
