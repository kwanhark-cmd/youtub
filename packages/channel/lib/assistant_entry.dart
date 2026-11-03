// 개인비서(통합 앱)에서 이 모듈을 여는 입구. 단독 앱의 main.dart 와 같은 준비를 하되,
// 자료는 통합 앱 사용자 폴더 아래 `channel_biseo/` 에 두고, 로그인은 개인비서 로그인 하나로 대신한다.
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app/app.dart';
import 'app/services.dart';
import 'core/db.dart';
import 'core/logger.dart';
import 'core/secret_store.dart';
import 'features/corner/corner_service.dart';
import 'features/corner/material_source.dart';
import 'features/production/production_service.dart';
import 'features/runner/notifier.dart';
import 'features/tools/tools_service.dart';
import 'features/update/installer.dart';
import 'features/voice/voice_commands.dart';
import 'features/voice/voice_io.dart';
import 'stages.dart';
import 'ui/google_setup_screen.dart';

/// 채널 모듈 자료 폴더 이름 (통합 앱 사용자 폴더 아래)
const channelFolder = 'channel_biseo';

bool _stagesRegistered = false;

/// 채널 모듈 준비 (한 번만). [userName]은 개인비서에 로그인한 사람 이름.
/// [skipOnboarding]: 개인비서가 글씨 크기·테마를 이미 정했으므로 첫 실행 안내를 건너뛴다.
Future<AppState> openChannelState({
  required String userName,
  required String appVersion,
  String? baseDir,
  bool skipOnboarding = false,
}) async {
  final support = baseDir ?? p.join((await getApplicationSupportDirectory()).path, channelFolder);
  Directory(support).createSync(recursive: true);
  String docs;
  try {
    docs = p.join((await getApplicationDocumentsDirectory()).path, '개인비서', '채널');
    Directory(docs).createSync(recursive: true);
  } catch (_) {
    docs = support;
  }
  final log = AppLogger(file: File(p.join(support, 'logs', 'app.log')));
  final env = AppEnv(
    baseDir: support,
    documentsDir: docs,
    secrets: OsSecretStore(),
    httpClient: http.Client(),
    logger: log,
    speech: DeviceSpeechInput(log),
    speaker: DeviceSpeaker(log),
    notifier: DeviceNotifier(log),
    isDesktop: Platform.isWindows || Platform.isMacOS || Platform.isLinux,
    platformName: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    appVersion: appVersion,
    launchUrl: (u) => launchUrl(u, mode: LaunchMode.externalApplication),
    pickFile: (ext) async {
      final f = await FilePicker.pickFile(
        type: ext.isEmpty ? FileType.any : FileType.custom,
        allowedExtensions: ext.isEmpty ? null : ext,
      );
      return f?.path;
    },
    pickDirectory: () => FilePicker.getDirectoryPath(),
    installUpdate: UpdateInstaller(log).install,
    osName: Platform.operatingSystem,
  );
  return openChannelStateWith(env, userName: userName, skipOnboarding: skipOnboarding);
}

/// 이미 만든 [env]로 채널 모듈 준비 (시험에서는 메모리 저장소·가짜 기기로).
Future<AppState> openChannelStateWith(AppEnv env, {required String userName, bool skipOnboarding = false}) async {
  if (!_stagesRegistered) {
    registerStages();
    _stagesRegistered = true;
  }
  final state = AppState(env);
  await signInAs(state, userName);
  if (skipOnboarding) state.user?.settings.onboardingDone = true;
  return state;
}

/// 개인비서 로그인 이름과 같은 채널 사용자로 바로 들어간다. 없으면 만든다(비밀번호는 무작위, 쓰지 않음).
Future<void> signInAs(AppState state, String userName) async {
  if (await state.tryAutoLogin() && state.user?.user.name == userName) return;
  final name = userName.trim().isEmpty ? '나' : userName.trim();
  final found = state.env.accounts.list().where((u) => u.name == name);
  final r = Random.secure();
  final u = found.isNotEmpty
      ? found.first
      : state.env.accounts.create(name, List.generate(24, (_) => r.nextInt(36).toRadixString(36)).join());
  await state.login(u);
}

Widget channelApp(AppState state) => ChannelBiseoApp(state: state);


// ======================= 개인비서 연결 =======================
// 아래 함수들은 개인비서 홈(오늘 할 일·통합 검색·음성·제안 받기)이 채널 자료를 읽고 쓰는 곳.
// 열쇠·토큰 같은 비밀 값은 돌려주지도, 기록하지도 않는다.

/// 개인비서의 공용 열쇠 (구글 앱 하나, AI 열쇠 하나, 도구 열쇠).
class ChannelSharedKeys {
  const ChannelSharedKeys({
    this.googleClientId,
    this.googleClientSecret,
    this.aiProvider,
    this.aiKey,
    this.higgsfieldKey,
    this.figmaKey,
  });
  final String? googleClientId;
  final String? googleClientSecret;

  /// 개인비서 이름: claude / openai / gemini
  final String? aiProvider;
  final String? aiKey;
  final String? higgsfieldKey;
  final String? figmaKey;
}

/// 개인비서 AI 제공자 이름 → 채널 모듈 제공자 이름.
String? channelAiProvider(String provider) => switch (provider.trim().toLowerCase()) {
  'claude' || 'anthropic' => 'claude',
  'openai' || 'gpt' || 'chatgpt' => 'openai',
  'gemini' || 'google' => 'gemini',
  _ => null,
};

/// 공용 열쇠를 채널 사용자에게 넣는다. 채널 쪽에 이미 설정된 값은 바꾸지 않는다
/// (설정 화면에서 저장하는 것과 같은 곳에 저장). 넣은 항목 이름(값 아님)을 돌려준다.
Future<List<String>> applySharedKeys(UserContext u, ChannelSharedKeys k) async {
  final done = <String>[];
  final gid = (k.googleClientId ?? '').trim();
  if (gid.isNotEmpty && u.settings.googleClientId.isEmpty) {
    await saveGoogleClient(u, gid, k.googleClientSecret ?? '');
    done.add('google');
  }
  final key = (k.aiKey ?? '').trim();
  final prov = channelAiProvider(k.aiProvider ?? 'claude');
  if (key.isNotEmpty && prov != null && !u.ai.hasKey && u.ai.providers.containsKey(prov)) {
    u.settings.aiProvider = prov;
    await u.ai.setKey(key);
    done.add('ai');
  }
  final tools = u.extensions['tools'];
  final hk = (k.higgsfieldKey ?? '').trim();
  if (hk.isNotEmpty && tools is ToolsService && !await tools.higgsConnected) {
    await tools.connectHiggsfield(hk);
    done.add('higgsfield');
  }
  // 피그마: 채널 모듈은 피그마를 OAuth(앱 번호 + 로그인)로만 연결하므로 열쇠 한 개를 넣을 자리가 없다.
  if (done.isNotEmpty) u.env.logger.info('개인비서 공용 열쇠 적용: ${done.join(', ')}');
  return done;
}

/// 오늘 할 일 한 줄 (개인비서 홈에 보임).
typedef ChannelTodayLine = ({String text, int urgency, String? action});

ProductionService? _production(UserContext u) => u.extensions['production'] as ProductionService?;
CornerService? _corner(UserContext u) => u.extensions['corner'] as CornerService?;

int _count(UserContext u, String sql, [List<Object?> args = const []]) => u.db.select(sql, args).first['n'] as int;

/// 채널 모듈 자료로 만든 오늘 할 일.
Future<List<ChannelTodayLine>> channelToday(UserContext u) async {
  final out = <ChannelTodayLine>[];
  final now = u.env.now();
  final today = dayKey(now);
  final ps = _production(u);
  if (ps != null) {
    final waiting = ps.list(statuses: [ProductionStatus.uploadedPrivate], limit: 500).length;
    if (waiting > 0) out.add((text: '확인 대기 영상 $waiting개', urgency: 70, action: '확인하기'));
    final ready = ps
        .list(statuses: [ProductionStatus.uploadTomorrow], limit: 500)
        .where((e) => e.uploadDay.isEmpty || e.uploadDay.compareTo(today) <= 0)
        .length;
    if (ready > 0) out.add((text: '오늘 게시 예정 $ready개', urgency: 65, action: '올리기 확인'));
  }
  final blogWaiting = _count(u, "SELECT COUNT(*) AS n FROM blog_drafts WHERE status IN ('copyReady','draftOnBlogger')");
  if (blogWaiting > 0) out.add((text: '확인 대기 블로그 글 $blogWaiting개', urgency: 55, action: '확인하기'));
  for (final a in u.youtube.expiringAccounts()) {
    final left = 7 - now.difference(a.connectedAt).inDays;
    out.add((
      text: '구글 연결(${a.label})이 ${left <= 0 ? '오늘' : '$left일 뒤'} 만료돼요',
      urgency: left <= 1 ? 90 : 80,
      action: '다시 연결',
    ));
  }
  for (final a in u.youtube.brokenAccounts()) {
    out.add((text: '구글 연결(${a.label})이 끊어졌어요', urgency: 85, action: '다시 연결'));
  }
  final failed = _count(u, "SELECT COUNT(*) AS n FROM jobs WHERE status = 'failed' AND run_day = ?", [today]);
  if (failed > 0) out.add((text: '자동 작업 $failed개가 실패했어요', urgency: 60, action: '기록 보기'));
  final tools = u.extensions['tools'];
  if (tools is ToolsService) {
    try {
      for (final t in await tools.expiringNotices()) {
        out.add((text: t, urgency: 50, action: null));
      }
    } catch (_) {}
  }
  final limit = u.settings.monthlyCostLimitUsd;
  if (limit > 0 && u.ai.hasKey && u.ai.monthCostUsd >= limit * 0.8) {
    out.add((text: '이번 달 AI 비용이 한도의 80%를 넘었어요', urgency: 60, action: null));
  }
  if (u.youtube.channels().isEmpty) out.add((text: '채널을 먼저 등록해 주세요', urgency: 30, action: '채널 등록'));
  return out;
}

/// 홈 타일 한 줄 상태용 숫자.
({int channels, int reviewWaiting}) channelCounts(UserContext u) =>
    (channels: u.youtube.channels().length, reviewWaiting: _production(u)?.reviewList().length ?? 0);

/// 통합 검색 결과 하나.
typedef ChannelHit = ({String title, String? subtitle, String kind});

/// 영상 제목·블로그 글·제작물·메모·코너 소재에서 찾기. 비밀 값은 없다.
List<ChannelHit> channelSearch(UserContext u, String query, {int perKind = 8}) {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final out = <ChannelHit>[];
  String cut(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > 60 ? '${t.substring(0, 60)}…' : t;
  }

  List<Map<String, dynamic>> rows(String sql) =>
      u.db.select(sql, [q, perKind]).map((r) => Map<String, dynamic>.from(r)).toList();
  const has = 'instr(lower(%s), lower(?1)) > 0';
  String w(String col) => has.replaceAll('%s', col);

  for (final r in rows('SELECT title FROM channels WHERE ${w('title')} ORDER BY title LIMIT ?2')) {
    out.add((title: r['title'] as String, subtitle: '내 채널', kind: '채널'));
  }
  for (final r in rows(
    'SELECT v.title AS title, c.title AS ch FROM videos v LEFT JOIN channels c ON c.channel_id = v.channel_id '
    'WHERE ${w('v.title')} ORDER BY v.published_at DESC LIMIT ?2',
  )) {
    out.add((title: r['title'] as String, subtitle: (r['ch'] as String?) ?? '유튜브 영상', kind: '영상'));
  }
  for (final r in rows('SELECT title, status FROM productions WHERE ${w('title')} ORDER BY id DESC LIMIT ?2')) {
    final st = switch (r['status']) {
      'uploadedPrivate' => '확인 대기',
      'uploadTomorrow' => '게시 예정',
      'doneByUser' => '공개함',
      _ => '만드는 중',
    };
    out.add((title: r['title'] as String, subtitle: '제작 · $st', kind: '제작'));
  }
  for (final r in rows(
    'SELECT p.title AS title, s.title AS site FROM posts p LEFT JOIN blog_sites s ON s.id = p.site_id '
    'WHERE ${w('p.title')} ORDER BY p.published_at DESC LIMIT ?2',
  )) {
    out.add((title: r['title'] as String, subtitle: (r['site'] as String?) ?? '블로그', kind: '블로그 글'));
  }
  for (final r in rows('SELECT title FROM blog_drafts WHERE ${w('title')} ORDER BY id DESC LIMIT ?2')) {
    out.add((title: r['title'] as String, subtitle: '블로그 새 글', kind: '블로그 글'));
  }
  for (final r in rows('SELECT text FROM memos WHERE ${w('text')} ORDER BY id DESC LIMIT ?2')) {
    out.add((title: cut(r['text'] as String), subtitle: '음성 메모', kind: '메모'));
  }
  for (final r in rows('SELECT name FROM corners WHERE ${w('name')} ORDER BY id LIMIT ?2')) {
    out.add((title: r['name'] as String, subtitle: '내 코너', kind: '코너'));
  }
  for (final r in rows(
    'SELECT i.title AS title, i.text AS text, c.name AS corner FROM corner_items i '
    'LEFT JOIN corners c ON c.id = i.corner_id WHERE ${w('i.title')} OR ${w('i.text')} ORDER BY i.id DESC LIMIT ?2',
  )) {
    final t = (r['title'] as String).isNotEmpty ? r['title'] as String : cut(r['text'] as String);
    out.add((title: t, subtitle: '내 코너 소재 · ${r['corner'] ?? ''}', kind: '코너 소재'));
  }
  return out;
}

/// 음성 답.
typedef ChannelVoiceReply = ({String spoken, bool needsConfirm, bool openModule});

/// 채널 모듈의 음성 명령 해석을 그대로 쓴다. 업로드·공개·삭제·수정 실행·되돌리기는
/// 여기서 실행하지 않고, 채널 화면을 열어 사용자가 직접 확인하게 한다. 모르는 말이면 null.
Future<ChannelVoiceReply?> channelVoice(UserContext u, String text) async {
  final cmd = u.voice.parse(text);
  switch (cmd.type) {
    case CommandType.unknown:
      return null;
    case CommandType.publish:
    case CommandType.delete:
      // 원래 앱도 하지 않는 명령: 안내만 한다.
      final r = await u.voice.handle(text);
      return (spoken: r.spoken, needsConfirm: false, openModule: cmd.type == CommandType.publish);
    case CommandType.upload:
    case CommandType.runEdits:
    case CommandType.revertToday:
      // confirmed: false → 실행하지 않고 확인 질문만 돌려준다.
      final r = await u.voice.handle(text);
      return (spoken: '${r.spoken} 채널 화면에서 직접 확인하고 실행해 주세요.', needsConfirm: true, openModule: true);
    default:
      final r = await u.voice.handle(text);
      return (spoken: r.spoken, needsConfirm: false, openModule: false);
  }
}

/// 다른 모듈(물건 비우기·하드 자료)에서 받은 소재.
class _SuggestionSource implements MaterialSource {
  _SuggestionSource(this.name, this.title, this.detail, this.files, {required this.own});
  @override
  final String name;
  final String title;
  final String detail;
  final List<String> files;

  /// 사용자가 직접 찍은 사진(물건 비우기)이면 true. 하드에서 찾은 자료는 저작권 확인을 받는다.
  final bool own;

  @override
  Future<List<MaterialItem>> list() async {
    final out = <MaterialItem>[
      MaterialItem(
        path: '',
        kind: 'text',
        title: title,
        note: detail.trim().isEmpty ? title : detail.trim(),
        copyright: 'own',
        sourceApp: name,
      ),
    ];
    for (final f in files) {
      final kind = kindOf(f);
      if (kind == null || !File(f).existsSync()) continue;
      out.add(
        MaterialItem(
          path: f,
          kind: kind,
          title: p.basenameWithoutExtension(f),
          note: title,
          copyright: own && !looksCopyrighted(f) ? 'own' : 'unknown',
          sourceApp: name,
        ),
      );
    }
    return out;
  }
}

/// 개인비서에서 받은 소재를 담는 코너 이름.
const assistantCornerName = '개인비서에서 받은 소재';

/// 제안을 "내 코너" 소재로 넣는다 (업로드는 하지 않음). 채널이 없어 코너를 만들 수 없으면
/// 음성 메모(제작 소재)로 남긴다. 넣었으면 true.
Future<bool> addSuggestedMaterial(
  UserContext u, {
  required String title,
  String detail = '',
  List<String> files = const [],
  required String fromName,
  bool ownMaterial = false,
}) async {
  final cs = _corner(u);
  final chans = u.youtube.channels();
  if (cs == null || chans.isEmpty) {
    final parts = [title.trim(), detail.trim(), ...files.map(p.basename)].where((e) => e.isNotEmpty);
    if (parts.isEmpty) return false;
    u.memos.add('[$fromName] ${parts.join(' · ')}');
    u.env.logger.info('개인비서 소재를 메모로 저장 ($fromName)');
    return true;
  }
  final corner =
      cs.corners().where((c) => c.name == assistantCornerName).firstOrNull ?? cs.create(assistantCornerName, chans.first.channelId);
  final r = await cs.importFrom(corner.id, _SuggestionSource(fromName, title.trim(), detail, files, own: ownMaterial));
  u.env.logger.info('개인비서 소재 ${r.added}개를 코너에 넣음 ($fromName, 확인 필요 ${r.needCheck}개)');
  return r.added > 0;
}
