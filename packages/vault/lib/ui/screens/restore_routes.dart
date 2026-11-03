import 'package:flutter/material.dart';

import 'accounts_screens.dart';
import 'cleanup_screens.dart';
import 'credits_screens.dart';
import 'mail_screens.dart';
import 'settings_screens.dart';
import 'subscriptions_screens.dart';
import 'voice_screen.dart';

/// 잠긴 뒤 다시 열 때 보던 화면을 되살린다(이름 → 화면). 입력 화면은 되살리지 않는다.
Widget? screenForRestoreId(String id) {
  if (id.startsWith('sub:')) {
    return SubscriptionDetailScreen(id: id.substring(4));
  }
  if (id.startsWith('acc:')) return AccountDetailScreen(id: id.substring(4));
  return switch (id) {
    'subs' => const SubscriptionsScreen(),
    'credits' => const CreditsScreen(),
    'accounts' => const AccountsScreen(),
    'generator' => const GeneratorScreen(),
    'cleanup' => const CleanupScreen(),
    'health' => const HealthScreen(),
    'voice' => const VoiceScreen(),
    'mail' => const MailImportScreen(),
    'settings' => const SettingsScreen(),
    'backup' => const BackupScreen(),
    'ai' => const AiSettingsScreen(),
    'gmail' => const GmailSettingsScreen(),
    _ => null,
  };
}

/// 기억해 둔 화면들을 순서대로 다시 연다.
void restoreScreens(NavigatorState nav, List<String> ids) {
  for (final id in ids) {
    final w = screenForRestoreId(id);
    if (w == null) continue;
    nav.push(MaterialPageRoute<void>(builder: (_) => w));
  }
}
