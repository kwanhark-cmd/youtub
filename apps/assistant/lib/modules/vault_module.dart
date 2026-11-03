import 'package:account_vault/app/app_controller.dart';
import 'package:account_vault/assistant_entry.dart';
import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/widgets.dart';

import '../app/assistant_state.dart';
import 'lazy.dart';

class VaultModule extends PackagedModule {
  VaultModule(this.s);
  final AssistantState s;
  late final lazy = Lazy<AppController>(openVaultController);

  @override
  ModuleId get id => ModuleId.vault;
  @override
  String get package => 'account_vault';

  @override
  Future<Widget> open() async => vaultApp(await lazy.get());

  @override
  Future<String> statusLine() async {
    final c = lazy.value;
    if (c == null) return '마스터 비밀번호로 열기';
    return c.isUnlocked ? '열려 있어요' : '잠겨 있어요';
  }
}
