import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../core/clock.dart';
import '../core/format.dart';
import '../core/logger.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/settings.dart';
import '../services/ai/ai_service.dart';
import '../services/backup_service.dart';
import '../services/export_service.dart';
import '../services/image_service.dart';
import '../services/notification_service.dart';
import '../services/paths.dart';
import '../services/gmail_service.dart';
import '../services/secret_store.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';
import '../services/sale_service.dart';
import '../services/timelapse_service.dart';
import '../services/video_service.dart';
import '../services/voice_service.dart';

/// 앱 버전 (pubspec.yaml의 version과 같아야 함 — 테스트로 확인)
const appVersion = '1.1.0';

/// 화면 전체가 함께 쓰는 상태
class AppState extends ChangeNotifier {
  final Repository repo;
  final AppPaths paths;
  final Clock clock;
  final VoiceIO voice;
  final Notifier notifier;
  late final AiService ai;
  late final SaleService sales;
  late final ImageService images;
  late final VideoService video;
  late final ExportService exports;
  late final BackupService backup;
  late final TimelapseService timelapse;
  late final SecretStore secrets;
  late final UpdateService updates;
  late final GmailService gmail;
  late final StorageService storage;

  /// 오류 창 등에서 보여 줄 마지막 시작 정보 (자료 변환 전 자동 백업 파일 등)
  File? preUpgradeBackup;

  GlobalSettings global = GlobalSettings();
  UserSettings user = UserSettings();
  AppUser? currentUser;
  List<AppUser> users = [];
  List<Item> items = [];
  ProgressStats? stats;
  List<Notice> unread = [];
  Item? today;
  SaleCheckResult? lastCheck;

  final http.Client _http;

  AppState._(this.repo, this.paths, this.clock, this.voice, this.notifier, http.Client? httpClient, FrameExtractor? extractor, SecretStore? secretStore)
    : _http = httpClient ?? http.Client() {
    secrets = secretStore ?? DeviceSecretStore(repo);
    updates = UpdateService(client: _http, paths: paths, currentVersion: appVersion);
    gmail = GmailService(_http);
    storage = StorageService(paths, repo);
    ai = AiService(repo, clock, httpClient: httpClient);
    sales = SaleService(repo, clock);
    images = ImageService(paths);
    video = VideoService(paths, extractor: extractor);
    exports = ExportService(paths);
    backup = BackupService(repo, paths);
    timelapse = TimelapseService(paths);
  }

  static Future<AppState> open({
    required DatabaseFactory dbFactory,
    required Directory root,
    String? dbPath,
    Clock clock = const SystemClock(),
    VoiceIO? voice,
    Notifier? notifier,
    http.Client? httpClient,
    FrameExtractor? extractor,
    SecretStore? secretStore,
  }) async {
    final paths = AppPaths(root);
    final path = dbPath ?? paths.dbPath;
    await log.attachFile(File(p.join(paths.logs.path, 'app.log')));
    // 자료 변환이 필요하면 먼저 자동 백업(사진 포함)
    File? pre;
    final oldVersion = path.startsWith('file:') ? null : await peekVersion(dbFactory, path);
    if (oldVersion != null && oldVersion > 0 && oldVersion < dataVersion) {
      final raw = await dbFactory.openDatabase(path, options: OpenDatabaseOptions(singleInstance: false));
      try {
        pre = await BackupService(Repository(raw), paths).createSafetyBackup('자료변환_v$oldVersion', appVersion: appVersion);
        log.info('자료 변환 전 자동 백업: v$oldVersion → v$dataVersion');
      } catch (e, st) {
        log.error('자료 변환 전 자동 백업 실패', e, st);
      } finally {
        await raw.close();
      }
    }
    final db = await openAppDatabase(dbFactory, path);
    final s = AppState._(Repository(db), paths, clock, voice ?? SilentVoice(), notifier ?? SilentNotifier(), httpClient, extractor, secretStore);
    s.preUpgradeBackup = pre;
    await s.startup();
    return s;
  }

  int get uid => currentUser!.id;

  /// 날짜 계산용 "지금". 기기 시간이 뒤로 가도 앱이 본 가장 늦은 시각보다 앞서지 않음.
  DateTime get now {
    final n = clock.now();
    final l = global.latestSeen;
    return (l != null && l.isAfter(n)) ? l : n;
  }

  Future<void> startup() async {
    global = await GlobalSettings.load(repo);
    users = await repo.users();
    if (users.isEmpty) {
      final u = await repo.createUser('나', clock.now());
      users = [u];
    }
    currentUser = users.firstWhere((u) => u.id == global.currentUserId, orElse: () => users.first);
    global.currentUserId = currentUser!.id;
    user = await UserSettings.load(repo, uid, secrets);
    // 이미 쓰던 자료가 있으면 첫 실행 마법사는 건너뜀 (업데이트 후 다시 묻지 않기)
    if (!global.onboarded && (await repo.items(uid, includePractice: true)).isNotEmpty) {
      global.onboarded = true;
    }
    await voice.init();
    await notifier.init();
    await runDailyChecks();
  }

  Future<void> runDailyChecks() async {
    final n = clock.now();
    if (global.latestSeen == null || n.isAfter(global.latestSeen!)) global.latestSeen = n;
    await global.save(repo);
    lastCheck = await sales.dailyCheck(uid, user, now);
    await _dailyNotice();
    if (user.dailyOn) {
      await notifier.scheduleDaily(user.dailyHour, global.appName, '오늘은 물건 하나만 정해 보세요. 지금 쓰는 것·판매·폐기 중 하나로 정해요.');
    }
    await refresh();
  }

  /// 하루 한 번 비우기 알림을 앱 안에도 기록 (절전으로 놓쳐도 앱을 열면 보임)
  Future<void> _dailyNotice() async {
    final n = now;
    if (!user.dailyOn || n.hour < user.dailyHour) return;
    final dayStart = DateTime(n.year, n.month, n.day);
    if (await repo.hasNoticeSince(uid, 'daily', dayStart)) return;
    final pick = await _pickToday();
    if (pick == null) return;
    await repo.addNotice(
      Notice(userId: uid, kind: 'daily', title: '오늘은 이 물건 하나만 정해 보세요', body: '"${pick.name}" — 지금 쓰는 것, 판매, 폐기 중 하나를 골라 주세요.', itemId: pick.id, createdAt: n),
    );
  }

  /// 오늘 정할 물건 하나: 하루 동안 같은 물건, 정하면 다음 물건
  Future<Item?> _pickToday() async {
    final undecided = await repo.items(uid, undecidedOnly: true);
    if (undecided.isEmpty) return null;
    final key = '${now.year}-${now.month}-${now.day}';
    final savedDay = await repo.getSetting(uid, 'todayDay');
    final savedId = int.tryParse(await repo.getSetting(uid, 'todayItem') ?? '');
    if (savedDay == key && savedId != null) {
      final it = undecided.where((i) => i.id == savedId);
      if (it.isNotEmpty) return it.first;
    }
    undecided.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final pick = undecided.first;
    await repo.setSetting(uid, 'todayDay', key);
    await repo.setSetting(uid, 'todayItem', '${pick.id}');
    return pick;
  }

  Future<void> refresh() async {
    items = await repo.items(uid);
    stats = await repo.stats(uid);
    unread = await repo.notices(uid, unreadOnly: true);
    today = await _pickToday();
    notifyListeners();
  }

  // ---------- 설정 ----------
  Future<void> saveGlobal() async {
    await global.save(repo);
    notifyListeners();
  }

  Future<void> saveUser() async {
    await user.save(repo, uid, secrets);
    if (user.dailyOn) {
      await notifier.scheduleDaily(user.dailyHour, global.appName, '오늘은 물건 하나만 정해 보세요.');
    } else {
      await notifier.cancelDaily();
    }
    notifyListeners();
  }

  // ---------- 업데이트 ----------
  UpdateInfo? update;

  /// 앱 시작 시 하루 한 번 조용히 확인 (실패해도 아무 말 안 함)
  Future<void> quietUpdateCheck() async {
    final key = '${clock.now().year}-${clock.now().month}-${clock.now().day}';
    if (global.lastUpdateCheck == key) return;
    try {
      update = await updates.check();
      global.lastUpdateCheck = key;
      global.latestVersion = update?.version;
      global.latestNotes = update?.notes ?? '';
      await global.save(repo);
      notifyListeners();
    } catch (e) {
      log.info('조용한 업데이트 확인 실패: $e');
    }
  }

  /// 설정의 "업데이트 확인" 버튼
  Future<UpdateInfo?> checkUpdateNow() async {
    update = await updates.check();
    global.lastUpdateCheck = '${clock.now().year}-${clock.now().month}-${clock.now().day}';
    global.latestVersion = update?.version;
    global.latestNotes = update?.notes ?? '';
    await global.save(repo);
    notifyListeners();
    return update;
  }

  bool get hasUpdate => global.latestVersion != null && compareVersions(global.latestVersion!, appVersion) > 0;

  // ---------- 사용자 ----------
  Future<void> switchUser(int id) async {
    currentUser = users.firstWhere((u) => u.id == id);
    global.currentUserId = id;
    await global.save(repo);
    user = await UserSettings.load(repo, id, secrets);
    await runDailyChecks();
  }

  Future<void> addUser(String name) async {
    final u = await repo.createUser(name.trim().isEmpty ? '새 사용자' : name.trim(), clock.now());
    users = await repo.users();
    await switchUser(u.id);
  }

  Future<void> removeUser(int id) async {
    if (users.length <= 1) return;
    await repo.deleteUser(id);
    users = await repo.users();
    if (currentUser?.id == id) await switchUser(users.first.id);
    notifyListeners();
  }

  // ---------- 물건 ----------
  Future<SavedPhoto> savePhoto(Uint8List bytes, {String? ext}) => images.save(bytes, keepOriginal: user.keepOriginals, originalExt: ext);

  Future<Item> addItem({
    required String name,
    String kind = '',
    String condition = '',
    String room = '',
    String spot = '',
    String description = '',
    String source = 'photo',
    SavedPhoto? photo,
    Decision? suggestion,
    String reason = '',
    Decision? decision,
    bool isPractice = false,
  }) async {
    final item = Item(
      isPractice: isPractice,
      userId: uid,
      name: name.trim().isEmpty ? '이름 없는 물건' : name.trim(),
      kind: kind,
      condition: condition,
      room: room,
      spot: spot,
      description: description,
      source: source,
      photoPath: photo?.photoPath,
      thumbPath: photo?.thumbPath,
      originalPath: photo?.originalPath,
      aiSuggestion: suggestion,
      aiReason: reason,
      createdAt: now,
      decision: decision,
      decidedAt: decision == null ? null : now,
    );
    await repo.insertItem(item);
    await refresh();
    return item;
  }

  Future<void> saveItem(Item item) async {
    await repo.updateItem(item);
    await refresh();
  }

  Future<void> deleteItem(Item item) async {
    await repo.deleteItem(uid, item.id!);
    for (final path in [item.photoPath, item.thumbPath, item.originalPath]) {
      if (path == null) continue;
      try {
        final f = File(paths.abs(path));
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await refresh();
  }

  /// 분류 확정. 되돌리기를 위해 이전 상태를 돌려줍니다.
  Future<Item> decide(Item item, Decision d) async {
    final before = item.copy();
    item.decision = d;
    item.decidedAt = now;
    if (d == Decision.sell) {
      item.saleStatus ??= SaleStatus.listing;
      item.listedAt ??= now;
    } else {
      item.saleStatus = null;
    }
    await repo.updateItem(item);
    await refresh();
    return before;
  }

  Future<void> restore(Item before) async {
    await repo.updateItem(before);
    await refresh();
  }

  Future<void> markDiscardDone(Item item, {bool done = true}) async {
    item.discardDoneAt = done ? now : null;
    await repo.updateItem(item);
    await refresh();
  }

  Future<Directory> keepDigitallyAndDiscard(Item item) async {
    final dir = await exports.exportDigitalKeep(item, now);
    item.digitalKeep = true;
    item.exportedAt = now;
    item.decision = Decision.discard;
    item.decidedAt ??= now;
    await repo.updateItem(item);
    await refresh();
    return dir;
  }

  Future<Directory> saveStory(Item item, String story) async {
    item.story = story;
    await repo.updateItem(item);
    final dir = await exports.exportStory(item, now);
    item.exportedAt = now;
    await repo.updateItem(item);
    await refresh();
    return dir;
  }

  // ---------- 알림 ----------
  Future<List<Notice>> allNotices() => repo.notices(uid);

  Future<void> readAllNotices() async {
    await repo.markAllRead(uid, clock.now());
    await refresh();
  }

  // ---------- 비용 ----------
  Future<double> monthCost() => ai.monthCost(uid);
  Future<double> totalCost() => repo.costTotal(uid);

  // ---------- 읽어주기 ----------
  Future<void> say(String text) async {
    if (!user.ttsOn) return;
    await voice.speak(text, rate: user.ttsRate);
  }

  String todaySpeech() {
    final t = today;
    if (t == null) return '오늘 정할 물건이 없어요. 새 물건을 찍어 보세요.';
    return '오늘은 ${t.name} 하나만 정해 보세요. 지금 쓰는 것, 판매, 폐기 중 하나를 고르면 돼요.';
  }

  String progressSpeech() {
    final s = stats;
    if (s == null || s.total == 0) return '아직 등록한 물건이 없어요.';
    return '전체 물건은 ${s.total}개예요. 판매 완료 ${s.sold}개, 폐기 완료 ${s.discarded}개, '
        '아직 정하지 않은 물건은 ${s.undecided}개예요. 판매 수입은 모두 ${won(s.income)}이에요.';
  }

  // ---------- 초기화 ----------
  Future<void> resetAll() async {
    await repo.wipeAll();
    for (final d in ['사진', '썸네일', '원본', '영상장면', '타임랩스사진']) {
      final dir = Directory(p.join(paths.root.path, d));
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    global = GlobalSettings();
    await startup();
  }

  Future<void> reloadAfterRestore() async => startup();
}
