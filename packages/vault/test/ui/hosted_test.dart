import 'package:account_vault/assistant_entry.dart';
import 'package:account_vault/core/crypto/vault_crypto.dart';
import 'package:account_vault/ui/app.dart';
import 'package:account_vault/ui/screens/settings_screens.dart';
import 'package:account_vault/ui/screens/update_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// 개인비서(통합 앱) 안에서는 이 모듈의 단독 앱 업데이트 카드(다른 저장소의 다른 앱)를 보여 주지 않는다.
/// 단독 앱으로 쓸 때는 그대로 보인다.
void main() {
  test('개인비서 입구(hostedVaultController)는 hostedByAssistant 를 켠다', () async {
    final rig = await TestRig.create();
    addTearDown(rig.dispose);
    expect(rig.controller.hostedByAssistant, isFalse, reason: '단독 앱 기본값');
    expect(hostedVaultController(rig.services, kdf: KdfParams.fastForTests).hostedByAssistant, isTrue);
  });

  for (final hosted in [false, true]) {
    testWidgets(hosted ? '개인비서 안: 설정에 업데이트 카드 없음' : '단독 앱: 설정에 업데이트 카드 그대로', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      late TestRig rig;
      await tester.runAsync(() async {
        rig = await TestRig.create();
        await rig.controller.updateSettings((s) {
          s.autoLockSeconds = 0;
          s.tipsShown = {};
        });
        await rig.controller.createProfile('시험 사용자', 'fake-master-phrase-1');
      });
      addTearDown(rig.dispose);
      rig.controller.hostedByAssistant = hosted;
      await tester.pumpWidget(VaultApp(controller: rig.controller));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      tester.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('문제 신고(기록 내보내기)'), findsOneWidget);
      expect(find.byType(UpdateCard), hosted ? findsNothing : findsOneWidget);
    });
  }
}
