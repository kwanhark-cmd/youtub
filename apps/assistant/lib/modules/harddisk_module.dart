import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/widgets.dart';

import '../app/assistant_state.dart';
import '../ui/hard_screen.dart';
import 'engine_client.dart';
import 'lazy.dart';

/// 3번 하드 모듈: 엔진은 그대로, 화면은 엔진의 웹 화면을 웹뷰(또는 외부 브라우저)로.
/// 엔진이 꺼져 있으면 오늘 할 일·검색은 조용히 비어 있다.
class HardDiskModule extends PackagedModule {
  HardDiskModule(this.s, {EngineClient? client}) : _fixed = client;
  final AssistantState s;
  final EngineClient? _fixed;
  static const tokenKey = 'engineToken';

  @override
  ModuleId get id => ModuleId.harddisk;
  @override
  String? get package => null;

  Future<EngineClient> client() async => _fixed ?? EngineClient(baseUrl: s.settings.engineUrl, token: await s.secrets.read(tokenKey));

  @override
  Future<Widget> open() async => HardScreen(state: s, module: this);

  @override
  Future<String> statusLine() async => (await (await client()).health()) ? '엔진 연결됨' : 'PC 엔진에 연결해 주세요';

  @override
  Future<List<TodayItem>> today() async {
    final c = await client();
    if (!await c.health()) return const [];
    final out = <TodayItem>[];
    try {
      final t = await c.today();
      final title = '${t['title'] ?? ''}';
      switch (t['type']) {
        case 'memory':
          out.add(TodayItem(module: id, text: '오늘의 추억: $title', urgency: 45));
          final item = t['item'];
          final fid = item is Map ? item['id'] as int? : null;
          s.links.propose(Suggestion(
            id: 'hard-memory-${DateTime.now().toIso8601String().substring(0, 10)}-${fid ?? title.hashCode}',
            kind: LinkKind.hardToChannel,
            from: id,
            to: ModuleId.channel,
            title: 'N년 전 오늘: $title',
            detail: '하드에서 찾은 오늘의 추억이에요. 채널 "내 코너" 소재로 써 보세요.',
            files: [if (fid != null) c.rawUrl(fid).toString()],
          ));
        case 'resume':
        case 'start':
          out.add(TodayItem(module: id, text: title, urgency: 30));
      }
    } catch (e) {
      CoreLog.warn('하드 오늘 할 일 실패: $e');
    }
    await proposeReceipts(c);
    return out;
  }

  /// 하드 → 금고: 영수증·계약서 문서를 "구독 근거 문서"로 제안 (하루 한 번 정도, 몇 개만)
  Future<int> proposeReceipts(EngineClient c) async {
    var n = 0;
    for (final q in const ['영수증', '계약서']) {
      try {
        for (final h in (await c.search(q, size: 5)).where((h) => h.kind != 'scenes')) {
          if (s.links.propose(Suggestion(
            id: 'hard-doc-${h.id ?? '${h.dir}/${h.name}'.hashCode}',
            kind: LinkKind.hardToVault,
            from: id,
            to: ModuleId.vault,
            title: '구독 근거 문서 후보: ${h.name}',
            detail: h.dir,
            files: [if (h.id != null) c.rawUrl(h.id!).toString()],
          ))) {
            n++;
          }
        }
      } catch (_) {}
    }
    return n;
  }

  @override
  Future<List<SearchHit>> search(String query) async {
    final c = await client();
    if (!await c.health()) return const [];
    return [
      for (final h in await c.search(query))
        SearchHit(module: id, title: h.name, subtitle: h.dir, kind: h.kind),
    ];
  }

  @override
  Future<ModuleReply?> handle(VoiceCommand cmd) async {
    final c = await client();
    if (!await c.health()) return const ModuleReply('PC의 하드 자료 찾기 엔진이 꺼져 있어요. PC에서 켜 주세요.');
    final hits = await c.search(cmd.text);
    if (hits.isEmpty) return ModuleReply('"${cmd.text}"을(를) 하드에서 찾지 못했어요.');
    return ModuleReply('하드에서 ${hits.length}개를 찾았어요. 첫 번째는 ${hits.first.name}이에요.', openModule: true);
  }

  /// 비우기 → 하드: "디지털로 남기고 버리기" 기록을 개인 기록 타임라인에 넣는다.
  @override
  Future<bool> receive(Suggestion sg) async {
    if (sg.kind != LinkKind.declutterToHard) return false;
    final c = await client();
    final text = '[물건 비우기] ${sg.title}${sg.detail.isEmpty ? '' : ' — ${sg.detail}'}'
        '${sg.files.isEmpty ? '' : '\n사진: ${sg.files.map((f) => f.split(RegExp(r'[\\/]')).last).join(', ')}'}';
    return (await c.addRecord(text)) != null;
  }

  @override
  Future<Map<String, bool>> checkConnections() async {
    final c = await client();
    final ok = await c.health();
    var face = false;
    if (ok) {
      try {
        final r = await c.recognition();
        face = r['faces'] == true;
      } catch (_) {}
    }
    return {'하드 엔진': ok, '얼굴 모델': face};
  }
}
