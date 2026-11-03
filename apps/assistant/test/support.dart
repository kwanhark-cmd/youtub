import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/material.dart';
import 'package:personal_assistant/app/assistant_state.dart';
import 'package:personal_assistant/modules/registry.dart';

/// 시험용 모듈: 기기 기능 없이 오늘 할 일·검색·명령·제안 받기를 흉내 낸다.
class FakeModule extends AssistantModule {
  FakeModule(this.id, {this.items = const [], this.hits = const [], this.reply});
  @override
  final ModuleId id;
  final List<TodayItem> items;
  final List<SearchHit> hits;
  final String? reply;
  final received = <Suggestion>[];
  int opened = 0;

  @override
  Future<Widget> open() async {
    opened++;
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => Column(children: [
            Text('${id.title} 모듈 홈'),
            TextButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('모듈 안 두 번째 화면')))), child: const Text('더 보기')),
          ]),
        ),
      ),
    );
  }

  @override
  Future<String> statusLine() async => '${id.title} 상태';
  @override
  Future<List<TodayItem>> today() async => items;
  @override
  Future<List<SearchHit>> search(String q) async => hits.where((h) => h.title.contains(q)).toList();
  @override
  Future<ModuleReply?> handle(VoiceCommand cmd) async => reply == null ? null : ModuleReply(reply!);
  @override
  Future<bool> receive(Suggestion s) async {
    received.add(s);
    return true;
  }
}

AssistantState fakeState(Directory root, {Map<ModuleId, FakeModule>? mods}) {
  final m = mods ?? {};
  late AssistantState s;
  s = AssistantState(
    root: root,
    secrets: MemorySecrets(),
    modules: ModuleRegistry([for (final id in ModuleId.values) m[id] ?? FakeModule(id)]),
  );
  return s;
}
