import 'dart:io';

import 'package:ai_chat_organizer/assistant_entry.dart';
import 'package:ai_chat_organizer/data/key_store.dart';
import 'package:ai_chat_organizer/services/app_controller.dart';
import 'package:ai_chat_organizer/voice/voice_service.dart';
import 'package:assistant_core/assistant_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/app/keys.dart';
import 'package:personal_assistant/modules/chats_module.dart';

import 'support.dart';

const _samples = '../../packages/chats/assets/samples';

AppController _controller(Directory root) => AppController(
      root: Directory('${root.path}/ai_chat_organizer')..createSync(recursive: true),
      keys: MemoryKeyStore(),
      voice: NoVoiceService(),
      inMemoryDb: true,
      autoUpdateCheck: false,
      loadAsset: (a) async => File('$_samples/${a.split('/').last}').readAsBytesSync(),
    );

/// 실제 대화로(샘플 표시 없이) 세 AI 파일을 넣은 컨트롤러.
Future<AppController> _withRealChats(Directory root) async {
  final c = _controller(root);
  await c.init();
  await signInAs(c, '나');
  for (final f in ['claude_sample.json', 'chatgpt_sample.json', 'gemini_sample.html']) {
    final j = await c.importBytes(f, File('$_samples/$f').readAsBytesSync());
    expect(j?.state, JobState.done, reason: f);
  }
  return c;
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('chats_module_test'));
  tearDown(() => root.deleteSync(recursive: true));

  test('오늘 할 일·상태 줄: 내보내기 요청 알림과 대화 수', () async {
    final s = fakeState(root);
    final c = await _withRealChats(root);
    final m = ChatsModule(s, make: () async => c);
    final items = await m.today();
    expect(items.any((i) => i.text.contains('내보내기 요청할 때예요')), isTrue);
    expect(items.every((i) => i.module == ModuleId.chats), isTrue);
    expect(await m.statusLine(), '대화 ${c.session!.store.count()}개');
    expect(c.session!.store.count(), greaterThan(0));
  });

  test('잠금 번호가 있으면 오늘 할 일·검색은 비어 있다', () async {
    final s = fakeState(root);
    final c = _controller(root);
    await c.init();
    await c.createUser('나', pin: '1234');
    c.signOut();
    await signInAs(c, '나'); // 잠금이 있으면 들어가지 않는다
    expect(c.session, isNull);
    final m = ChatsModule(s, make: () async => c);
    expect(await m.today(), isEmpty);
    expect(await m.search('썸네일'), isEmpty);
    expect(await m.proposeDecisions(s.links), 0);
  });

  test('통합 검색: 제목과 찾은 부분', () async {
    final s = fakeState(root);
    final c = await _withRealChats(root);
    final m = ChatsModule(s, make: () async => c);
    final hits = await m.search('썸네일');
    expect(hits, isNotEmpty);
    expect(hits.first.module, ModuleId.chats);
    expect(hits.any((h) => h.title.contains('썸네일')), isTrue);
    expect(await m.search(''), isEmpty);
  });

  test('음성 명령: 개수와 첫 제목을 말한다', () async {
    final s = fakeState(root);
    final c = await _withRealChats(root);
    final m = ChatsModule(s, make: () async => c);
    final r = await m.handle(const VoiceCommand('유튜브 썸네일 얘기한 대화 찾아줘'));
    expect(r, isNotNull);
    expect(r!.speak, contains('개'));
    expect(r.speak, contains('썸네일'));
    expect(r.openModule, isTrue);
    final none = await m.handle(const VoiceCommand('지난달 화성탐사선 얘기한 대화'));
    expect(none!.speak, contains('찾지 못했어요'));
    expect(none.openModule, isFalse);
  });

  test('대화 → 모든 모듈: 결정 문장을 제안하고 다시 넣지 않는다', () async {
    final s = fakeState(root);
    final c = await _withRealChats(root);
    final m = ChatsModule(s, make: () async => c);
    final n = await m.proposeDecisions(s.links);
    expect(n, greaterThan(0));
    final p = s.links.pending;
    expect(p.every((x) => x.kind == LinkKind.chatsToAll && x.from == ModuleId.chats), isTrue);
    expect(p.any((x) => x.to == ModuleId.channel), isTrue);
    expect(await m.proposeDecisions(s.links), 0);
    expect(ChatsModule.decisionTarget('당근에 팔기로 했어'), ModuleId.declutter);
    expect(ChatsModule.decisionTarget('넷플릭스 구독은 해지하기로 결정'), ModuleId.vault);
    expect(ChatsModule.decisionTarget('옛날 사진은 하드에 모으기로 했어'), ModuleId.harddisk);
    expect(ChatsModule.decisionTarget('점심은 국수로 하자'), isNull);
    expect(ChatsModule.stableHash('a'), ChatsModule.stableHash('a'));
  });

  test('샘플 대화는 제안하지 않는다', () async {
    final s = fakeState(root);
    final c = _controller(root);
    await c.init();
    await signInAs(c, '나');
    await c.importSamples();
    final m = ChatsModule(s, make: () async => c);
    expect(await m.proposeDecisions(s.links), 0);
  });

  test('하나의 열쇠: 모듈에 없을 때만 AI·구글 열쇠를 넣는다', () async {
    final s = fakeState(root);
    final keys = SharedKeys(s.secrets);
    await keys.setAi('claude', 'sk-ant-test-0000');
    await keys.setGoogleJson('{"installed":{"client_id":"1-abc.apps.googleusercontent.com","client_secret":"GOCSPX-test"}}');
    final c = _controller(root);
    await c.init();
    await signInAs(c, '나');
    final m = ChatsModule(s, make: () async => c);
    await m.open();
    expect(await c.hasApiKey(), isTrue);
    expect(await c.gmail().hasSecret(), isTrue);
    expect(c.settings.gmailClientId, '1-abc.apps.googleusercontent.com');

    // 모듈에 이미 있는 열쇠는 덮어쓰지 않는다
    await c.setApiKey('sk-ant-own');
    await m.shareKeys(c);
    expect(await c.keys.read('apikey-claude-${c.session!.user.id}'), 'sk-ant-own');
  });

  test('다른 AI 열쇠(클로드 아님)는 넣지 않는다', () async {
    final s = fakeState(root);
    await SharedKeys(s.secrets).setAi('openai', 'sk-other');
    final c = _controller(root);
    await c.init();
    await signInAs(c, '나');
    await ChatsModule(s, make: () async => c).shareKeys(c);
    expect(await c.hasApiKey(), isFalse);
  });
}
