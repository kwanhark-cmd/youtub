import 'package:ai_chat_organizer/ui/screens/settings_screen.dart';
import 'package:ai_chat_organizer/ui/widgets/update_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

/// 개인비서(통합 앱) 안에서는 이 모듈의 단독 앱 업데이트(다른 저장소의 다른 앱)를 보여 주지 않는다.
/// 단독 앱으로 쓸 때는 그대로 보인다.
void main() {
  for (final hosted in [false, true]) {
    testWidgets(hosted ? '개인비서 안: 업데이트 카드·새 버전 배지 없음' : '단독 앱: 업데이트 카드·새 버전 배지 그대로', (tester) async {
      await setScreen(tester, const Size(900, 1400));
      final c = (await tester.runAsync(
        () => readyController(hosted: hosted, settings: (s) => s.latestVersion = '99.0.0'),
      ))!;
      expect(c.hostedByAssistant, hosted);
      expect(c.hasUpdateBadge, !hosted);
      await tester.pumpWidget(appWith(c, home: const SettingsScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(UpdateCard), hosted ? findsNothing : findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
