import 'dart:io';

import 'package:binugi/app.dart';
import 'package:binugi/assistant_entry.dart';
import 'package:binugi/state/app_state.dart';
import 'package:binugi/ui/screens/settings_screen.dart';
import 'package:binugi/ui/widgets/update_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// 개인비서(통합 앱) 안에서는 이 모듈의 단독 앱 업데이트 카드(다른 저장소의 다른 앱)를 보여 주지 않는다.
/// 단독 앱으로 쓸 때는 그대로 보인다.
void main() {
  for (final hosted in [false, true]) {
    testWidgets(hosted ? '개인비서 입구로 열면: 설정에 업데이트 카드 없음' : '단독 앱: 설정에 업데이트 카드 그대로', (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.6;
      addTearDown(t.view.reset);
      late AppState s;
      late Directory root;
      await t.runAsync(() async {
        root = await Directory.systemTemp.createTemp('binugi_hosted_');
        s = hosted ? await openDeclutterState(rootOverride: root, inMemory: true) : (await makeState(root: root)).$1;
        s.global.onboarded = true;
        s.global.latestVersion = '99.0.0';
        await s.refresh();
      });
      addTearDown(() => root.deleteSync(recursive: true));
      expect(s.hostedByAssistant, hosted);
      await t.pumpWidget(BinugiApp(state: s, picker: FakePicker(), listenShares: false));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('새 버전 있어요'), hosted ? findsNothing : findsOneWidget, reason: '홈 위쪽 새 버전 배지');
      navKey.currentState!.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(find.byType(UpdateCard), hosted ? findsNothing : findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
    });
  }
}
