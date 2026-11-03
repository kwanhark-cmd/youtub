@Tags(['tool'])
library;

import 'dart:io';

import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/stages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 시작·화면 전환 시간 재기 (화면 개선 전후 비교용). 결과는 PERF_OUT 파일에 한 줄씩.
/// 실행: flutter test --run-skipped --tags tool test/tool_perf_test.dart
void main() {
  testWidgets('시작·전환 시간', (t) async {
    registerStages();
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final start = <int>[], tab = <int>[], push = <int>[];
    for (var round = 0; round < 7; round++) {
      final k = TestKit();
      final s = AppState(k.env);
      await s.login(k.env.accounts.create('측정$round', '1234'));
      s.user!.settings.onboardingDone = true;
      await s.user!.youtube.connectGoogle();
      for (final c in s.user!.youtube.channels()) {
        await s.user!.youtube.syncChannel(c.channelId);
      }
      final sw = Stopwatch()..start();
      await t.pumpWidget(ChannelBiseoApp(state: s));
      await t.pumpAndSettle();
      start.add(sw.elapsedMicroseconds);
      sw.reset();
      await t.tap(find.byIcon(Icons.video_library).last);
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.dashboard).last);
      await t.pumpAndSettle();
      tab.add(sw.elapsedMicroseconds ~/ 2);
      await t.tap(find.byIcon(Icons.video_library).last);
      await t.pumpAndSettle();
      sw.reset();
      await t.tap(find.byKey(const Key('channel-UC_mock_trip')));
      await t.pumpAndSettle();
      t.state<NavigatorState>(find.byType(Navigator).first).pop();
      await t.pumpAndSettle();
      push.add(sw.elapsedMicroseconds);
      await t.pumpWidget(const SizedBox());
    }
    int median(List<int> l) => (l..sort())[l.length ~/ 2];
    final line = '시작 ${median(start) ~/ 1000}ms, 메뉴 전환 ${median(tab) ~/ 1000}ms, 상세 화면 열고 닫기 ${median(push) ~/ 1000}ms';
    // ignore: avoid_print
    print('PERF $line');
    final out = Platform.environment['PERF_OUT'];
    if (out != null) File(out).writeAsStringSync('$line\n', mode: FileMode.append);
  });
}
