import 'dart:ui';

import 'package:ai_chat_organizer/services/settings.dart' as chats_s;
import 'package:assistant_core/assistant_core.dart';
import 'package:binugi/theme/app_theme.dart' as d;
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/modules/look_sync.dart';

void main() {
  test('글씨 크기 3단계가 세 모듈의 3단계와 짝이 맞음', () {
    expect(TextSize.values.map(chatsFont), chats_s.FontSize.values);
    expect(TextSize.values.map(declutterSize), d.TextSizeChoice.values);
    expect(TextSize.values.map(vaultTextLevel), [0, 1, 2]);
  });

  test('테마: 기기 따라·밝게·어둡게·고대비', () {
    expect(chatsTheme('system'), chats_s.ThemeChoice.system);
    expect(chatsTheme('dark'), chats_s.ThemeChoice.dark);
    expect(declutterTheme('system', false, Brightness.dark), d.ThemeModeChoice.dark);
    expect(declutterTheme('system', false, Brightness.light), d.ThemeModeChoice.light);
    expect(declutterTheme('light', true, Brightness.light), d.ThemeModeChoice.highContrast);
    expect(vaultTheme('system', false), 'system');
    expect(vaultTheme('dark', true), 'contrast');
  });
}
