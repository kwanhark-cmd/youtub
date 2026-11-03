import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../classify/ai_provider.dart';
import '../classify/classification_service.dart';
import '../core/app_info.dart';
import '../core/app_log.dart';
import '../core/cancel_token.dart';
import '../data/conversation_store.dart';
import '../data/key_store.dart';
import '../models/models.dart';
import '../parsers/import_reader.dart';
import '../parsers/parser_common.dart';
import '../voice/voice_service.dart';
import 'app_identity.dart';
import 'backup_service.dart';
import 'gmail_service.dart';
import 'settings.dart';
import 'update_service.dart';
import 'user_service.dart';
import 'user_session.dart';

/// 화면이 멈추지 않도록 다른 일꾼(Isolate)에서 파일을 읽습니다.
Future<List<ParseResult>> parseInBackground(String name, Uint8List bytes, AiSource? hint) =>
    Isolate.run(() => ImportReader.read(name, bytes, hint: hint));

enum JobKind { importing, classifying }

enum JobState { running, done, failed, cancelled }

/// 백그라운드 작업(가져오기·분류)의 진행 상황.
class Job {
  final JobKind kind;
  final String title;
  JobState state = JobState.running;
  int done = 0;
  int total = 0;
  String? message;
  String? problemHint;
  String? stage; // 실패한 단계: 파일 열기/형식 판별/파싱/저장/AI 호출
  UnreadableKind? unreadable;
  bool emptyFile = false;
  ImportSummary? importSummary;
  ClassifyOutcome? classifyOutcome;
  final CancelToken cancel = CancelToken();

  Job(this.kind, this.title);

  double? get progress => total == 0 ? null : done / total;
}

class AppController extends ChangeNotifier {
  final Directory root;
  final KeyStore keys;
  final VoiceService voice;
  final bool autoUpdateCheck;
  final bool inMemoryDb;
  final Future<Uint8List> Function(String asset) loadAsset;
  late final UserService users;

  List<UserProfile> profiles = [];
  UserSession? session;
  Job? job;
  int revision = 0; // 자료가 바뀌면 올라감(화면 새로고침용)
  String? fatalError;

  /// 로그인 전(사용자 고르기 화면)에 쓰는 설정.
  AppSettings guestSettings = AppSettings();

  AppController({
    required this.root,
    required this.keys,
    required this.voice,
    this.inMemoryDb = false,
    this.autoUpdateCheck = true,
    Future<Uint8List> Function(String asset)? loadAsset,
  }) : loadAsset = loadAsset ?? ((a) async => (await rootBundle.load(a)).buffer.asUint8List()) {
    users = UserService(root);
  }

  AppSettings get settings => session?.settings ?? guestSettings;

  File get _guestFile => File('${root.path}/guest_settings.json');

  Future<void> init() async {
    profiles = users.load();
    guestSettings = AppSettings.load(_guestFile);
    // 사용자가 한 명이고 비밀번호가 없으면 바로 들어감
    if (profiles.length == 1 && profiles.first.pinHash == null) {
      await signIn(profiles.first);
    }
    notifyListeners();
  }

  void touch() {
    revision++;
    notifyListeners();
  }

  // ---------- 사용자 ----------

  Future<UserProfile> createUser(String name, {String emoji = '🙂', String? pin}) async {
    final u = users.create(name, emoji: emoji, pin: pin);
    profiles = users.load();
    await signIn(u, carryGuestSettings: true);
    return u;
  }

  Future<void> signIn(UserProfile u, {bool carryGuestSettings = false}) async {
    session?.close();
    session = null;
    try {
      session = await UserSession.open(u, users.dirOf(u.id), keys, inMemory: inMemoryDb);
      if (carryGuestSettings) {
        final s = session!.settings;
        s.fontSize = guestSettings.fontSize;
        s.theme = guestSettings.theme;
        s.highContrast = guestSettings.highContrast;
        s.reduceMotion = guestSettings.reduceMotion;
        session!.saveSettings();
      }
      // 이미 대화가 있는 사용자(이전 버전에서 쓰던 자료)는 첫 안내를 건너뜀
      final ss = session!;
      if (!ss.settings.onboardingDone && ss.store.count() > 0) {
        ss.settings.onboardingDone = true;
        ss.saveSettings();
      }
      applySampleVisibility();
      apiKeyPresent = await hasApiKey();
      // 하루 한 번 조용히 새 버전 확인(인터넷이 없어도 앱은 그대로)
      applyIdentity();
      if (autoUpdateCheck && settings.gmailConnected) {
        final last = settings.lastGmailCheck;
        if (last == null || DateTime.now().difference(last) > const Duration(hours: 6)) {
          unawaited(checkGmail(silent: true).then((_) => notifyListeners(), onError: (_) {}));
        }
      }
      if (autoUpdateCheck) unawaited(checkForUpdate(silent: true).then((_) => notifyListeners(), onError: (_) {}));
      fatalError = null;
      AppLog.info('사용자 열기', {'dataVersion': ss.database.version});
    } catch (e, st) {
      AppLog.error('사용자 자료 열기 실패', e, st);
      fatalError = '자료를 여는 중 문제가 생겼어요. 설정의 "문제 신고"로 알려 주시거나 백업에서 되살려 주세요.';
    }
    touch();
  }

  void signOut() {
    session?.close();
    session = null;
    job = null;
    touch();
  }

  /// 실제 대화가 들어오면 샘플을 숨김(설정에서 다시 보이게 할 수 있음).
  void applySampleVisibility() {
    final s = session;
    if (s == null) return;
    final hide = !s.settings.showSamples && s.store.realCount() > 0;
    s.store.hideSamples = hide;
    s.topics.hideSamples = hide;
  }

  bool get samplesHidden => session?.store.hideSamples ?? false;

  /// 홈 제목 등에 쓰는 앱 이름(설정에서 바꿀 수 있음).
  String get appName => settings.displayName ?? defaultAppName;

  void updateSettings(void Function(AppSettings s) change) {
    change(settings);
    applySampleVisibility();
    if (session != null) {
      session!.saveSettings();
    } else {
      guestSettings.save(_guestFile);
    }
    notifyListeners();
  }

  // ---------- AI 키 ----------

  Future<bool> hasApiKey() async {
    final s = session;
    if (s == null) return false;
    final k = await keys.read(UserSession.apiKeyName(s.user.id));
    return k != null && k.isNotEmpty;
  }

  /// AI 열쇠가 있는지(화면 상태 표시용, 저장 즉시 바뀜).
  bool apiKeyPresent = false;

  Future<void> setApiKey(String? key) async {
    final s = session;
    if (s == null) return;
    if (key == null || key.trim().isEmpty) {
      await keys.delete(UserSession.apiKeyName(s.user.id));
    } else {
      await keys.write(UserSession.apiKeyName(s.user.id), key.trim());
    }
    apiKeyPresent = await hasApiKey();
    notifyListeners();
  }

  /// 연결 상태 3가지(홈·설정에 따로 표시)
  bool get aiConnected => settings.aiMode == AiMode.claude && apiKeyPresent && settings.shareConsentGiven;
  bool get gmailConnected => settings.gmailConnected;

  /// 테스트에서 가짜 제공자를 넣을 수 있게 둡니다.
  AiProvider Function(String apiKey)? providerFactory;

  Future<AiProvider?> provider() async {
    final s = session;
    if (s == null) return null;
    final k = await keys.read(UserSession.apiKeyName(s.user.id));
    if (k == null || k.isEmpty) return null;
    return (providerFactory ?? (key) => ClaudeProvider(apiKey: key))(k);
  }

  bool get aiReady => settings.aiMode == AiMode.claude && settings.shareConsentGiven;

  // ---------- 가져오기 ----------

  bool get busy => job?.state == JobState.running;

  Future<Job?> importFile(String path) async {
    final f = File(path);
    final name = f.uri.pathSegments.isEmpty ? path : f.uri.pathSegments.last;
    Uint8List bytes;
    try {
      bytes = await f.readAsBytes(); // 읽기만 함
    } catch (e, st) {
      AppLog.error('가져오기 실패(단계: 파일 열기)', e, st);
      final j = Job(JobKind.importing, '$name 가져오기')
        ..state = JobState.failed
        ..stage = '파일 열기'
        ..message = '파일을 열 수 없어요. 다른 곳에 저장된 파일인지 확인해 주세요.';
      job = j;
      notifyListeners();
      return j;
    }
    return importBytes(name, bytes);
  }

  Future<Job?> importSamples() async {
    Job? last;
    final all = <ParseResult>[];
    for (final a in ['claude_sample.json', 'chatgpt_sample.json', 'gemini_sample.html']) {
      all.addAll(ImportReader.read(a, await loadAsset('assets/samples/$a')));
    }
    last = await _runImport('샘플 대화 가져오기', 'samples', () async => all, sample: true);
    return last;
  }

  Future<Job?> importBytes(String name, Uint8List bytes, {AiSource? hint}) =>
      _runImport('$name 가져오기', name, () => parseInBackground(name, bytes, hint));

  Future<Job?> _runImport(String title, String fileName, Future<List<ParseResult>> Function() parse, {bool sample = false}) async {
    final s = session;
    if (s == null || busy) return null;
    final j = Job(JobKind.importing, title);
    job = j;
    j.message = '파일을 읽고 있어요…';
    notifyListeners();
    try {
      List<ParseResult> results;
      try {
        results = await parse();
      } on UnreadableFileException catch (e) {
        j.state = JobState.failed;
        j.stage = '형식 판별';
        j.unreadable = e.kind;
        j.message = switch (e.kind) {
          UnreadableKind.expiredLink => '내려받기 링크가 만료된 것 같아요. 받은 파일이 대화 기록이 아니라 안내 페이지예요. 내보내기를 다시 요청해 주세요.',
          UnreadableKind.empty => '빈 파일이에요. 내려받기가 끝까지 됐는지 확인하고 다시 받아 주세요.',
          UnreadableKind.unknown => '이 파일은 읽을 수 없어요. 어느 AI 파일인지 골라 주세요.',
        };
        j.problemHint = e.hint;
        AppLog.error('가져오기 실패(단계: 형식 판별)', e);
        notifyListeners();
        return j;
      } on RemoteError catch (e) {
        // 백그라운드에서 난 오류
        j.state = JobState.failed;
        j.stage = '파싱';
        j.unreadable = UnreadableKind.unknown;
        j.message = '이 파일은 읽을 수 없어요. 어느 AI 파일인지 골라 주세요.';
        j.problemHint = e.toString().split('\n').first;
        AppLog.error('가져오기 실패(단계: 파싱)', e);
        notifyListeners();
        return j;
      }
      if (results.every((r) => r.conversations.isEmpty)) {
        j.state = JobState.failed;
        j.stage = '파싱';
        j.emptyFile = true;
        j.message = '이 파일에는 가져올 대화가 없어요. 다른 파일이거나 대화가 하나도 없는 계정일 수 있어요.';
        AppLog.error('가져오기 실패(단계: 파싱) 대화 0개', fileName.length);
        notifyListeners();
        return j;
      }
      j.total = results.fold(0, (a, r) => a + r.conversations.length);
      j.message = '대화를 저장하고 있어요…';
      notifyListeners();
      final summary = await s.store.importResults(
        results,
        fileName: fileName,
        sample: sample,
        cancel: j.cancel,
        onProgress: (d, t) {
          j.done = d;
          j.total = t;
          notifyListeners();
        },
      );
      j.importSummary = summary;
      // 새로 들어온 대화는 비용 없는 키워드 분류·요약을 바로 해 둠
      if (summary.touchedIds.isNotEmpty) {
        j.message = '주제별로 나누고 있어요…';
        notifyListeners();
        await s.classifier.classifyOffline(summary.touchedIds, cancel: j.cancel);
      }
      applySampleVisibility();
      if (!sample && summary.saved > 0) settings.gmailFoundCount = 0;
      j.state = summary.cancelled ? JobState.cancelled : JobState.done;
      j.message = summary.cancelled ? '취소했어요. 지금까지 ${summary.saved}개는 저장됐어요.' : '다 가져왔어요!';
    } catch (e, st) {
      AppLog.error('가져오기 실패(단계: 저장)', e, st);
      j.state = JobState.failed;
      j.stage = '저장';
      j.message = '가져오는 중 문제가 생겼어요. 이미 저장된 대화는 그대로 있어요.';
    }
    touch();
    return j;
  }

  void cancelJob() {
    job?.cancel.cancel();
    notifyListeners();
  }

  void clearJob() {
    if (!busy) {
      job = null;
      notifyListeners();
    }
  }

  // ---------- 분류 ----------

  Future<Job?> classify(List<int> ids, {required bool useAi}) async {
    final s = session;
    if (s == null || busy || ids.isEmpty) return null;
    final j = Job(JobKind.classifying, useAi ? 'AI로 주제 정리하기' : '주제 정리하기')..total = ids.length;
    job = j;
    j.message = '대화를 읽고 주제를 정하고 있어요…';
    notifyListeners();
    void progress(int d, int t) {
      j.done = d;
      j.total = t;
      notifyListeners();
    }

    try {
      ClassifyOutcome out;
      if (useAi) {
        final p = await provider();
        if (p == null) {
          j.state = JobState.failed;
          j.message = const AiError(AiErrorKind.noKey).message;
          notifyListeners();
          return j;
        }
        out = await s.classifier.classifyWithAi(
          ids,
          provider: p,
          model: s.settings.aiModel,
          scope: s.settings.shareScope,
          monthlyCapUsd: s.settings.monthlyCapUsd,
          onProgress: progress,
          cancel: j.cancel,
        );
      } else {
        out = await s.classifier.classifyOffline(ids, onProgress: progress, cancel: j.cancel);
      }
      j.classifyOutcome = out;
      if (out.stoppedBy != null) {
        AppLog.error('정리 실패(단계: AI 호출)', out.stoppedBy!);
        j.stage = 'AI 호출';
        j.state = JobState.failed;
        j.message = '${out.stoppedBy!.message}\n(${out.done}개는 정리됐어요)';
      } else if (out.cancelled) {
        j.state = JobState.cancelled;
        j.message = '취소했어요. ${out.done}개는 정리됐어요.';
      } else {
        j.state = JobState.done;
        j.message = '${out.done}개 대화를 정리했어요!';
      }
    } catch (e, st) {
      AppLog.error('분류 실패', e, st);
      j.state = JobState.failed;
      j.message = '정리하는 중 문제가 생겼어요.';
    }
    touch();
    return j;
  }

  List<int> todayImportedIds() {
    final s = session;
    if (s == null) return const [];
    final now = DateTime.now();
    return s.store.importedSince(DateTime(now.year, now.month, now.day)).map((c) => c.id).toList();
  }

  List<int> allIds() {
    final s = session;
    if (s == null) return const [];
    return s.store.db
        .select('SELECT id FROM conversations c WHERE ${s.store.sampleCond()} ORDER BY created_at DESC')
        .map((r) => r['id'] as int)
        .toList();
  }

  // ---------- 지메일 ----------

  /// 테스트에서 가짜 서버·브라우저를 넣을 수 있게 둡니다.
  http.Client? gmailHttpClient;
  Future<void> Function(Uri url)? openBrowser;

  GmailService gmail() {
    final s = session!;
    return GmailService(
      keys: keys,
      userId: s.user.id,
      client: gmailHttpClient,
      openBrowser: openBrowser ?? (u) async => AppLog.warn('브라우저 열기 함수 없음'),
    );
  }

  /// 클라이언트 ID·비밀번호 저장 후 브라우저로 연결.
  Future<void> connectGmail({required String clientId, String? clientSecret}) async {
    final g = gmail();
    if (clientSecret != null && clientSecret.trim().isNotEmpty) await g.saveSecret(clientSecret.trim());
    updateSettings((s) => s.gmailClientId = clientId.trim());
    await g.connect(clientId: clientId.trim());
    updateSettings((s) => s.gmailConnected = true);
    await checkGmail();
  }

  /// 내보내기 안내 메일 확인 → 마지막으로 대화를 넣은 뒤 온 메일 수를 "오늘 할 일"에 표시.
  Future<List<ExportMail>> checkGmail({bool silent = false}) async {
    final s = session;
    if (s == null || !settings.gmailConnected || settings.gmailClientId == null) return const [];
    try {
      final mails = await gmail().recentExportMails(settings.gmailClientId!);
      final lastImport = s.store.lastImportAt();
      final fresh = mails.where((m) => lastImport == null || m.receivedAt.isAfter(lastImport)).length;
      updateSettings((x) {
        x.lastGmailCheck = DateTime.now();
        x.gmailFoundCount = fresh;
      });
      return mails;
    } on GmailError catch (e) {
      AppLog.error('지메일 확인 실패(단계: 지메일 확인)', e);
      if (e.kind == GmailErrorKind.expired) updateSettings((x) => x.gmailConnected = false);
      if (!silent) rethrow;
      return const [];
    }
  }

  Future<void> disconnectGmail() async {
    if (session == null) return;
    await gmail().disconnect();
    updateSettings((s) {
      s.gmailConnected = false;
      s.gmailFoundCount = 0;
    });
  }

  // ---------- 앱 꾸미기 ----------

  void applyIdentity() {
    AppIdentity.applyName(appName);
  }

  // ---------- 업데이트 ----------

  /// 테스트에서 가짜 서버를 넣을 수 있게 둡니다.
  UpdateService Function()? updateServiceFactory;
  UpdateService get updates => (updateServiceFactory ?? () => UpdateService())();
  UpdateInfo? availableUpdate;

  bool get hasUpdateBadge {
    final v = settings.latestVersion;
    return v != null && compareVersions(v, AppInfo.version) > 0;
  }

  /// [silent]: 앱 시작 때 하루 한 번 조용히 확인(오류는 기록만).
  Future<UpdateInfo?> checkForUpdate({bool silent = false}) async {
    if (silent) {
      final last = settings.lastUpdateCheck;
      if (last != null && DateTime.now().difference(last) < const Duration(hours: 24)) return null;
    }
    try {
      final info = await updates.check();
      availableUpdate = info;
      updateSettings((s) {
        s.lastUpdateCheck = DateTime.now();
        s.latestVersion = info?.version;
      });
      return info;
    } on UpdateError catch (e) {
      AppLog.warn('업데이트 확인 안 됨', {'stage': '업데이트 확인', 'kind': e.kind.name});
      if (silent) return null;
      rethrow;
    }
  }

  /// 설치 전 자동 백업: 자료 파일과 설정을 사용자 폴더의 backups에 복사(최근 5개 보관).
  Future<Directory?> backupBeforeUpdate(String toVersion) async {
    final s = session;
    if (s == null || s.database.path == null) return null;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dir = Directory('${s.dir.path}/backups/before-update-v${AppInfo.version}-to-v$toVersion-$stamp')..createSync(recursive: true);
    s.database.db.execute("VACUUM INTO '${dir.path}/data.db'");
    if (s.settingsFile.existsSync()) s.settingsFile.copySync('${dir.path}/settings.json');
    final all = Directory('${s.dir.path}/backups').listSync().whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path));
    while (all.length > 5) {
      all.removeAt(0).deleteSync(recursive: true);
    }
    AppLog.info('업데이트 전 백업 완료', {'to': toVersion});
    return dir;
  }

  // ---------- 백업·초기화 ----------

  Future<Uint8List> makeBackup(String password) async {
    final s = session!;
    return BackupService.create(s.store, password, settings: s.settings.toJson());
  }

  Future<void> restoreBackup(Uint8List data, String password) async {
    final s = session!;
    final settingsJson = await BackupService.restore(s.store, data, password);
    if (settingsJson != null) {
      s.settings = AppSettings.fromJson(settingsJson)..onboardingDone = true;
      s.saveSettings();
    }
    touch();
  }

  /// 이 사용자의 앱 자료를 모두 지움(사용자가 넣었던 원본 파일은 건드리지 않음).
  Future<void> resetCurrentUser() async {
    final s = session;
    if (s == null) return;
    final u = s.user;
    s.close();
    session = null;
    await keys.delete(UserSession.dataKeyName(u.id));
    await keys.delete(UserSession.apiKeyName(u.id));
    users.remove(u.id);
    profiles = users.load();
    AppLog.info('사용자 자료 초기화');
    touch();
  }
}
