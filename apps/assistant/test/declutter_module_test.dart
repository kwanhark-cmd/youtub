import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:binugi/assistant_entry.dart';
import 'package:binugi/core/clock.dart';
import 'package:binugi/data/models.dart';
import 'package:binugi/services/image_service.dart';
import 'package:binugi/services/secret_store.dart';
import 'package:binugi/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:binugi/theme/app_theme.dart' show TextSizeChoice, ThemeModeChoice;

import 'package:path/path.dart' as p;
import 'package:personal_assistant/app/assistant_state.dart';
import 'package:personal_assistant/app/keys.dart';
import 'package:personal_assistant/modules/declutter_module.dart';
import 'package:personal_assistant/modules/registry.dart';

import 'support.dart';

/// 진짜 비우기 모듈 코드(메모리 DB, 임시 폴더, 가짜 시계)로 홈·검색·음성·연결을 확인한다.
void main() {
  late Directory root;
  late AssistantState s;
  late DeclutterModule m;
  late AppState st;
  late MemorySecretStore modSecrets;
  final clock = FakeClock(DateTime(2026, 3, 1, 9));

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pa_declutter_');
    modSecrets = MemorySecretStore();
    s = AssistantState(
      root: root,
      secrets: MemorySecrets(),
      modules: ModuleRegistry([for (final id in ModuleId.values) FakeModule(id)]),
    );
    m = DeclutterModule(s, opener: () => openDeclutterState(rootOverride: Directory(p.join(root.path, 'binugi')), inMemory: true, clock: clock, secretStore: modSecrets));
    st = await m.lazy.get();
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  Future<SavedPhoto> photo(String name) async {
    final rel = p.join('사진', '$name.jpg');
    final f = File(st.paths.abs(rel));
    await f.parent.create(recursive: true);
    await f.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
    return SavedPhoto(rel, rel, null, 1, 1);
  }

  test('오늘 할 일·상태 줄: 정할 물건 개수와 가격 인하 추천', () async {
    await st.addItem(name: '낡은 의자', description: '다리가 흔들림');
    await st.addItem(name: '전기 주전자');
    final cam = await st.addItem(name: '필름 카메라', decision: Decision.sell);
    await st.sales.startSelling(cam, price: 50000);
    clock.advance(const Duration(days: 20));
    await st.refresh();

    final t = await m.today();
    expect(t.any((e) => e.text.startsWith('오늘 정할 물건 2개')), isTrue, reason: t.map((e) => e.text).join('\n'));
    final drop = t.firstWhere((e) => e.text.contains('가격 내리기'));
    expect(drop.text, contains('필름 카메라'));
    expect(drop.text, contains('50,000원'));
    expect(await m.statusLine(), '정할 물건 2개 · 판매 중 1개');
  });

  test('검색: 이름·설명으로 찾고 상태·가격을 보여 준다', () async {
    await st.addItem(name: '낡은 의자', description: '다리가 흔들림', room: '거실');
    final cam = await st.addItem(name: '필름 카메라', decision: Decision.sell);
    await st.sales.startSelling(cam, price: 50000);
    await st.addItem(name: '깨진 화분', decision: Decision.discard);

    final a = await m.search('흔들');
    expect(a.single.title, '낡은 의자');
    expect(a.single.subtitle, contains('정하지 않음'));
    expect(a.single.subtitle, contains('거실'));
    final b = await m.search('카메라');
    expect(b.single.subtitle, contains('판매'));
    expect(b.single.subtitle, contains('50,000원'));
    expect((await m.search('화분')).single.subtitle, contains('폐기'));
    expect(await m.search('없는물건'), isEmpty);
  });

  test('음성: "이건 폐기"는 바로 실행하지 않고 개수를 알려 주며 모듈을 연다', () async {
    final chair = await st.addItem(name: '낡은 의자');
    final r = await m.handle(const VoiceCommand('이건 폐기'));
    expect(r, isNotNull);
    expect(r!.openModule, isTrue);
    expect(r.speak, contains('1개'));
    final after = (await st.repo.items(st.uid)).firstWhere((i) => i.id == chair.id);
    expect(after.decision, isNull);
    expect((await m.handle(const VoiceCommand('이건 판매')))!.openModule, isTrue);
    expect((await m.handle(const VoiceCommand('비우기 현황')))!.speak, contains('전체 물건은 1개'));
    expect(await m.handle(const VoiceCommand('날씨 알려줘')), isNull);
  });

  test('연결 제안: 사연·타임랩스·디지털 기록, 반복해도 겹치지 않음', () async {
    final story = await st.addItem(name: '할머니 재봉틀', photo: await photo('a'));
    await st.saveStory(story, '어릴 때 할머니가 옷을 지어 주시던 재봉틀');
    await st.addItem(name: '사연만 있는 물건'); // 사진 없음 → 제안 없음
    final dig = await st.addItem(name: '졸업 앨범', photo: await photo('b'));
    await st.keepDigitallyAndDiscard(dig);
    final mp4 = File(p.join(st.paths.exportTimelapse.path, '타임랩스_거실_세로_1.mp4'));
    await mp4.writeAsBytes([0, 0, 0, 0]);

    final n = await m.proposeLinks(s.links);
    expect(n, 3);
    final all = s.links.all;
    final st1 = all.firstWhere((e) => e.id == 'declutter.story.${story.id}');
    expect(st1.kind, LinkKind.declutterToChannel);
    expect(st1.to, ModuleId.channel);
    expect(st1.title, '할머니 재봉틀 사연');
    expect(st1.detail, contains('재봉틀'));
    expect(File(st1.files.single).existsSync(), isTrue);
    final tl = all.firstWhere((e) => e.files.contains(mp4.path));
    expect(tl.kind, LinkKind.declutterToChannel);
    final d = all.firstWhere((e) => e.kind == LinkKind.declutterToHard);
    expect(d.to, ModuleId.harddisk);
    expect(d.title, contains('졸업 앨범'));
    expect(d.files, isNotEmpty);

    expect(await m.proposeLinks(s.links), 0);
    await m.today(); // today()도 제안을 부르지만 겹치지 않음
    expect(s.links.all.length, 3);
  });

  test('본체 열쇠 → 모듈 설정: 비어 있을 때만 넣는다', () async {
    final keys = SharedKeys(s.secrets);
    await keys.setAi('claude', 'sk-ant-test');
    await keys.setGoogleJson('{"installed":{"client_id":"abc.apps.googleusercontent.com","client_secret":"sec"}}');
    expect(await m.syncSharedKeys(st), isTrue);
    expect(st.user.apiKey, 'sk-ant-test');
    expect(st.user.googleClientSecret, 'sec');
    expect(st.user.googleClientId, 'abc.apps.googleusercontent.com');
    expect(modSecrets.values[apiKeyName(st.uid)], 'sk-ant-test');

    await keys.setAi('claude', 'sk-ant-other');
    expect(await m.syncSharedKeys(st), isFalse);
    expect(st.user.apiKey, 'sk-ant-test');
  });

  test('개인비서 입구(openDeclutterState): 단독 앱 업데이트 카드·배너 숨김', () async {
    expect(st.hostedByAssistant, isTrue);
  });

  test('개인비서 보기 설정이 열 때 넘어가고 첫 안내는 건너뜀', () async {
    s.settings
      ..textSize = TextSize.large
      ..themeMode = 'dark'
      ..reduceMotion = true;
    await m.open();
    expect(st.global.textSize, TextSizeChoice.large);
    expect(st.global.theme, ThemeModeChoice.dark);
    expect(st.global.reduceMotion, isTrue);
    expect(st.global.onboarded, isTrue);
    s.settings.highContrast = true;
    await m.open();
    expect(st.global.theme, ThemeModeChoice.highContrast);
  });
}
