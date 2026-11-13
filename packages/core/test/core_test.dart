import 'package:flutter/widgets.dart';
import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeModule extends AssistantModule {
  _FakeModule(this.id, this.hits);
  @override
  final ModuleId id;
  final List<SearchHit> hits;
  @override
  Future<Widget> open() => throw UnimplementedError();
  @override
  Future<List<SearchHit>> search(String q) async => hits;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('core'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('음성 라우터', () {
    final r = VoiceRouter();
    test('지시서 예시 다섯 가지가 맞는 모듈로 간다', () {
      expect(r.route('이번 주 조회수').module, ModuleId.channel);
      expect(r.route('지난달 유튜브 앱 얘기한 대화').module, ModuleId.chats);
      expect(r.route('2005년 아이들 영상').module, ModuleId.harddisk);
      expect(r.route('이건 판매').module, ModuleId.declutter);
      expect(r.route('힉스필드 언제 끝나').module, ModuleId.vault);
    });
    test('브리핑·오늘 할 일·홈', () {
      expect(r.route('아침 브리핑 해 줘').intent, 'briefing');
      expect(r.route('오늘 할 일').intent, 'today');
      expect(r.route('홈으로').intent, 'home');
    });
    test('애매하면 두 후보', () {
      final x = r.route('사진 정리할 물건');
      expect(x.isAmbiguous || x.module != null, isTrue);
      final y = r.route('구독 채널');
      expect(y.isAmbiguous, isTrue);
      expect(y.alternatives.toSet(), {ModuleId.channel, ModuleId.vault});
    });
    test('비밀번호는 읽지 않는다', () {
      final x = r.route('넷플릭스 비밀번호 읽어 줘');
      expect(x.refusal, isNotNull);
      expect(x.intent, 'refuse_password');
    });
    test('중요 명령은 확인', () {
      expect(r.route('이 영상 채널에 업로드').needsConfirm, isTrue);
      expect(r.route('이 물건 폐기').needsConfirm, isTrue);
      expect(r.route('이번 주 조회수').needsConfirm, isFalse);
    });
    test('모르는 말', () => expect(r.route('날씨 어때').intent, 'unknown'));
    test('메타지우개: 메타데이터·위치 정보 이야기는 메타지우개 플러스로', () {
      expect(r.route('메타지우개 열어 줘').module, ModuleId.metaclean);
      expect(r.route('사진 메타데이터 보여줘').module, ModuleId.metaclean);
      final x = r.route('사진 위치 정보 지워 줘');
      expect(x.module, ModuleId.metaclean);
      expect(x.needsConfirm, isTrue);
      // 원래 다섯 모듈 예시는 그대로
      expect(r.route('2005년 아이들 영상').module, ModuleId.harddisk);
    });
  });

  test('비밀 값 가리기', () {
    expect(Redact.text('password=abcd1234 hi'), isNot(contains('abcd1234')));
    expect(Redact.text('key sk-abcdefghijklmnop'), isNot(contains('sk-abcdef')));
    expect(Redact.text('GOCSPX-abc123_x'), '[가림]');
    expect(Redact.looksSecret('안녕하세요'), isFalse);
  });

  test('기록에 비밀 값이 남지 않는다', () {
    final f = File('${tmp.path}/log/app.log');
    CoreLog.init(f);
    CoreLog.error('실패 token=ya29.SECRETVALUE');
    expect(f.readAsStringSync(), isNot(contains('SECRETVALUE')));
  });

  test('브리핑은 모듈 순서대로, 없으면 안내', () {
    final s = Briefing.compose({
      ModuleId.vault: [const TodayItem(module: ModuleId.vault, text: '힉스필드 3일 뒤 만료', urgency: 90)],
      ModuleId.channel: [const TodayItem(module: ModuleId.channel, text: '확인 대기 영상 2개')],
    }, userName: '관학', now: DateTime(2026, 1, 1, 8));
    expect(s, startsWith('좋은 아침이에요, 관학님.'));
    expect(s.indexOf('채널'), lessThan(s.indexOf('금고')));
    expect(Briefing.compose({}), contains('급한 일이 없어요'));
    final (top, rest) = Briefing.pickTop([
      const TodayItem(module: ModuleId.chats, text: 'a', urgency: 10),
      const TodayItem(module: ModuleId.vault, text: 'b', urgency: 95),
    ]);
    expect(top!.text, 'b');
    expect(rest.single.text, 'a');
  });

  test('설정은 파일에 남고 다시 읽힌다', () {
    final f = File('${tmp.path}/settings.json');
    final s = AppSettings(f)
      ..textSize = TextSize.huge
      ..themeMode = 'dark'
      ..setLink('hardToChannel', false);
    expect(s.textSize.scale, 1.5);
    final s2 = AppSettings(f);
    expect(s2.textSize, TextSize.huge);
    expect(s2.themeMode, 'dark');
    expect(s2.linkOn('hardToChannel'), isFalse);
    expect(s2.linkOn('declutterToChannel'), isTrue);
  });

  test('깨진 설정 파일이어도 기본값으로 시작', () {
    final f = File('${tmp.path}/settings.json')..writeAsStringSync('{깨짐');
    expect(AppSettings(f).appName, '개인비서');
  });

  test('로그인: 만들기·확인·자동 로그인', () async {
    final secrets = MemorySecrets();
    final a = AuthService(file: File('${tmp.path}/users.json'), secrets: secrets, iterations: 1000);
    final u = a.create('관학', '1234');
    expect(() => a.create('관학', '5678'), throwsArgumentError);
    expect(() => a.create('x', '12'), throwsArgumentError);
    expect(a.verify(u.id, '1234')?.name, '관학');
    expect(a.verify(u.id, '0000'), isNull);
    expect(File('${tmp.path}/users.json').readAsStringSync(), isNot(contains('1234')));
    await a.setAutoLogin(u, true);
    expect((await a.tryAutoLogin())?.id, u.id);
    await a.logout();
    expect(await a.tryAutoLogin(), isNull);
  });

  test('통합 검색은 비밀 값을 버린다', () async {
    final s = UnifiedSearch([
      _FakeModule(ModuleId.vault, const [
        SearchHit(module: ModuleId.vault, title: '넷플릭스', subtitle: '월 13,500원'),
        SearchHit(module: ModuleId.vault, title: '넷플릭스 비밀번호', subtitle: 'abc', kind: 'password'),
        SearchHit(module: ModuleId.vault, title: 'x', subtitle: 'password: hunter2'),
      ]),
      _FakeModule(ModuleId.chats, const [SearchHit(module: ModuleId.chats, title: '넷플릭스 해지 얘기')]),
    ]);
    final r = await s.run('넷플릭스');
    expect(r[ModuleId.vault]!.map((e) => e.title), ['넷플릭스']);
    expect(r[ModuleId.chats]!.length, 1);
    expect(await s.run('  '), isEmpty);
  });

  test('제안함: 꺼진 연결은 넣지 않고, 같은 제안은 한 번만', () {
    final f = File('${tmp.path}/links.json');
    final hub = LinkHub(file: f, enabled: (k) => k != LinkKind.hardToVault);
    Suggestion mk(String id, LinkKind k) => Suggestion(id: id, kind: k, from: ModuleId.declutter, to: ModuleId.channel, title: '의자 사연');
    expect(hub.propose(mk('a', LinkKind.declutterToChannel)), isTrue);
    expect(hub.propose(mk('a', LinkKind.declutterToChannel)), isFalse);
    expect(hub.propose(mk('b', LinkKind.hardToVault)), isFalse);
    hub.accept('a');
    final again = LinkHub(file: f);
    expect(again.all.single.status, 'accepted');
    expect(again.pendingFor(ModuleId.channel), isEmpty);
  });

  test('버전 비교', () {
    expect(UpdateChecker.compare('v1.2.0', '1.1.9'), 1);
    expect(UpdateChecker.compare('1.0.0', '1.0.0+5'), 0);
    expect(UpdateChecker.compare('0.9', '1.0.0'), -1);
  });

  test('해시 확인', () async {
    final f = File('${tmp.path}/a.bin')..writeAsStringSync('abc');
    expect(await UpdateChecker.verify(f, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'), isTrue);
    expect(await UpdateChecker.verify(f, '0' * 64), isFalse);
  });
}
