import 'dart:convert';
import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/modules/engine_client.dart';
import 'package:personal_assistant/modules/harddisk_module.dart';

import 'support.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('hd'));
  tearDown(() => tmp.deleteSync(recursive: true));

  final posted = <String>[];
  MockClient engine({bool up = true}) => MockClient((r) async {
        if (!up) throw const SocketException('꺼짐');
        final j = switch (r.url.path) {
          '/api/health' => {'ok': true},
          '/api/today' => {'type': 'memory', 'title': '2015년 오늘, 제주도', 'item': {'id': 7}},
          '/api/search' => {
              'files': {
                'items': [
                  {'id': 3, 'name': r.url.queryParameters['q'] == '영수증' ? '넷플릭스_영수증.pdf' : '2005_아이들.mp4', 'dir': 'D:/가족'},
                ],
              },
            },
          '/api/records/voice-diary' => () {
              posted.add(r.body);
              return {'ok': true, 'id': 11};
            }(),
          '/api/recognition' => {'faces': true},
          _ => {'error': '없음'},
        };
        return http.Response(jsonEncode(j), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      });

  test('엔진이 켜져 있으면: 오늘의 추억 + 채널·금고로 제안 + 검색 + 연결 상태', () async {
    final s = fakeState(tmp);
    final m = HardDiskModule(s, client: EngineClient(baseUrl: 'http://pc:47810', client: engine()));
    final today = await m.today();
    expect(today.single.text, '오늘의 추억: 2015년 오늘, 제주도');
    expect(s.links.pendingFor(ModuleId.channel).single.kind, LinkKind.hardToChannel);
    expect(s.links.pendingFor(ModuleId.vault).first.title, contains('넷플릭스_영수증.pdf'));
    // 두 번 불러도 같은 제안은 한 번만
    await m.today();
    expect(s.links.pendingFor(ModuleId.channel).length, 1);
    expect((await m.search('아이들')).single.title, '2005_아이들.mp4');
    expect(await m.checkConnections(), {'하드 엔진': true, '얼굴 모델': true});
    expect((await m.handle(const VoiceCommand('2005년 아이들 영상')))!.speak, contains('2005_아이들.mp4'));
  });

  test('연결을 끄면 제안하지 않는다', () async {
    final s = fakeState(tmp);
    s.settings.setLink(LinkKind.hardToChannel.name, false);
    s.settings.setLink(LinkKind.hardToVault.name, false);
    final m = HardDiskModule(s, client: EngineClient(baseUrl: 'http://pc:47810', client: engine()));
    await m.today();
    expect(s.links.pending, isEmpty);
  });

  test('비우기 → 하드: 기록 타임라인에 글로 남긴다', () async {
    final s = fakeState(tmp);
    final m = HardDiskModule(s, client: EngineClient(baseUrl: 'http://pc:47810', client: engine()));
    posted.clear();
    final ok = await m.receive(Suggestion(id: 'x', kind: LinkKind.declutterToHard, from: ModuleId.declutter, to: ModuleId.harddisk, title: '할머니 재봉틀', detail: '1970년대에 산 것', files: ['/data/photos/a.jpg']));
    expect(ok, isTrue);
    expect(posted.single, contains('할머니 재봉틀'));
    expect(posted.single, contains('a.jpg'));
  });

  test('엔진이 꺼져 있으면 조용히 비어 있다', () async {
    final s = fakeState(tmp);
    final m = HardDiskModule(s, client: EngineClient(baseUrl: 'http://pc:47810', client: engine(up: false)));
    expect(await m.today(), isEmpty);
    expect(await m.search('a'), isEmpty);
    expect((await m.handle(const VoiceCommand('사진')))!.speak, contains('꺼져'));
  });
}
