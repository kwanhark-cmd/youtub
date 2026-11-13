import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/clock.dart';
import '../core/crypto/vault_crypto.dart';
import '../core/log/app_logger.dart';
import '../core/vault/vault.dart';
import '../data/migrations.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../logic/alerts.dart';
import 'services.dart';

/// 앱 전체 상태. 금고가 잠기면 데이터 참조를 모두 버린다.
class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController(
    this.services, {
    Clock? clock,
    KdfParams kdf = KdfParams.standard,
    this.clipboardSeconds = 30,
  }) : clock = clock ?? const SystemClock(),
       profiles = ProfileRepository(
         Directory(p.join(services.dataDir.path, 'store')),
         kdf: kdf,
         clock: clock,
       );

  final AppServices services;
  final Clock clock;

  /// 개인비서(통합 앱) 안에서 열렸으면 true. 이 모듈의 단독 앱 업데이트 카드를 숨긴다:
  /// 단독 앱 저장소를 보고 다른 앱을 설치하게 되므로. 업데이트는 개인비서 설정에서 한다.
  bool hostedByAssistant = false;
  final ProfileRepository profiles;
  late final BackupService backups = BackupService(profiles);

  DeviceSettings settings = DeviceSettings();
  List<ProfileInfo> profileList = [];
  bool ready = false;

  VaultSession? _session;
  VaultData? _data;
  ProfileInfo? currentProfile;

  // ───────── 화면·위치 기억(메모리에만, 비밀 정보 없음) ─────────
  /// 앱 전체에서 하나뿐인 화면 길잡이. 사라진 화면 대신 이것으로 대화상자를 띄운다.
  final navigatorKey = GlobalKey<NavigatorState>();
  final navObserver = NavStackObserver();
  final _routeIds = Expando<String>('restoreId');

  /// 화면 이름 → 목록 스크롤 위치.
  final scrollOffsets = <String, double>{};
  List<String> _resume = [];
  String? _resumeProfile;

  void registerRoute(Route<dynamic> r, String id) => _routeIds[r] = id;

  /// 잠긴 뒤 다시 열었을 때 열어 줄 화면들(같은 사용자일 때만).
  List<String> takeResume() {
    final out = _resumeProfile == currentProfile?.id ? _resume : <String>[];
    _resume = [];
    return out;
  }

  /// 잠금이 일어날 때 화면을 첫 화면으로 되돌리기 위한 신호.
  final lockEvents = StreamController<void>.broadcast();

  File get _settingsFile =>
      File(p.join(services.dataDir.path, 'settings.json'));

  /// 첫 실행 마법사(또는 사용자 추가) 진행 중이면 true — 금고가 열려도 마법사를 끝까지 보여 준다.
  bool onboarding = false;

  void beginOnboarding() {
    onboarding = true;
    notifyListeners();
  }

  void refresh() => notifyListeners();

  void endOnboarding() {
    onboarding = false;
    notifyListeners();
  }

  bool get isUnlocked => _session?.isOpen ?? false;
  VaultSession? get session => _session;
  bool get mustResetPassword => _session?.mustResetPassword ?? false;

  VaultData get data {
    final d = _data;
    if (d == null) throw StateError('잠긴 상태');
    return d;
  }

  DateTime now() => clock.now();

  Future<void> init() async {
    settings = await DeviceSettings.load(_settingsFile);
    profileList = await profiles.list();
    await log.attachFile(File(p.join(services.dataDir.path, 'app.log')));
    log.info('앱 시작 (사용자 ${profileList.length}명)');
    await services.notifications.init();
    await services.secureScreen.setSecure(
      !const bool.fromEnvironment('ALLOW_SCREENSHOT'),
    );
    ready = true;
    notifyListeners();
  }

  // ───────── 설정 ─────────
  Future<void> updateSettings(void Function(DeviceSettings s) f) async {
    f(settings);
    await settings.save(_settingsFile);
    _restartAutoLock();
    notifyListeners();
  }

  bool tipSeen(String id) => settings.tipsShown.contains(id);
  Future<void> markTip(String id) =>
      updateSettings((s) => s.tipsShown = {...s.tipsShown, id});

  // ───────── 사용자·잠금 ─────────
  ProfileInfo? get defaultProfile {
    if (profileList.isEmpty) return null;
    return profileList.firstWhere(
      (e) => e.id == settings.lastProfileId,
      orElse: () => profileList.first,
    );
  }

  /// 새 사용자(금고) 만들기. 복구 코드를 돌려준다(화면에 한 번만 보여 줌).
  Future<String> createProfile(String name, String masterPassword) async {
    final (session, code, info) = await profiles.createProfile(
      name,
      masterPassword,
    );
    profileList = await profiles.list();
    await _open(session, info);
    log.info('새 금고 만듦');
    return code;
  }

  Future<UnlockResult> unlockWithPassword(ProfileInfo info, String pw) async {
    final r = await profiles.storeFor(info.id).unlockWithPassword(pw);
    await _afterUnlock(r, info, 'password');
    return r;
  }

  Future<UnlockResult> unlockWithRecovery(ProfileInfo info, String code) async {
    final r = await profiles.storeFor(info.id).unlockWithRecoveryCode(code);
    await _afterUnlock(r, info, 'recovery');
    return r;
  }

  Future<UnlockResult> unlockWithBiometric(ProfileInfo info) async {
    final r = await profiles
        .storeFor(info.id)
        .unlockWithDevice(services.keyStore, services.biometric);
    await _afterUnlock(r, info, 'biometric');
    return r;
  }

  Future<bool> hasBiometric(ProfileInfo info) async {
    try {
      final h = await profiles.storeFor(info.id).readHeader();
      return h.wrappedByDevice != null &&
          await services.biometric.isAvailable();
    } catch (_) {
      return false;
    }
  }

  Future<Duration> lockoutRemaining(ProfileInfo info) async {
    try {
      return await profiles.storeFor(info.id).lockoutRemaining();
    } catch (_) {
      return Duration.zero;
    }
  }

  Future<void> _afterUnlock(
    UnlockResult r,
    ProfileInfo info,
    String how,
  ) async {
    switch (r) {
      case UnlockSuccess(:final session):
        await _open(session, info);
        log.info('금고 열림($how)');
      case UnlockWrongSecret(:final failedAttempts):
        log.warn('잠금 해제 실패 $failedAttempts회($how)');
      case UnlockLockedOut():
        log.warn('잠금 해제 대기 중');
      case UnlockUnavailable():
        log.info('생체 인증 사용 불가 → 비밀번호로');
      case UnlockCorrupted():
        log.warn('금고 파일 손상 감지');
    }
  }

  Future<void> _open(VaultSession s, ProfileInfo info) async {
    if (_resumeProfile != null && _resumeProfile != info.id) {
      _resume = [];
      scrollOffsets.clear();
    }
    final VaultData d;
    try {
      d = loadVaultData(s.data);
    } on FutureDataVersionException {
      s.lock();
      throw const VaultCryptoException('더 새로운 앱 버전에서 저장한 데이터예요. 앱을 업데이트해 주세요.');
    }
    _session = s;
    _data = d;
    currentProfile = info;
    settings.lastProfileId = info.id;
    await settings.save(_settingsFile);
    // 구 버전 데이터였으면 변환한 결과를 바로 저장
    if ((s.data['schemaVersion'] as num?)?.toInt() != VaultData.schemaVersion) {
      await s.save(d.toJson());
    }
    _restartAutoLock();
    unawaited(_reschedule());
    notifyListeners();
  }

  /// 잠그기: 키·데이터 참조를 버리고, 복사해 둔 비밀번호도 지운다.
  Future<void> lock({String reason = 'manual'}) async {
    if (_session == null) return;
    _autoLockTimer?.cancel();
    // 보던 화면 순서를 기억(초기화·복원으로 잠근 경우는 기억하지 않음).
    if (reason == 'reset' || reason == 'restore') {
      _resume = [];
      scrollOffsets.clear();
    } else {
      _resume = [
        for (final r in navObserver.stack)
          if (_routeIds[r] != null) _routeIds[r]!,
      ];
      _resumeProfile = currentProfile?.id;
    }
    // 키와 데이터는 기다리지 않고 즉시 버린다(안전하게 실패).
    _session?.lock();
    _session = null;
    _data = null;
    currentProfile = null;
    log.info('금고 잠김($reason)');
    lockEvents.add(null);
    notifyListeners();
    await _clearClipboardNow();
  }

  // ───────── 저장 ─────────
  Future<void> save() async {
    final s = _session;
    final d = _data;
    if (s == null || d == null) return;
    await s.save(d.toJson());
    unawaited(_reschedule());
    notifyListeners();
  }

  Future<void> mutate(void Function(VaultData d) f) async {
    f(data);
    await save();
  }

  Future<void> _reschedule() async {
    final d = _data;
    if (d == null) return;
    await services.notifications.scheduleReminders(notificationTimes(d, now()));
  }

  List<AlertItem> takeUnseenAlerts() {
    final d = _data;
    if (d == null) return [];
    final u = unseenAlerts(d, now());
    if (u.isNotEmpty) {
      markSeen(d, u);
      unawaited(save());
    }
    return u;
  }

  // ───────── 자동 잠금 ─────────
  Timer? _autoLockTimer;
  DateTime? _backgroundSince;

  /// 사용자가 화면을 만질 때마다 호출 → 자동 잠금 시간을 다시 센다.
  void touch() {
    if (isUnlocked) _restartAutoLock();
  }

  void _restartAutoLock() {
    _autoLockTimer?.cancel();
    if (!isUnlocked) return;
    final secs = settings.autoLockSeconds;
    if (secs <= 0) return;
    _autoLockTimer = Timer(Duration(seconds: secs), () => lock(reason: 'auto'));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundSince ??= now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundSince;
      _backgroundSince = null;
      if (since != null && isUnlocked) {
        final away = now().difference(since);
        if (away.inSeconds >= settings.autoLockSeconds) {
          lock(reason: 'background');
        } else {
          _restartAutoLock();
        }
      }
    }
  }

  // ───────── 클립보드(30초 뒤 자동 삭제) ─────────
  /// 비밀번호 복사 후 자동 삭제까지 걸리는 시간(기본 30초).
  final int clipboardSeconds;
  final clipboardRemaining = ValueNotifier<int>(0);
  Timer? _clipTimer;
  String? _copied;

  Future<void> copySecret(String text) async {
    await services.clipboard.write(text);
    _copied = text;
    clipboardRemaining.value = clipboardSeconds;
    _clipTimer?.cancel();
    _clipTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      clipboardRemaining.value = clipboardRemaining.value - 1;
      if (clipboardRemaining.value <= 0) {
        t.cancel();
        await _clearClipboardNow();
      }
    });
  }

  /// 일반 정보(아이디 등) 복사 — 자동 삭제 대상 아님.
  Future<void> copyPlain(String text) => services.clipboard.write(text);

  Future<void> _clearClipboardNow() async {
    _clipTimer?.cancel();
    clipboardRemaining.value = 0;
    final c = _copied;
    _copied = null;
    if (c == null) return;
    final current = await services.clipboard.read();
    // 그사이 사용자가 다른 것을 복사했으면 건드리지 않는다.
    if (current == null || current == c) {
      await services.clipboard.write('');
      log.info('클립보드 자동 삭제');
    }
  }

  // ───────── 위험 동작 ─────────
  Future<bool> verifyMasterPassword(String pw) async =>
      await _session?.verifyMasterPassword(pw) ?? false;

  Future<void> setBiometric(bool on) async {
    final s = _session;
    if (s == null) return;
    if (on) {
      await s.enableDeviceUnlock(services.keyStore);
    } else {
      await s.disableDeviceUnlock(services.keyStore);
    }
    notifyListeners();
  }

  /// 이 사용자의 금고를 완전히 지운다(마스터 비밀번호 재확인 후).
  Future<void> deleteCurrentProfile() async {
    final info = currentProfile;
    if (info == null) return;
    await lock(reason: 'reset');
    await profiles.deleteProfile(info.id, services.keyStore);
    profileList = await profiles.list();
    if (settings.lastProfileId == info.id) settings.lastProfileId = null;
    await settings.save(_settingsFile);
    log.info('사용자 금고 초기화');
    notifyListeners();
  }

  /// 업데이트 전 자동 암호화 백업(앱 자료 폴더의 auto_backups). 저장 경로를 돌려준다.
  Future<String> backupBeforeUpdate(String newVersion) async {
    final info = currentProfile;
    if (info == null) throw StateError('잠긴 상태');
    final json = await backups.export(info.id, info.name, services.appVersion);
    final dir = profiles.autoBackupDir;
    await dir.create(recursive: true);
    final stamp = now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final f = File(
      p.join(dir.path, 'before-update-$newVersion-$stamp.vaultbackup'),
    );
    await writeFileAtomic(f, json);
    log.info('업데이트 전 자동 백업 저장');
    return f.path;
  }

  /// 표시 이름 바꾸기(사용자 목록 + 금고 안 설정).
  Future<void> renameProfile(String name) async {
    final info = currentProfile;
    if (info == null || name.trim().isEmpty) return;
    info.name = name.trim();
    await profiles.upsert(info);
    profileList = await profiles.list();
    await mutate((d) => d.prefs.displayName = name.trim());
  }

  /// 런처 이름·아이콘(위장) 바꾸기. 안드로이드는 실제 런처까지, 나머지는 앱 안 제목만.
  Future<bool> setLauncherStyle(String style) async {
    await updateSettings((s) => s.launcherStyle = style);
    return services.launcherStyle.setStyle(style);
  }

  Future<void> reloadProfiles() async {
    profileList = await profiles.list();
    notifyListeners();
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    _clipTimer?.cancel();
    lockEvents.close();
    super.dispose();
  }
}

/// 지금 열려 있는 화면 순서를 기록한다.
class NavStackObserver extends NavigatorObserver {
  final stack = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      stack.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      stack.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      stack.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : stack.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      stack[i] = newRoute;
    } else if (newRoute != null) {
      stack.add(newRoute);
    }
  }
}
