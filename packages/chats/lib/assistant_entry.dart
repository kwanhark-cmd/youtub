// 개인비서(통합 앱)에서 이 모듈을 여는 입구. 단독 앱 main.dart 와 같은 준비를 한다.
// 자료는 통합 앱 사용자 폴더 아래 `ai_chat_organizer/` (DataLocation 그대로).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app.dart';
import 'core/app_log.dart';
import 'data/conversation_store.dart';
import 'data/key_store.dart';
import 'models/models.dart';
import 'search/query_parser.dart';
import 'search/search_service.dart';
import 'services/app_controller.dart';
import 'services/data_location.dart';
import 'summary/summarizer.dart';
import 'voice/voice_service.dart';

Future<AppController> openChatsController({required String userName, Directory? rootOverride}) async {
  final root = rootOverride ?? await DataLocation.resolve();
  root.createSync(recursive: true);
  AppLog.init(File('${root.path}/logs/app.log'));
  final c = hostedChatsController(root: root, keys: SecureKeyStore(File('${root.path}/.keys')), voice: DeviceVoiceService());
  c.openBrowser = (u) async {
    await launchUrl(u, mode: LaunchMode.externalApplication);
  };
  await c.init();
  await signInAs(c, userName);
  return c;
}

/// 개인비서 안에서 쓰는 대화 컨트롤러: 단독 앱 업데이트(카드·배지·하루 한 번 확인)를 끈다.
/// 업데이트는 개인비서 설정 하나로. [inMemoryDb]·[loadAsset]은 시험에서만 바꾼다.
AppController hostedChatsController({
  required Directory root,
  required KeyStore keys,
  required VoiceService voice,
  bool inMemoryDb = false,
  Future<Uint8List> Function(String asset)? loadAsset,
}) =>
    AppController(root: root, keys: keys, voice: voice, inMemoryDb: inMemoryDb, loadAsset: loadAsset, hostedByAssistant: true);

/// 개인비서 로그인 이름과 같은 사용자로 바로 들어간다. 없으면 만든다.
/// 기존 사용자에게 잠금 번호가 있으면 모듈 자기 잠금 화면을 그대로 보여 준다(건너뛰지 않음).
Future<void> signInAs(AppController c, String userName) async {
  final name = userName.trim().isEmpty ? '나' : userName.trim();
  if (c.session?.user.name == name) return;
  final same = c.profiles.where((u) => u.name == name).toList();
  if (same.isEmpty) {
    if (c.profiles.isEmpty) await c.createUser(name);
    return;
  }
  if (same.first.pinHash == null) await c.signIn(same.first);
}

Widget chatsApp(AppController c) => AiChatOrganizerApp(controller: c);

// ---------- 개인비서 홈·검색·연결에 쓰는 읽기 전용 도우미 ----------

/// 주제가 하나도 정해지지 않은 대화 수(숨긴 샘플 제외). 사용자 자료가 열려 있지 않으면 0.
int chatsUnclassifiedCount(AppController c) {
  final s = c.session;
  if (s == null) return 0;
  return s.store.db
      .select(
        "SELECT COUNT(*) AS n FROM conversations c WHERE ${s.store.sampleCond()} "
        "AND NOT EXISTS (SELECT 1 FROM conversation_topics t WHERE t.conv_id=c.id AND t.origin!='removed')",
      )
      .first['n'] as int;
}

/// 모듈 자기 검색(말 → 검색 조건 → 본문 전체 검색). 자료가 열려 있지 않으면 null.
Future<({SearchQuery query, List<SearchHit> hits, bool hasMore})?> chatsSearch(AppController c, String text, {int limit = 20, DateTime? now}) async {
  final s = c.session;
  if (s == null) return null;
  final q = QueryParser.parse(text, now: now, exact: s.settings.exactMatch, similar: s.settings.similarWords);
  if (q.isEmpty) return (query: q, hits: const <SearchHit>[], hasMore: false);
  final page = await s.search.search(q, limit: limit);
  return (query: q, hits: page.hits, hasMore: page.hasMore);
}

/// 대화 하나에서 찾은 "정한 내용" 한 문장.
class ChatDecision {
  const ChatDecision({required this.text, required this.conversation});
  final String text;
  final ConversationSummary conversation;
}

final _decisionWords = RegExp(r'(하기로|결정|정했|로 하자|으로 하자)');
final _sentenceSplit = RegExp(r'(?<=[.!?。])\s+|\n+');

/// 최근 [limit]개 실제 대화(샘플 제외)의 제목·메시지에서 결정처럼 보이는 문장을 찾는다.
Future<List<ChatDecision>> chatsRecentDecisions(AppController c, {int limit = 20}) async {
  final s = c.session;
  if (s == null) return const [];
  final rows = s.store.db.select(
    'SELECT ${ConversationStore.summaryColumns} FROM conversations c WHERE c.sample=0 ORDER BY c.created_at DESC, c.id DESC LIMIT ?',
    [limit],
  );
  final out = <ChatDecision>[];
  for (final r in rows) {
    final conv = ConversationStore.rowToSummary(r);
    final seen = <String>{};
    void add(String raw) {
      final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (t.length < 4 || t.length > 160 || !seen.add(t)) return;
      if (_decisionWords.hasMatch(t)) out.add(ChatDecision(text: t, conversation: conv));
    }

    add(conv.title);
    final msgs = await s.store.messages(conv.id);
    for (final d in OfflineSummarizer.decisionsIn(msgs)) {
      add(d);
    }
    for (final m in msgs) {
      for (final part in m.text.split(_sentenceSplit)) {
        add(part);
      }
    }
  }
  return out;
}
