import 'package:account_vault/data/models.dart';
import 'package:account_vault/logic/alerts.dart';
import 'package:account_vault/ui/app.dart';
import 'package:account_vault/ui/screens/subscriptions_screens.dart';
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

ScrollPosition listPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

void main() {
  testWidgets('목록 위치: 갱신·저장·설정 변경에도 유지, 잠금 후 다시 열면 같은 화면·위치', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late TestRig rig;
    await tester.runAsync(() async {
      rig = await TestRig.create();
      await rig.controller.updateSettings((s) {
        s.autoLockSeconds = 0;
        s.tipsShown = {'subs', 'home'};
      });
      await rig.controller.createProfile('a', 'fake-master-phrase-1');
      await rig.controller.mutate((d) {
        for (var i = 0; i < 40; i++) {
          d.subscriptions.add(
            Subscription(
              serviceName: '가짜 구독 $i',
              amount: 1000 + i,
              nextRenewal: rig.controller.now().add(Duration(days: 20 + i)),
            ),
          );
        }
        markSeen(d, computeAlerts(d, rig.controller.now()));
      });
    });
    addTearDown(rig.dispose);
    final app = rig.controller;
    await tester.pumpWidget(VaultApp(controller: app));
    await realWait(tester, 5);

    app.navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const SubscriptionsScreen()),
    );
    await realWait(tester, 8);
    listPosition(tester).jumpTo(1500);
    await tester.pump();

    // 저장(자료 변경)·화면 갱신·설정 변경이 일어나도 위치 유지
    await tester.runAsync(
      () => app.mutate((d) => d.subscriptions.first.memo = '바뀜'),
    );
    app.refresh();
    await tester.runAsync(
      () => app.updateSettings((s) => s.haptics = !s.haptics),
    );
    await realWait(tester, 5);
    expect(listPosition(tester).pixels, 1500);

    // 자동 잠금처럼 잠금 → 다시 열기 → 구독 화면·같은 위치로 복귀
    await tester.runAsync(() => app.lock(reason: 'auto'));
    await realWait(tester, 5);
    expect(find.text('금고가 잠겨 있어요'), findsOneWidget);
    await tester.runAsync(
      () => app.unlockWithPassword(
        app.profileList.single,
        'fake-master-phrase-1',
      ),
    );
    await realWait(tester, 15);
    expect(find.byType(SubscriptionsScreen), findsOneWidget);
    expect(listPosition(tester).pixels, 1500);
    expect(tester.takeException(), isNull);
  });
}
