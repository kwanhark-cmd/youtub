import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/widgets.dart';

import '../app/assistant_state.dart';
import '../ui/hard_screen.dart';
import 'engine_client.dart';
import 'lazy.dart';

/// 3번 하드 모듈: 엔진은 그대로, 화면은 엔진의 웹 화면을 웹뷰(또는 외부 브라우저)로.
class HardDiskModule extends PackagedModule {
  HardDiskModule(this.s);
  final AssistantState s;
  static const tokenKey = 'engineToken';

  @override
  ModuleId get id => ModuleId.harddisk;
  @override
  String? get package => null;

  Future<EngineClient> client() async => EngineClient(baseUrl: s.settings.engineUrl, token: await s.secrets.read(tokenKey));

  @override
  Future<Widget> open() async => HardScreen(state: s, module: this);

  @override
  Future<String> statusLine() async => (await (await client()).health()) ? '엔진 연결됨' : 'PC 엔진에 연결해 주세요';

  @override
  Future<Map<String, bool>> checkConnections() async => {'하드 엔진': await (await client()).health()};
}
