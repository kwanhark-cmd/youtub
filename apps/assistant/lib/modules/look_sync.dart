// 개인비서의 하나의 보기 설정(글씨 크기 3단계·테마·고대비·움직임 줄이기)을 각 모듈의 자기 설정 이름으로 바꿔 넘긴다.
// 모듈을 열 때마다 넘기므로, 개인비서 설정을 바꾸면 다음에 모듈을 열 때 바로 같아진다.
// 모듈의 첫 안내(글씨 크기·화면 색 고르기)는 개인비서가 이미 정했으니 건너뛴다. 금고의 첫 마법사는
// 마스터 비밀번호를 만드는 단계라 그대로 둔다.
import 'package:account_vault/app/app_controller.dart' as vault;
import 'package:ai_chat_organizer/services/app_controller.dart' as chats;
import 'package:ai_chat_organizer/services/settings.dart' as chats_s;
import 'package:assistant_core/assistant_core.dart';
import 'package:binugi/state/app_state.dart' as declutter;
import 'package:binugi/theme/app_theme.dart' as declutter_t;
import 'dart:ui';

/// 대화 모듈 이름으로
chats_s.FontSize chatsFont(TextSize t) => switch (t) {
      TextSize.normal => chats_s.FontSize.normal,
      TextSize.large => chats_s.FontSize.large,
      TextSize.huge => chats_s.FontSize.xlarge,
    };

chats_s.ThemeChoice chatsTheme(String mode) => switch (mode) {
      'light' => chats_s.ThemeChoice.light,
      'dark' => chats_s.ThemeChoice.dark,
      _ => chats_s.ThemeChoice.system,
    };

/// 비우기 모듈 이름으로 (고대비는 테마 하나로 되어 있고, "기기 따라"가 없어 기기 밝기로 고른다)
declutter_t.TextSizeChoice declutterSize(TextSize t) => switch (t) {
      TextSize.normal => declutter_t.TextSizeChoice.normal,
      TextSize.large => declutter_t.TextSizeChoice.large,
      TextSize.huge => declutter_t.TextSizeChoice.huge,
    };

declutter_t.ThemeModeChoice declutterTheme(String mode, bool highContrast, Brightness platform) {
  if (highContrast) return declutter_t.ThemeModeChoice.highContrast;
  final dark = mode == 'dark' || (mode == 'system' && platform == Brightness.dark);
  return dark ? declutter_t.ThemeModeChoice.dark : declutter_t.ThemeModeChoice.light;
}

/// 금고 모듈 이름으로 (글씨 단계 0·1·2, 테마 light·dark·contrast·system)
int vaultTextLevel(TextSize t) => switch (t) { TextSize.normal => 0, TextSize.large => 1, TextSize.huge => 2 };

String vaultTheme(String mode, bool highContrast) => highContrast ? 'contrast' : (const {'light', 'dark'}.contains(mode) ? mode : 'system');

Brightness get _platform => PlatformDispatcher.instance.platformBrightness;

void applyLookToChats(chats.AppController c, AppSettings s) {
  c.updateSettings((x) {
    x.fontSize = chatsFont(s.textSize);
    x.theme = chatsTheme(s.themeMode);
    x.highContrast = s.highContrast;
    x.reduceMotion = s.reduceMotion;
    if (c.session != null) x.onboardingDone = true;
  });
}

Future<void> applyLookToDeclutter(declutter.AppState st, AppSettings s) async {
  st.global
    ..textSize = declutterSize(s.textSize)
    ..theme = declutterTheme(s.themeMode, s.highContrast, _platform)
    ..reduceMotion = s.reduceMotion
    ..onboarded = true;
  await st.saveGlobal();
}

Future<void> applyLookToVault(vault.AppController c, AppSettings s) => c.updateSettings((x) {
      x.textScaleLevel = vaultTextLevel(s.textSize);
      x.themeMode = vaultTheme(s.themeMode, s.highContrast);
      x.reduceMotion = s.reduceMotion;
    });
