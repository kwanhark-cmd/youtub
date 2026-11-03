import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/clock.dart';
import '../core/crypto/vault_crypto.dart';
import '../core/vault/vault.dart';
import 'models.dart';

class ProfileInfo {
  ProfileInfo(this.id, this.name, this.createdAt);
  final String id;
  String name;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
  };

  static ProfileInfo fromJson(Map<String, Object?> j) => ProfileInfo(
    j['id'] as String,
    (j['name'] as String?) ?? '사용자',
    DateTime.tryParse((j['createdAt'] as String?) ?? '') ?? DateTime.now(),
  );
}

/// 이 기기의 사용자 목록. 사용자마다 금고 폴더가 완전히 따로 있다.
/// 목록에는 이름(사용자가 정한 별칭)만 있고 다른 정보는 없다.
class ProfileRepository {
  ProfileRepository(this.root, {this.kdf = KdfParams.standard, Clock? clock})
    : clock = clock ?? const SystemClock();

  final Directory root;
  final KdfParams kdf;
  final Clock clock;

  File get _file => File(p.join(root.path, 'profiles.json'));
  Directory get autoBackupDir => Directory(p.join(root.path, 'auto_backups'));

  Future<List<ProfileInfo>> list() async {
    var list = <ProfileInfo>[];
    try {
      if (_file.existsSync()) {
        final raw = jsonDecode(await _file.readAsString());
        list = (raw as List)
            .whereType<Map>()
            .map((m) => ProfileInfo.fromJson(Map<String, Object?>.from(m)))
            .toList();
      }
    } catch (_) {
      list = [];
    }
    // 금고 파일이 없는 항목은 숨긴다(만들다 중단된 경우).
    list = list.where((pi) => storeFor(pi.id).exists).toList();
    // 목록 파일이 지워지거나 손상돼도 금고 폴더가 남아 있으면 다시 찾아 준다.
    final found = await _scanVaultFolders(list.map((e) => e.id).toSet());
    if (found.isNotEmpty) {
      list.addAll(found);
      try {
        await _save(list);
      } catch (_) {}
    }
    return list;
  }

  Future<List<ProfileInfo>> _scanVaultFolders(Set<String> known) async {
    final out = <ProfileInfo>[];
    final dir = Directory(p.join(root.path, 'profiles'));
    if (!dir.existsSync()) return out;
    for (final e in dir.listSync().whereType<Directory>()) {
      final id = p.basename(e.path);
      if (known.contains(id) || !storeFor(id).exists) continue;
      try {
        final h = await storeFor(id).readHeader();
        if (h.profileId != id) continue;
        out.add(
          ProfileInfo(id, '사용자 ${out.length + known.length + 1}', h.createdAt),
        );
      } catch (_) {}
    }
    return out;
  }

  Future<void> _save(List<ProfileInfo> list) =>
      writeFileAtomic(_file, jsonEncode(list.map((e) => e.toJson()).toList()));

  VaultStore storeFor(String id) => VaultStore(
    directory: Directory(p.join(root.path, 'profiles', id)),
    clock: clock,
    newVaultKdf: kdf,
  );

  Future<(VaultSession, String, ProfileInfo)> createProfile(
    String name,
    String masterPassword,
  ) async {
    final id = newId();
    final store = storeFor(id);
    final data = VaultData(prefs: UserPrefs(displayName: name));
    final (session, code) = await store.create(
      profileId: id,
      masterPassword: masterPassword,
      initialData: data.toJson(),
    );
    final info = ProfileInfo(id, name, clock.now());
    final all = await _rawList();
    all.add(info);
    await _save(all);
    return (session, code, info);
  }

  Future<List<ProfileInfo>> _rawList() async {
    try {
      if (!_file.existsSync()) return [];
      final raw = jsonDecode(await _file.readAsString()) as List;
      return raw
          .whereType<Map>()
          .map((m) => ProfileInfo.fromJson(Map<String, Object?>.from(m)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> upsert(ProfileInfo info) async {
    final all = await _rawList();
    all.removeWhere((e) => e.id == info.id);
    all.add(info);
    await _save(all);
  }

  /// 사용자 삭제(초기화). 금고 폴더를 지운다. 되돌릴 수 없으므로 화면에서 2단계 확인 후 호출.
  Future<void> deleteProfile(String id, DeviceKeyStore keys) async {
    final all = await _rawList();
    all.removeWhere((e) => e.id == id);
    await _save(all);
    final dir = storeFor(id).directory;
    if (dir.existsSync()) await dir.delete(recursive: true);
    try {
      await keys.delete(id);
    } catch (_) {}
  }
}

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
}

class BackupInfo {
  BackupInfo(this.profileId, this.profileName, this.createdAt, this.raw);
  final String profileId;
  final String profileName;
  final DateTime createdAt;
  final Map<String, Object?> raw;
}

/// 암호화된 백업 파일 내보내기·가져오기.
/// 백업 파일 안의 데이터는 금고와 똑같이 암호화되어 있어, 마스터 비밀번호 없이는 열 수 없다.
class BackupService {
  BackupService(this.profiles, {VaultCrypto? crypto})
    : crypto = crypto ?? VaultCrypto();

  final ProfileRepository profiles;
  final VaultCrypto crypto;

  static const format = 'account-vault-backup';
  static const backupVersion = 1;

  Future<String> export(
    String profileId,
    String profileName,
    String appVersion,
  ) async {
    final payload = await profiles.storeFor(profileId).exportRaw();
    final payloadJson = jsonEncode(payload);
    return const JsonEncoder.withIndent(' ').convert({
      'format': format,
      'backupVersion': backupVersion,
      'appVersion': appVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'profileId': profileId,
      'profileName': profileName,
      'sha256': await crypto.sha256Hex(utf8.encode(payloadJson)),
      'payload': payload,
    });
  }

  /// 복원 전에 파일을 검사한다(형식·버전·손상 여부).
  Future<BackupInfo> inspect(String content) async {
    Object? raw;
    try {
      raw = jsonDecode(content);
    } catch (_) {
      throw const BackupException('백업 파일이 아니거나 손상되었어요.');
    }
    if (raw is! Map || raw['format'] != format) {
      throw const BackupException('이 앱에서 만든 백업 파일이 아니에요.');
    }
    final v = raw['backupVersion'];
    if (v is! int) throw const BackupException('백업 파일이 손상되었어요.');
    if (v > backupVersion) {
      throw const BackupException(
        '더 새로운 앱 버전에서 만든 백업이에요. 앱을 최신 버전으로 업데이트한 뒤 다시 시도해 주세요.',
      );
    }
    final payload = raw['payload'];
    if (payload is! Map ||
        payload['header'] is! Map ||
        payload['data'] == null) {
      throw const BackupException('백업 파일이 손상되었어요.');
    }
    final sha = await crypto.sha256Hex(utf8.encode(jsonEncode(payload)));
    if (sha != raw['sha256']) {
      throw const BackupException(
        '백업 파일이 손상되었어요(내용이 바뀌었어요). 다른 백업 파일을 골라 주세요.',
      );
    }
    try {
      final h = VaultHeader.fromJson(payload['header']);
      if (h.profileId != raw['profileId']) {
        throw const VaultCryptoException('id');
      }
    } on VaultCryptoException {
      throw const BackupException('백업 파일이 손상되었거나 지원하지 않는 버전이에요.');
    }
    return BackupInfo(
      raw['profileId'] as String,
      (raw['profileName'] as String?) ?? '사용자',
      DateTime.tryParse('${raw['createdAt']}') ?? DateTime.now(),
      Map<String, Object?>.from(payload),
    );
  }

  /// 백업의 마스터 비밀번호가 맞는지 임시 폴더에서 확인한다.
  Future<bool> verifyPassword(
    BackupInfo info,
    String password,
    Directory scratch,
  ) async {
    final tmp = VaultStore(
      directory: Directory(p.join(scratch.path, 'verify_${newId()}')),
    );
    try {
      await tmp.importRaw(
        Map<String, Object?>.from(info.raw['header'] as Map),
        info.raw['data'],
      );
      final r = await tmp.unlockWithPassword(password);
      if (r is UnlockSuccess) {
        r.session.lock();
        return true;
      }
      return false;
    } finally {
      if (tmp.directory.existsSync()) {
        await tmp.directory.delete(recursive: true);
      }
    }
  }

  /// 복원: 같은 사용자의 현재 데이터를 먼저 자동 백업한 뒤 바꾼다.
  /// 반환: 자동 백업 파일 경로(없으면 null).
  Future<String?> restore(BackupInfo info, String appVersion) async {
    String? autoPath;
    final store = profiles.storeFor(info.profileId);
    if (store.exists) {
      final current = await export(
        info.profileId,
        info.profileName,
        appVersion,
      );
      await profiles.autoBackupDir.create(recursive: true);
      final stamp = DateTime.now().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final f = File(
        p.join(profiles.autoBackupDir.path, 'before-restore-$stamp.json'),
      );
      await writeFileAtomic(f, current);
      autoPath = f.path;
    }
    await store.importRaw(
      Map<String, Object?>.from(info.raw['header'] as Map),
      info.raw['data'],
    );
    await profiles.upsert(
      ProfileInfo(info.profileId, info.profileName, DateTime.now()),
    );
    return autoPath;
  }
}

/// 기기 공통 설정(암호화하지 않음: 개인 정보 없음). 잠금 화면에서도 글씨 크기 등이 필요하다.
class DeviceSettings {
  DeviceSettings({
    this.textScaleLevel = 1,
    this.themeMode = 'light',
    this.reduceMotion = false,
    this.haptics = true,
    this.sound = true,
    this.autoLockSeconds = 120,
    this.lastProfileId,
    this.tipsShown = const {},
    this.voiceProvider = 'device',
    this.colorTheme = 'violet',
    this.launcherStyle = 'default',
  });

  /// 색 테마(주요색): violet(기본)·plum·navy·slate
  String colorTheme;

  /// 앱 겉모습(위장): default·calculator·memo — 런처 이름·아이콘(안드로이드)과 앱 제목
  String launcherStyle;

  static const colorThemes = {
    'violet': '보라(기본)',
    'plum': '자주',
    'navy': '남색',
    'slate': '먹색',
  };
  static const launcherStyles = {
    'default': '구독·계정 비서(기본)',
    'calculator': '계산기',
    'memo': '메모',
  };

  /// 작업 전환 화면 등에 보이는 앱 이름.
  String get appTitle => switch (launcherStyle) {
    'calculator' => '계산기',
    'memo' => '메모',
    _ => '구독·계정 비서',
  };

  /// 0=보통, 1=크게, 2=아주 크게
  int textScaleLevel;

  /// light, dark, contrast, system
  String themeMode;
  bool reduceMotion;
  bool haptics;
  bool sound;
  int autoLockSeconds;
  String? lastProfileId;
  Set<String> tipsShown;
  String voiceProvider;

  static const textScales = [1.0, 1.3, 1.6];
  static const textScaleLabels = ['보통', '크게', '아주 크게'];

  double get textScale => textScales[textScaleLevel.clamp(0, 2)];

  Map<String, Object?> toJson() => {
    'textScaleLevel': textScaleLevel,
    'themeMode': themeMode,
    'reduceMotion': reduceMotion,
    'haptics': haptics,
    'sound': sound,
    'autoLockSeconds': autoLockSeconds,
    'lastProfileId': lastProfileId,
    'tipsShown': tipsShown.toList(),
    'voiceProvider': voiceProvider,
    'colorTheme': colorTheme,
    'launcherStyle': launcherStyle,
  };

  static DeviceSettings fromJson(Map<String, Object?> j) => DeviceSettings(
    textScaleLevel: (j['textScaleLevel'] as num?)?.toInt() ?? 1,
    themeMode: (j['themeMode'] as String?) ?? 'light',
    reduceMotion: (j['reduceMotion'] as bool?) ?? false,
    haptics: (j['haptics'] as bool?) ?? true,
    sound: (j['sound'] as bool?) ?? true,
    autoLockSeconds: (j['autoLockSeconds'] as num?)?.toInt() ?? 120,
    lastProfileId: j['lastProfileId'] as String?,
    tipsShown: ((j['tipsShown'] as List?) ?? []).whereType<String>().toSet(),
    voiceProvider: (j['voiceProvider'] as String?) ?? 'device',
    colorTheme: (j['colorTheme'] as String?) ?? 'violet',
    launcherStyle: (j['launcherStyle'] as String?) ?? 'default',
  );

  static Future<DeviceSettings> load(File f) async {
    try {
      if (!f.existsSync()) return DeviceSettings();
      return fromJson(
        Map<String, Object?>.from(jsonDecode(await f.readAsString()) as Map),
      );
    } catch (_) {
      return DeviceSettings();
    }
  }

  Future<void> save(File f) => writeFileAtomic(f, jsonEncode(toJson()));
}
