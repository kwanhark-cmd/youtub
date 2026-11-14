import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/ui/assistant_app.dart';

import 'support.dart';

/// 자료를 바꾸는 음성 명령: "정말 할까요?" → 네일 때만 실행, 아니요면 그대로.
class _Changer extends FakeModule {
  _Changer() : super(ModuleId.vault);
  int done = 0;
  @override
  Future<ModuleReply?> handle(VoiceCommand cmd) async => ModuleReply(
        '넷플릭스를 해지 후보에 넣을까요?',
        needsConfirm: true,
        confirmText: '넷플릭스를 해지 후보에 넣기',
        onConfirm: () async {
          done++;
          return '네, 처리했어요.';
        },
      );
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('vc'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('네 → 실행, 아니요 → 그대로', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final m = _Changer();
    final s = fakeState(tmp, mods: {ModuleId.vault: m});
    await s.login(s.auth.create('관학', '1234'));
    await t.pumpWidget(AssistantApp(state: s));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('home-mic')));
    await t.pumpAndSettle();

    Future<void> say(String x) async {
      await t.enterText(find.byKey(const Key('voice-text')), x);
      await t.testTextInput.receiveAction(TextInputAction.send);
      await t.pumpAndSettle();
    }

    await say('넷플릭스 구독 해지 후보');
    expect(find.text('정말 할까요?'), findsOneWidget);
    expect(find.text('넷플릭스를 해지 후보에 넣기'), findsOneWidget);
    await t.tap(find.byKey(const Key('voice-confirm-no')));
    await t.pumpAndSettle();
    expect(m.done, 0);
    expect(find.text('취소했어요. 아무것도 바꾸지 않았어요.'), findsOneWidget);

    await say('넷플릭스 구독 해지 후보');
    await t.tap(find.byKey(const Key('voice-confirm-yes')));
    await t.pumpAndSettle();
    expect(m.done, 1);
    expect(find.text('네, 처리했어요.'), findsOneWidget);
  });
}
