import 'package:ai_chat_organizer/assistant_entry.dart';
import 'package:ai_chat_organizer/services/app_controller.dart';
import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/widgets.dart';

import '../app/assistant_state.dart';
import 'lazy.dart';

class ChatsModule extends PackagedModule {
  ChatsModule(this.s);
  final AssistantState s;
  late final lazy = Lazy<AppController>(() => openChatsController(userName: s.user?.name ?? '나'));

  @override
  ModuleId get id => ModuleId.chats;
  @override
  String get package => 'ai_chat_organizer';

  @override
  Future<Widget> open() async => chatsApp(await lazy.get());

  @override
  Future<String> statusLine() async => '클로드·챗GPT·제미나이 대화';
}
