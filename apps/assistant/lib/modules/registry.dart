import 'package:assistant_core/assistant_core.dart';

import '../app/assistant_state.dart';
import 'channel_module.dart';
import 'chats_module.dart';
import 'declutter_module.dart';
import 'harddisk_module.dart';
import 'vault_module.dart';

/// 다섯 모듈 목록. 모듈은 처음 눌러야 로드된다.
class ModuleRegistry {
  ModuleRegistry(this.all);

  factory ModuleRegistry.device(AssistantState s) => ModuleRegistry([
        ChannelModule(s),
        ChatsModule(s),
        HardDiskModule(s),
        DeclutterModule(s),
        VaultModule(s),
      ]);

  final List<AssistantModule> all;

  AssistantModule of(ModuleId id) => all.firstWhere((m) => m.id == id);
}
