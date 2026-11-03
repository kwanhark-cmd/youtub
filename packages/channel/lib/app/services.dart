import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/db.dart';
import '../core/http_json.dart';
import '../core/logger.dart';
import '../core/oauth.dart';
import '../core/secret_store.dart';
import '../features/accounts/local_accounts.dart';
import '../features/ai/ai_service.dart';
import '../features/ai/brain.dart';
import '../features/edits/edit_service.dart';
import '../features/runner/job_runner.dart';
import '../features/runner/notifier.dart';
import '../features/settings/app_look.dart';
import '../features/settings/maintenance.dart';
import '../features/settings/user_settings.dart';
import '../features/update/update_service.dart';
import '../features/voice/briefing.dart';
import '../features/voice/memos.dart';
import '../features/voice/voice_controller.dart';
import '../features/voice/voice_io.dart';
import '../features/youtube/mock_youtube_api.dart';
import '../features/youtube/quota.dart';
import '../features/youtube/youtube_api.dart';
import '../features/youtube/youtube_service.dart';

/// 기기마다 다른 것들 (실제 앱 / 테스트에서 바꿔 끼운다).
class AppEnv {
  AppEnv({
    required this.baseDir,
    required this.documentsDir,
    required this.secrets,
    required this.httpClient,
    required this.logger,
    required this.speech,
    required this.speaker,
    required this.notifier,
    required this.isDesktop,
    required this.platformName,
    required this.appVersion,
    required this.launchUrl,
    this.now = DateTime.now,
    this.inMemoryDb = false,
    this.mockYouTube,
    this.aiProviders,
    this.pickFile,
    this.pickDirectory,
    this.installUpdate,
    this.osName = '',
    this.setLauncherIcon,
    this.pinShortcut,
  });

  /// 안드로이드 홈 화면 아이콘 바꾸기 / 바로가기 만들기 (다른 운영체제는 null)
  final Future<void> Function(String iconId)? setLauncherIcon;
  final Future<bool> Function(String label, Uint8List png)? pinShortcut;

  /// 내려받은 업데이트 설치 시작 (실제 앱만). 테스트에서는 가짜.
  final Future<void> Function(File installer)? installUpdate;

  /// 'android' | 'windows' | 'macos' | 'linux' (업데이트 파일 고르기)
  final String osName;

  late final UpdateService updates = UpdateService(client: httpClient, currentVersion: appVersion, logger: logger);

  /// 파일 고르기 (확장자 목록). 고르지 않으면 null.
  final Future<String?> Function(List<String> extensions)? pickFile;

  /// 폴더 고르기. 고르지 않으면 null.
  final Future<String?> Function()? pickDirectory;

  final String baseDir;
  final String documentsDir;
  final SecretStore secrets;
  final http.Client httpClient;
  final AppLogger logger;
  final SpeechInput speech;
  final Speaker speaker;
  final Notifier notifier;
  final bool isDesktop;
  final String platformName;
  final String appVersion;
  final UrlLauncher launchUrl;
  final DateTime Function() now;
  final bool inMemoryDb;

  /// 테스트에서 가짜 유튜브를 넣어 상태를 확인할 때.
  final MockYouTubeApi? mockYouTube;
  final Map<String, AiProvider>? aiProviders;

  late final JsonHttp jsonHttp = JsonHttp(httpClient, logger: logger);
  late final LocalAccounts accounts = LocalAccounts(
    baseDir: baseDir,
    secrets: secrets,
    logger: logger,
    inMemory: inMemoryDb,
  );
}

/// 로그인한 사용자 한 명의 모든 기능 묶음. 로그아웃하면 통째로 버린다.
class UserContext {
  UserContext._(this.env, this.user, this.db);

  final AppEnv env;
  final LocalUser user;
  final AppDatabase db;

  late final UserSettings settings;
  late final UserSecrets secrets;
  late final OAuthFlow oauth;
  late final TokenManager tokens;
  late final QuotaTracker quota;
  late final MockYouTubeApi mockYouTube;
  late final YouTubeService youtube;
  late final AiService ai;
  late final Brain brain;
  late final EditLog editLog;
  late final EditService edits;
  late final MemoService memos;
  late final BriefingService briefing;
  late final VoiceController voice;
  late final JobQueue jobs;
  late final JobRunner runner;
  late final Maintenance maintenance;
  late final AppLook look;

  /// 다른 단계(2~4단계)가 기능을 붙이는 곳.
  final Map<String, Object> extensions = {};

  /// 마지막 업데이트 전 백업 폴더 (이번 실행 중)
  String? lastUpdateBackup;

  /// 이 사용자가 쓴 앱 버전 기록. 업데이트 뒤 처음 열 때 한 줄 추가.
  void _recordVersion() {
    final v = env.appVersion;
    final seen = db.select('SELECT 1 FROM app_versions WHERE version = ?', [v]).isNotEmpty;
    if (seen) return;
    final prev = db.select('SELECT version FROM app_versions ORDER BY first_seen DESC LIMIT 1');
    db.execute('INSERT INTO app_versions(version, first_seen) VALUES(?, ?)', [v, env.now().toIso8601String()]);
    if (prev.isNotEmpty) env.logger.info('업데이트됨: ${prev.first['version']} → $v (설정·자료 유지)');
    // 예전 버전에서 쓰던 사람은 첫 실행 안내를 다시 보지 않게 (설정이 이미 있으면 건너뜀)
    if (!settings.onboardingDone && hasExistingData) settings.onboardingDone = true;
  }

  /// 이미 쓰던 자료가 있는지 (계정·채널·제작·메모 중 하나라도)
  bool get hasExistingData =>
      db
              .select(
                'SELECT (SELECT COUNT(*) FROM accounts) + (SELECT COUNT(*) FROM productions) + (SELECT COUNT(*) FROM memos) AS n',
              )
              .first['n']
          as int >
      0;

  static Future<UserContext> open(AppEnv env, LocalUser user) async {
    final db = env.accounts.openUserDb(user.id);
    final c = UserContext._(env, user, db);
    await c._wire();
    return c;
  }

  Future<void> _wire() async {
    final now = env.now;
    settings = UserSettings(db)..ensureFirstUseDay(now());
    _recordVersion();
    secrets = UserSecrets(env.secrets, user.id);
    oauth = OAuthFlow(env.jsonHttp, env.launchUrl, now: now);
    tokens = TokenManager(secrets, oauth, now: now);
    quota = QuotaTracker(db, limit: () => settings.quotaDailyLimit, now: now);
    mockYouTube = env.mockYouTube ?? MockYouTubeApi();
    youtube = YouTubeService(
      db: db,
      settings: settings,
      secrets: secrets,
      realApi: RealYouTubeApi(env.jsonHttp, env.httpClient),
      mockApi: mockYouTube,
      tokens: tokens,
      oauth: oauth,
      quota: quota,
      now: now,
      logger: env.logger,
    );
    ai = AiService(
      db: db,
      settings: settings,
      secrets: secrets,
      providers: env.aiProviders ?? {'claude': ClaudeProvider(env.jsonHttp)},
      now: now,
      logger: env.logger,
    );
    await ai.loadKey();
    brain = Brain(ai, logger: env.logger);
    editLog = EditLog(db, now);
    edits = EditService(log: editLog, youtube: youtube, brain: brain, settings: settings, now: now, logger: env.logger);
    memos = MemoService(db, now);
    briefing = BriefingService(youtube: youtube, edits: edits, ai: ai, quota: quota, settings: settings, now: now);
    voice = VoiceController(youtube: youtube, edits: edits, briefing: briefing, memos: memos, now: now);
    jobs = JobQueue(db, now);
    runner = JobRunner(
      settings: settings,
      queue: jobs,
      youtube: youtube,
      edits: edits,
      ai: ai,
      notifier: env.notifier,
      now: now,
      isDesktop: env.isDesktop,
      logger: env.logger,
      appName: () => look.displayName,
    );
    look = AppLook(
      settings: settings,
      userDir: env.accounts.userDir(user.id),
      logger: env.logger,
      setLauncherIcon: env.setLauncherIcon,
      pinShortcut: env.pinShortcut,
    );
    maintenance = Maintenance(
      db: db,
      logger: env.logger,
      appVersion: env.appVersion,
      platform: env.platformName,
      now: now,
    );
  }

  /// 연습 모드 표시 여부 (유튜브 또는 AI 중 하나라도 실제 연결이 아니면).
  bool get isPracticeMode => youtube.isPracticeMode || ai.isPracticeMode;

  /// 구글 연결 상태 (실제 계정이 정상 연결됨)
  bool get googleConnected => youtube.googleConnected;

  /// 인공지능 연결 상태 (열쇠가 있고 이번 달 한도 안)
  bool get aiConnected => ai.hasKey && !ai.overLimit;

  void close() => db.close();
}
