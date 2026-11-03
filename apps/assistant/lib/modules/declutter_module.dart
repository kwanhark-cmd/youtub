import 'package:assistant_core/assistant_core.dart';
import 'package:binugi/assistant_entry.dart';
import 'package:binugi/state/app_state.dart';
import 'package:flutter/widgets.dart';

import '../app/assistant_state.dart';
import 'lazy.dart';

class DeclutterModule extends PackagedModule {
  DeclutterModule(this.s);
  final AssistantState s;
  late final lazy = Lazy<AppState>(() => openDeclutterState());

  @override
  ModuleId get id => ModuleId.declutter;
  @override
  String get package => 'binugi';

  @override
  Future<Widget> open() async => declutterApp(await lazy.get());

  @override
  Future<String> statusLine() async => '쓰는 것·판매·폐기 나누기';
}
