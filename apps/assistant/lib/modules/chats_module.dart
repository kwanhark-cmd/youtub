import 'dart:async';

import 'package:ai_chat_organizer/assistant_entry.dart';
import 'package:ai_chat_organizer/models/models.dart';
import 'package:ai_chat_organizer/services/app_controller.dart';
import 'package:ai_chat_organizer/voice/voice_command.dart' as chats;
import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/widgets.dart';

import '../app/assistant_state.dart';
import '../app/keys.dart';
import 'lazy.dart';

class ChatsModule extends PackagedModule {
  /// [make]: 시험에서 기기 기능 없는 컨트롤러를 넣을 때 쓴다.
  ChatsModule(this.s, {Future<AppController> Function()? make})
      : _make = make ?? (() => openChatsController(userName: s.user?.name ?? '나'));
  final AssistantState s;
  final Future<AppController> Function() _make;
  late final lazy = Lazy<AppController>(() async {
    final c = await _make();
    await shareKeys(c);
    return c;
  });

  @override
  ModuleId get id => ModuleId.chats;
  @override
  String get package => 'ai_chat_organizer';

  @override
  Future<Widget> open() async {
    final c = await lazy.get();
    await shareKeys(c); // 잠금 번호로 늦게 들어온 경우를 위해 한 번 더
    return chatsApp(c);
  }

  /// 개인비서의 하나의 열쇠 → 모듈 열쇠 (모듈에 없을 때만). 열쇠 값은 절대 기록하지 않는다.
  Future<void> shareKeys(AppController c) async {
    if (c.session == null) return;
    final keys = SharedKeys(s.secrets);
    try {
      final ai = await keys.ai();
      if (ai != null && ai.provider == 'claude' && !await c.hasApiKey()) {
        await c.setApiKey(ai.key);
        CoreLog.info('대화 모듈에 AI 열쇠 연결');
      }
    } catch (e) {
      CoreLog.warn('대화 모듈 AI 열쇠 연결 실패 (${e.runtimeType})');
    }
    try {
      final g = await keys.googleClient();
      if (g != null && g.clientSecret.isNotEmpty) {
        final gm = c.gmail();
        if (!await gm.hasSecret()) {
          await gm.saveSecret(g.clientSecret);
          if ((c.settings.gmailClientId ?? '').isEmpty) c.updateSettings((x) => x.gmailClientId = g.clientId);
          CoreLog.info('대화 모듈에 구글 열쇠 연결');
        }
        gm.client.close();
      }
    } catch (e) {
      CoreLog.warn('대화 모듈 구글 열쇠 연결 실패 (${e.runtimeType})');
    }
  }

  /// 잠금 번호 때문에 아직 못 들어간 경우 null.
  Future<AppController?> _ready() async {
    final c = await lazy.get();
    return c.session == null ? null : c;
  }

  @override
  Future<String> statusLine() async {
    if (!lazy.isLoaded) return '클로드·챗GPT·제미나이 대화';
    final c = lazy.value!;
    final ss = c.session;
    if (ss == null) return '잠금 번호를 넣어 주세요';
    return '대화 ${ss.store.count()}개';
  }

  @override
  Future<List<TodayItem>> today() async {
    try {
      final c = await _ready();
      if (c == null) return const [];
      final ss = c.session!;
      final out = <TodayItem>[];
      final total = ss.store.count();
      final mails = c.settings.gmailFoundCount;
      if (total == 0) {
        out.add(const TodayItem(module: ModuleId.chats, text: 'AI 대화 기록 파일을 넣어 주세요', urgency: 20, actionLabel: '대화 넣기'));
      }
      if (mails > 0) {
        out.add(TodayItem(
          module: ModuleId.chats,
          text: '내보내기 안내 메일이 $mails통 왔어요. 링크가 만료되기 전에 내려받아 넣어요',
          urgency: 70,
          actionLabel: '내려받고 넣기',
        ));
      }
      final due = c.settings.exportDue(DateTime.now());
      if (due.isNotEmpty) {
        out.add(TodayItem(
          module: ModuleId.chats,
          text: '${due.map((d) => d.label).join(', ')} 대화 기록 내보내기 요청할 때예요',
          urgency: 40,
          actionLabel: '내보내기 요청',
        ));
      }
      final un = chatsUnclassifiedCount(c);
      if (un > 0) {
        out.add(TodayItem(module: ModuleId.chats, text: '주제가 안 정해진 대화 $un개를 정리해요', urgency: 30, actionLabel: '주제 정리'));
      }
      unawaited(proposeDecisions(s.links).catchError((Object e) {
        CoreLog.warn('대화 결정 제안 실패 (${e.runtimeType})');
        return 0;
      }));
      return out;
    } catch (e, st) {
      CoreLog.error('대화 모듈 오늘 할 일 실패', e, st);
      return const [];
    }
  }

  @override
  Future<List<SearchHit>> search(String query) async {
    try {
      final c = await _ready();
      if (c == null) return const [];
      final r = await chatsSearch(c, query);
      if (r == null) return const [];
      return [
        for (final h in r.hits)
          SearchHit(
            module: ModuleId.chats,
            title: h.conversation.title,
            subtitle: h.snippet.isEmpty ? h.conversation.source.label : '${h.conversation.source.label} · ${h.snippet}',
            kind: '대화',
          ),
      ];
    } catch (e, st) {
      CoreLog.error('대화 검색 실패', e, st);
      return const [];
    }
  }

  @override
  Future<ModuleReply?> handle(VoiceCommand cmd) async {
    try {
      final c = await _ready();
      if (c == null) return const ModuleReply('대화 기록은 잠금 번호를 넣어야 볼 수 있어요.', openModule: true);
      final parsed = chats.VoiceCommandParser.parse(cmd.text);
      switch (parsed) {
        case chats.SearchCommand(:final text):
          final r = await chatsSearch(c, text, limit: 50);
          if (r == null || r.query.isEmpty) return null;
          final what = [if (r.query.dateLabel != null) r.query.dateLabel!, ...r.query.keywords].join(' ');
          if (r.hits.isEmpty) return ModuleReply('$what 대화는 찾지 못했어요.');
          final n = r.hasMore ? '${r.hits.length}개 넘게' : '${r.hits.length}개';
          return ModuleReply('$what 대화 $n 찾았어요. 첫 번째는 "${r.hits.first.conversation.title}"예요.', openModule: true);
        case chats.ClassifyRecentCommand(:final todayOnly):
          final ids = todayOnly ? c.todayImportedIds() : c.allIds();
          if (ids.isEmpty) return const ModuleReply('정리할 대화가 없어요.');
          final j = await c.classify(ids, useAi: false);
          return ModuleReply(j?.message ?? '지금은 다른 작업 중이에요. 잠시 뒤에 해 주세요.');
        default:
          return const ModuleReply('대화 기록을 열게요.', openModule: true);
      }
    } catch (e, st) {
      CoreLog.error('대화 음성 명령 실패', e, st);
      return null;
    }
  }

  /// 대화 → 모든 모듈: 최근 대화에서 찾은 결정 사항을 해당 모듈 메모로 제안. 새로 넣은 제안 수.
  Future<int> proposeDecisions(LinkHub hub) async {
    final c = await _ready();
    if (c == null) return 0;
    var n = 0;
    for (final d in await chatsRecentDecisions(c, limit: 20)) {
      final to = decisionTarget(d.text) ?? decisionTarget(d.conversation.title);
      if (to == null) continue;
      final title = d.text.length > 60 ? '${d.text.substring(0, 60)}…' : d.text;
      final ok = hub.propose(Suggestion(
        id: 'chats-${to.name}-${stableHash('${d.conversation.source.key}|${d.conversation.externalId}|${d.text}')}',
        kind: LinkKind.chatsToAll,
        from: ModuleId.chats,
        to: to,
        title: title,
        detail: '${d.conversation.source.label} 대화 "${d.conversation.title}"에서 정한 내용',
      ));
      if (ok) n++;
    }
    return n;
  }

  /// 결정 문장 → 받을 모듈 (낱말로 판단). 맞는 곳이 없으면 null.
  static ModuleId? decisionTarget(String text) {
    final t = text.toLowerCase();
    const map = <ModuleId, List<String>>{
      ModuleId.channel: ['채널', '유튜브', 'youtube', '블로그', '영상', '썸네일'],
      ModuleId.declutter: ['물건', '판매', '폐기', '당근', '중고'],
      ModuleId.vault: ['구독', '계정', '결제'],
      ModuleId.harddisk: ['하드', '사진', '파일'],
    };
    for (final e in map.entries) {
      if (e.value.any(t.contains)) return e.key;
    }
    return null;
  }

  /// 앱을 다시 켜도 같은 값이 나오는 짧은 해시(FNV-1a 32비트).
  static String stableHash(String s) {
    var h = 0x811c9dc5;
    for (final b in s.codeUnits) {
      h ^= b;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
