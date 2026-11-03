import 'dart:convert';
import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/app/services.dart';
import 'package:channel_biseo/assistant_entry.dart';
import 'package:channel_biseo/core/logger.dart';
import 'package:channel_biseo/core/secret_store.dart';
import 'package:channel_biseo/features/ai/ai_service.dart';
import 'package:channel_biseo/features/corner/corner_service.dart';
import 'package:channel_biseo/features/runner/notifier.dart';
import 'package:channel_biseo/features/tools/tools_service.dart';
import 'package:channel_biseo/features/voice/voice_io.dart';
import 'package:channel_biseo/features/youtube/youtube_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:personal_assistant/app/assistant_state.dart';
import 'package:personal_assistant/app/keys.dart';
import 'package:personal_assistant/modules/channel_module.dart';

/// 인터넷·기기 없이 채널 모듈 상태를 만든다 (연습 모드, 메모리 DB·저장소).
Future<AppState> channelState(Directory root, MemorySecretStore secrets, DateTime now) {
  final env = AppEnv(
    baseDir: Directory('${root.path}/ch').path,
    documentsDir: root.path,
    secrets: secrets,
    httpClient: MockClient((req) async => throw StateError('네트워크 호출 금지: ${req.url.host}')),
    logger: AppLogger(),
    speech: FakeSpeechInput(),
    speaker: FakeSpeaker(),
    notifier: MemoryNotifier(),
    isDesktop: true,
    platformName: 'test',
    appVersion: '0.0.0+test',
    launchUrl: (u) async => true,
    now: () => now,
    inMemoryDb: true,
    aiProviders: {'claude': FakeAiProvider((_) => '{}')},
  );
  Directory(env.baseDir).createSync(recursive: true);
  return openChannelStateWith(env, userName: '관학', skipOnboarding: true);
}

void main() {
  late Directory root;
  late MemorySecretStore chSecrets;
  late AssistantState s;
  final now = DateTime(2026, 11, 3, 9);

  setUp(() {
    root = Directory.systemTemp.createTempSync('ch_mod');
    chSecrets = MemorySecretStore();
    s = AssistantState(root: root, secrets: MemorySecrets());
  });
  tearDown(() => root.deleteSync(recursive: true));

  ChannelModule module() => ChannelModule(s, openState: () => channelState(root, chSecrets, now));

  Future<UserContext> withChannels(ChannelModule m) async {
    final u = (await m.lazy.get()).user!;
    await u.youtube.connectGoogle(mock: true);
    for (final c in u.youtube.channels()) {
      await u.youtube.syncChannel(c.channelId);
    }
    return u;
  }

  void addProduction(UserContext u, String title, String status, {String uploadDay = ''}) {
    final ch = u.youtube.channels().first.channelId;
    u.db.execute(
      'INSERT INTO productions(channel_id, format, title, status, upload_day, day, created_at, updated_at) VALUES(?,?,?,?,?,?,?,?)',
      [ch, 'shorts', title, status, uploadDay, '2026-11-02', now.toIso8601String(), now.toIso8601String()],
    );
  }

  test('첫 실행 안내를 건너뛰고 상태 줄·오늘 할 일', () async {
    final m = module();
    final u = await withChannels(m);
    expect(u.settings.onboardingDone, isTrue);
    addProduction(u, '가을 산책 브이로그', 'uploadedPrivate');
    addProduction(u, '단풍 쇼츠', 'uploadedPrivate');
    addProduction(u, '김장 하는 날', 'uploadTomorrow', uploadDay: '2026-11-03');

    final n = u.youtube.channels().length;
    expect(await m.statusLine(), '채널 $n개 · 확인 대기 3개');
    final today = await m.today();
    final texts = today.map((e) => e.text).toList();
    expect(texts, contains('확인 대기 영상 2개'));
    expect(texts, contains('오늘 게시 예정 1개'));
    expect(today.every((e) => e.module == ModuleId.channel), isTrue);
  });

  test('구글 테스트 앱 연결 7일 만료 임박을 알린다', () async {
    final m = module();
    final u = (await m.lazy.get()).user!;
    u.db.execute('INSERT INTO accounts(provider, label, connected_at, status, mock) VALUES(?,?,?,?,0)', [
      'google',
      '내 구글',
      now.subtract(const Duration(days: 6)).toIso8601String(),
      'ok',
    ]);
    final texts = (await m.today()).map((e) => e.text);
    expect(texts, contains('구글 연결(내 구글)이 1일 뒤 만료돼요'));
  });

  test('검색: 영상 제목·제작물·메모·블로그 글', () async {
    final m = module();
    final u = await withChannels(m);
    addProduction(u, '할머니 김장 이야기', 'draft');
    u.memos.add('김장 김치 레시피 영상 아이디어');
    u.db.execute('INSERT INTO blog_sites(platform, title, added_at) VALUES(?,?,?)', ['tistory', '내 블로그', now.toIso8601String()]);
    u.db.execute('INSERT INTO posts(site_id, post_id, title, updated_at) VALUES(1, ?, ?, ?)', ['p1', '김장 준비물 정리', now.toIso8601String()]);

    final hits = await m.search('김장');
    final kinds = hits.map((h) => h.kind).toSet();
    expect(kinds, containsAll(['제작', '메모', '블로그 글']));
    expect(hits.map((h) => h.title), contains('김장 준비물 정리'));

    final video = u.youtube.videos(u.youtube.channels().first.channelId).first.title;
    final vh = await m.search(video.split(' ').first);
    expect(vh.any((h) => h.kind == '영상'), isTrue);
    expect(await m.search('  '), isEmpty);
  });

  test('음성: 이번 주 조회수는 답하고, 업로드·삭제·공개는 실행하지 않고 화면을 연다', () async {
    final m = module();
    await withChannels(m);
    final views = await m.handle(const VoiceCommand('이번 주 조회수 알려줘'));
    expect(views, isNotNull);
    expect(views!.openModule, isFalse);
    expect(views.speak, contains('조회수'));

    final up = (await m.handle(const VoiceCommand('영상 업로드해 줘')))!;
    expect(up.openModule, isTrue);
    expect(up.needsConfirm, isTrue);

    final del = (await m.handle(const VoiceCommand('영상 삭제해')))!;
    expect(del.speak, contains('하지 않아요'));
    final pub = (await m.handle(const VoiceCommand('영상 공개로 바꿔')))!;
    expect(pub.openModule, isTrue);

    final fix = (await m.handle(const VoiceCommand('영상 수정 실행')))!;
    expect(fix.openModule, isTrue);
    final u = m.lazy.value!.user!;
    expect(u.editLog.countOn('2026-11-03'), 0);

    expect(await m.handle(const VoiceCommand('냉장고 정리')), isNull);
  });

  test('제안 받기: 비우기·하드 소재를 "내 코너"에 넣는다 (올리지 않음)', () async {
    final m = module();
    final u = await withChannels(m);
    final photo = File('${root.path}/의자.jpg')..writeAsBytesSync([1, 2, 3]);
    final ok = await m.receive(Suggestion(
      id: 's1',
      kind: LinkKind.declutterToChannel,
      from: ModuleId.declutter,
      to: ModuleId.channel,
      title: '할아버지 의자',
      detail: '30년 쓴 나무 의자를 보내며',
      files: [photo.path],
    ));
    expect(ok, isTrue);
    final cs = u.extensions['corner']! as CornerService;
    final corner = cs.corners().singleWhere((c) => c.name == assistantCornerName);
    final items = cs.items(corner.id);
    expect(items.map((i) => i.kind), containsAll(['text', 'image']));
    expect(items.firstWhere((i) => i.kind == 'image').copyright, 'own');
    expect(items.firstWhere((i) => i.kind == 'text').text, contains('나무 의자'));

    final ok2 = await m.receive(Suggestion(
      id: 's2',
      kind: LinkKind.hardToChannel,
      from: ModuleId.harddisk,
      to: ModuleId.channel,
      title: '2005년 제주 여행',
      files: [photo.path],
    ));
    expect(ok2, isTrue);
    expect(cs.items(corner.id).where((i) => i.kind == 'image').last.needsCheck, isTrue);
    expect(u.db.select("SELECT COUNT(*) AS n FROM productions").first['n'], 0);

    // 다른 종류의 제안은 받지 않는다
    expect(
      await m.receive(Suggestion(id: 's3', kind: LinkKind.vaultToChannel, from: ModuleId.vault, to: ModuleId.channel, title: 'x')),
      isFalse,
    );
  });

  test('채널이 없으면 소재를 음성 메모로 남긴다', () async {
    final m = module();
    final u = (await m.lazy.get()).user!;
    final ok = await m.receive(Suggestion(
      id: 's1',
      kind: LinkKind.declutterToChannel,
      from: ModuleId.declutter,
      to: ModuleId.channel,
      title: '오래된 카메라',
    ));
    expect(ok, isTrue);
    expect(u.memos.list().single.text, contains('오래된 카메라'));
  });

  test('공용 열쇠를 채널 사용자 열쇠 자리에 넣는다 (이미 있으면 두기)', () async {
    final keys = SharedKeys(s.secrets);
    await keys.setGoogleJson(jsonEncode({
      'installed': {'client_id': '123-abc.apps.googleusercontent.com', 'client_secret': 'GOCSPX-xyz'},
    }));
    await keys.setAi('claude', 'sk-ant-test');
    await keys.set(SharedKeys.higgsfield, 'hf-key');

    final m = module();
    final st = await m.lazy.get();
    final u = st.user!;
    expect(u.settings.googleClientId, '123-abc.apps.googleusercontent.com');
    expect(await u.secrets.read(YouTubeService.googleSecretKey), 'GOCSPX-xyz');
    expect(u.ai.hasKey, isTrue);
    expect(u.settings.aiProvider, 'claude');
    expect(await u.secrets.read(AiService.keyName), 'sk-ant-test');
    expect(await (u.extensions['tools']! as ToolsService).higgsConnected, isTrue);

    // 채널 쪽에서 바꾼 값은 덮어쓰지 않는다
    u.settings.googleClientId = 'mine.apps.googleusercontent.com';
    await keys.setAi('openai', 'sk-other');
    final done = await applySharedKeys(
      u,
      const ChannelSharedKeys(googleClientId: 'x.apps.googleusercontent.com', aiProvider: 'openai', aiKey: 'sk-other'),
    );
    expect(done, isEmpty);
    expect(u.settings.googleClientId, 'mine.apps.googleusercontent.com');
    expect(channelAiProvider('gemini'), 'gemini');
  });

  test('지원하지 않는 AI 제공자 열쇠는 넣지 않는다', () async {
    await SharedKeys(s.secrets).setAi('openai', 'sk-openai');
    final m = module();
    final u = (await m.lazy.get()).user!;
    expect(u.ai.hasKey, isFalse);
    expect(u.settings.aiProvider, 'claude');
  });
}
