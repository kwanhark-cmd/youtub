import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import '../clock.dart';
import '../crypto/recovery_code.dart';
import '../crypto/vault_crypto.dart';

/// 생체 인증으로 열 때 쓰는 "기기 키"를 OS 보안 저장소에 두는 창구.
abstract class DeviceKeyStore {
  Future<List<int>?> read(String profileId);
  Future<void> write(String profileId, List<int> key);
  Future<void> delete(String profileId);
}

/// OS 생체 인증(지문·얼굴·윈도우 Hello) 창구.
abstract class BiometricGate {
  Future<bool> isAvailable();
  Future<bool> authenticate(String reason);
}

/// 파일을 반쯤 쓰다 꺼져도 망가지지 않게: 임시 파일에 다 쓴 뒤 이름만 바꾼다.
Future<void> writeFileAtomic(File file, String content) async {
  await file.parent.create(recursive: true);
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(content, flush: true);
  await tmp.rename(file.path);
}

/// 틀린 비밀번호가 반복될 때 기다려야 하는 시간.
Duration lockoutDelayFor(int failedAttempts) {
  if (failedAttempts < 3) return Duration.zero;
  const table = [5, 15, 30, 60, 120]; // 3번째 실패부터
  final i = failedAttempts - 3;
  return Duration(seconds: i < table.length ? table[i] : 300);
}

class VaultHeader {
  VaultHeader({
    required this.profileId,
    required this.createdAt,
    required this.kdf,
    required this.passwordSalt,
    required this.wrappedByPassword,
    required this.recoverySalt,
    required this.wrappedByRecovery,
    this.wrappedByDevice,
    this.failedAttempts = 0,
    this.lastFailureAt,
  });

  static const format = 'account-vault-header';
  static const version = 1;

  final String profileId;
  final DateTime createdAt;
  KdfParams kdf;
  List<int> passwordSalt;
  EncryptedBlob wrappedByPassword;
  List<int> recoverySalt;
  EncryptedBlob wrappedByRecovery;
  EncryptedBlob? wrappedByDevice;
  int failedAttempts;
  DateTime? lastFailureAt;

  Map<String, Object?> toJson() => {
    'format': format,
    'version': version,
    'profileId': profileId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'kdf': kdf.toJson(),
    'passwordSalt': base64Encode(passwordSalt),
    'wrappedByPassword': wrappedByPassword.toJson(),
    'recoverySalt': base64Encode(recoverySalt),
    'wrappedByRecovery': wrappedByRecovery.toJson(),
    'wrappedByDevice': wrappedByDevice?.toJson(),
    'failedAttempts': failedAttempts,
    'lastFailureAt': lastFailureAt?.toUtc().toIso8601String(),
  };

  static VaultHeader fromJson(Object? raw) {
    if (raw is! Map || raw['format'] != format) {
      throw const VaultCryptoException('금고 머리글 형식 오류');
    }
    final v = raw['version'];
    if (v is! int || v > version) {
      throw const VaultCryptoException('더 새로운 앱 버전에서 만든 금고');
    }
    try {
      return VaultHeader(
        profileId: raw['profileId'] as String,
        createdAt: DateTime.parse(raw['createdAt'] as String),
        kdf: KdfParams.fromJson(Map<String, Object?>.from(raw['kdf'] as Map)),
        passwordSalt: base64Decode(raw['passwordSalt'] as String),
        wrappedByPassword: EncryptedBlob.fromJson(raw['wrappedByPassword']),
        recoverySalt: base64Decode(raw['recoverySalt'] as String),
        wrappedByRecovery: EncryptedBlob.fromJson(raw['wrappedByRecovery']),
        wrappedByDevice: raw['wrappedByDevice'] == null
            ? null
            : EncryptedBlob.fromJson(raw['wrappedByDevice']),
        failedAttempts: (raw['failedAttempts'] as int?) ?? 0,
        lastFailureAt: raw['lastFailureAt'] == null
            ? null
            : DateTime.parse(raw['lastFailureAt'] as String),
      );
    } on VaultCryptoException {
      rethrow;
    } catch (_) {
      throw const VaultCryptoException('금고 머리글 형식 오류');
    }
  }
}

sealed class UnlockResult {
  const UnlockResult();
}

class UnlockSuccess extends UnlockResult {
  const UnlockSuccess(this.session);
  final VaultSession session;
}

class UnlockWrongSecret extends UnlockResult {
  const UnlockWrongSecret(this.failedAttempts, this.waitBeforeNext);
  final int failedAttempts;
  final Duration waitBeforeNext;
}

class UnlockLockedOut extends UnlockResult {
  const UnlockLockedOut(this.remaining);
  final Duration remaining;
}

class UnlockUnavailable extends UnlockResult {
  const UnlockUnavailable(this.message);
  final String message;
}

class UnlockCorrupted extends UnlockResult {
  const UnlockCorrupted(this.message);
  final String message;
}

/// 한 사용자의 금고 폴더(header.json, vault.enc, vault.enc.prev).
class VaultStore {
  VaultStore({
    required this.directory,
    VaultCrypto? crypto,
    Clock? clock,
    this.newVaultKdf = KdfParams.standard,
  }) : crypto = crypto ?? VaultCrypto(),
       clock = clock ?? const SystemClock();

  final Directory directory;
  final VaultCrypto crypto;
  final Clock clock;
  final KdfParams newVaultKdf;

  static const dataFormat = 'account-vault-data';
  static const dataVersion = 1;

  File get headerFile => File(p.join(directory.path, 'header.json'));
  File get dataFile => File(p.join(directory.path, 'vault.enc'));
  File get prevDataFile => File(p.join(directory.path, 'vault.enc.prev'));

  bool get exists => headerFile.existsSync() && dataFile.existsSync();

  static List<int> aadFor(String profileId, String purpose) =>
      utf8.encode('$profileId|$purpose|v1');

  /// 새 금고를 만든다. 반환: (열린 금고, 복구 코드). 복구 코드는 화면에 한 번만 보여 준다.
  Future<(VaultSession, String)> create({
    required String profileId,
    required String masterPassword,
    required Map<String, Object?> initialData,
  }) async {
    if (exists) throw StateError('이미 금고가 있습니다');
    final dataKey = await crypto.newRandomKey();
    final pwSalt = crypto.randomBytes(VaultCrypto.saltLength);
    final pwKey = await crypto.deriveKey(masterPassword, pwSalt, newVaultKdf);
    final code = RecoveryCode.generate();
    final rcSalt = crypto.randomBytes(VaultCrypto.saltLength);
    final rcKey = await crypto.deriveKey(
      RecoveryCode.normalize(code),
      rcSalt,
      newVaultKdf,
    );
    final header = VaultHeader(
      profileId: profileId,
      createdAt: clock.now(),
      kdf: newVaultKdf,
      passwordSalt: pwSalt,
      wrappedByPassword: await crypto.wrapKey(
        dataKey,
        pwKey,
        aadFor(profileId, 'pw'),
      ),
      recoverySalt: rcSalt,
      wrappedByRecovery: await crypto.wrapKey(
        dataKey,
        rcKey,
        aadFor(profileId, 'rc'),
      ),
    );
    await directory.create(recursive: true);
    final session = VaultSession._(this, header, dataKey, initialData);
    await session.save(initialData);
    await _writeHeader(header);
    return (session, code);
  }

  Future<VaultHeader> readHeader() async {
    try {
      return VaultHeader.fromJson(jsonDecode(await headerFile.readAsString()));
    } on VaultCryptoException {
      rethrow;
    } catch (_) {
      throw const VaultCryptoException('금고 머리글을 읽을 수 없음');
    }
  }

  Future<void> _writeHeader(VaultHeader h) =>
      writeFileAtomic(headerFile, jsonEncode(h.toJson()));

  /// 지금 기다려야 하는 시간(0이면 바로 시도 가능).
  Future<Duration> lockoutRemaining() async {
    final h = await readHeader();
    return _remaining(h);
  }

  Duration _remaining(VaultHeader h) {
    final last = h.lastFailureAt;
    if (last == null) return Duration.zero;
    final until = last.add(lockoutDelayFor(h.failedAttempts));
    final left = until.difference(clock.now());
    return left.isNegative ? Duration.zero : left;
  }

  Future<UnlockResult> unlockWithPassword(String password) =>
      _unlockWithSecret(password, isRecovery: false);

  /// 복구 코드로 연다. 성공하면 반드시 새 마스터 비밀번호를 정해야 한다(코드는 1회용).
  Future<UnlockResult> unlockWithRecoveryCode(String code) {
    if (!RecoveryCode.isWellFormed(code)) {
      return _unlockWithSecret('\u0000invalid', isRecovery: true);
    }
    return _unlockWithSecret(RecoveryCode.normalize(code), isRecovery: true);
  }

  Future<UnlockResult> _unlockWithSecret(
    String secret, {
    required bool isRecovery,
  }) async {
    final VaultHeader h;
    try {
      h = await readHeader();
    } on VaultCryptoException catch (e) {
      return UnlockCorrupted(e.reason);
    }
    final wait = _remaining(h);
    if (wait > Duration.zero) return UnlockLockedOut(wait);

    SecretKey dataKey;
    try {
      final k = await crypto.deriveKey(
        secret,
        isRecovery ? h.recoverySalt : h.passwordSalt,
        h.kdf,
      );
      dataKey = await crypto.unwrapKey(
        isRecovery ? h.wrappedByRecovery : h.wrappedByPassword,
        k,
        aadFor(h.profileId, isRecovery ? 'rc' : 'pw'),
      );
    } on VaultCryptoException {
      h.failedAttempts += 1;
      h.lastFailureAt = clock.now();
      await _writeHeader(h);
      return UnlockWrongSecret(
        h.failedAttempts,
        lockoutDelayFor(h.failedAttempts),
      );
    }
    return _openWithKey(h, dataKey, mustResetPassword: isRecovery);
  }

  /// 생체 인증으로 연다. 무엇이든 실패하면 UnlockUnavailable → 화면은 비밀번호로 넘어간다.
  Future<UnlockResult> unlockWithDevice(
    DeviceKeyStore store,
    BiometricGate gate,
  ) async {
    try {
      final h = await readHeader();
      final wrapped = h.wrappedByDevice;
      if (wrapped == null) return const UnlockUnavailable('생체 인증이 꺼져 있어요');
      if (_remaining(h) > Duration.zero) {
        return UnlockLockedOut(_remaining(h));
      }
      if (!await gate.isAvailable()) {
        return const UnlockUnavailable('이 기기에서 생체 인증을 쓸 수 없어요');
      }
      if (!await gate.authenticate('금고를 열려면 본인 확인이 필요해요')) {
        return const UnlockUnavailable('본인 확인이 취소되었어요');
      }
      final raw = await store.read(h.profileId);
      if (raw == null) return const UnlockUnavailable('기기 키를 찾을 수 없어요');
      final dataKey = await crypto.unwrapKey(
        wrapped,
        SecretKey(raw),
        aadFor(h.profileId, 'dev'),
      );
      return await _openWithKey(h, dataKey, mustResetPassword: false);
    } catch (_) {
      return const UnlockUnavailable('생체 인증으로 열지 못했어요');
    }
  }

  Future<UnlockResult> _openWithKey(
    VaultHeader h,
    SecretKey dataKey, {
    required bool mustResetPassword,
  }) async {
    Map<String, Object?>? data;
    String? note;
    try {
      data = await _readData(dataFile, h.profileId, dataKey);
    } catch (_) {
      // 본문이 손상되었으면 바로 전 저장본으로 시도한다.
      try {
        if (prevDataFile.existsSync()) {
          data = await _readData(prevDataFile, h.profileId, dataKey);
          note = 'restored_prev';
        }
      } catch (_) {}
    }
    if (data == null) {
      return const UnlockCorrupted('금고 파일이 손상되었어요. 백업 파일로 복원해 주세요.');
    }
    if (h.failedAttempts != 0 || h.lastFailureAt != null) {
      h.failedAttempts = 0;
      h.lastFailureAt = null;
      await _writeHeader(h);
    }
    final s = VaultSession._(this, h, dataKey, data)
      ..mustResetPassword = mustResetPassword
      ..openNote = note;
    if (note != null) await s.save(data);
    return UnlockSuccess(s);
  }

  Future<Map<String, Object?>> _readData(
    File f,
    String profileId,
    SecretKey key,
  ) async {
    final raw = jsonDecode(await f.readAsString());
    if (raw is! Map || raw['format'] != dataFormat) {
      throw const VaultCryptoException('금고 본문 형식 오류');
    }
    final blob = EncryptedBlob.fromJson(raw['blob']);
    final plain = await crypto.decrypt(
      blob,
      key,
      aad: aadFor(profileId, 'data'),
    );
    final decoded = jsonDecode(utf8.decode(plain));
    if (decoded is! Map) throw const VaultCryptoException('금고 본문 형식 오류');
    return Map<String, Object?>.from(decoded);
  }

  /// 금고 파일 묶음(백업용). 기기 키와 실패 횟수는 뺀다.
  Future<Map<String, Object?>> exportRaw() async {
    final h = await readHeader();
    h.wrappedByDevice = null;
    h.failedAttempts = 0;
    h.lastFailureAt = null;
    final data = jsonDecode(await dataFile.readAsString());
    return {'header': h.toJson(), 'data': data};
  }

  /// 백업 묶음을 이 폴더에 쓴다(검사는 호출 쪽에서 끝낸 뒤).
  Future<void> importRaw(Map<String, Object?> header, Object? data) async {
    await directory.create(recursive: true);
    await writeFileAtomic(dataFile, jsonEncode(data));
    if (prevDataFile.existsSync()) await prevDataFile.delete();
    await writeFileAtomic(headerFile, jsonEncode(header));
  }
}

/// 열린 금고. 잠그면 키와 데이터 참조를 버린다.
class VaultSession {
  VaultSession._(this._store, this._header, this._dataKey, this._data);

  final VaultStore _store;
  final VaultHeader _header;
  SecretKey? _dataKey;
  Map<String, Object?>? _data;

  /// 복구 코드로 열었으면 true → 새 마스터 비밀번호를 정하기 전에는 다른 화면으로 못 간다.
  bool mustResetPassword = false;

  /// 'restored_prev' 이면 직전 저장본으로 복구했다는 뜻.
  String? openNote;

  String get profileId => _header.profileId;
  bool get isOpen => _dataKey != null;
  bool get hasDeviceUnlock => _header.wrappedByDevice != null;

  Map<String, Object?> get data {
    final d = _data;
    if (d == null) throw StateError('잠긴 금고');
    return d;
  }

  SecretKey get _key {
    final k = _dataKey;
    if (k == null) throw StateError('잠긴 금고');
    return k;
  }

  Future<void> save(Map<String, Object?> data) async {
    final plain = utf8.encode(jsonEncode(data));
    final blob = await _store.crypto.encrypt(
      plain,
      _key,
      aad: VaultStore.aadFor(profileId, 'data'),
    );
    final f = _store.dataFile;
    if (f.existsSync()) {
      await f.copy(_store.prevDataFile.path);
    }
    await writeFileAtomic(
      f,
      jsonEncode({
        'format': VaultStore.dataFormat,
        'v': VaultStore.dataVersion,
        'savedAt': _store.clock.now().toUtc().toIso8601String(),
        'blob': blob.toJson(),
      }),
    );
    _data = data;
  }

  Future<void> changeMasterPassword(String newPassword) async {
    final salt = _store.crypto.randomBytes(VaultCrypto.saltLength);
    final k = await _store.crypto.deriveKey(newPassword, salt, _header.kdf);
    _header.passwordSalt = salt;
    _header.wrappedByPassword = await _store.crypto.wrapKey(
      _key,
      k,
      VaultStore.aadFor(profileId, 'pw'),
    );
    await _store._writeHeader(_header);
  }

  /// 새 복구 코드를 만들고 이전 코드는 못 쓰게 한다. 새 코드를 돌려준다.
  Future<String> regenerateRecoveryCode() async {
    final code = RecoveryCode.generate();
    final salt = _store.crypto.randomBytes(VaultCrypto.saltLength);
    final k = await _store.crypto.deriveKey(
      RecoveryCode.normalize(code),
      salt,
      _header.kdf,
    );
    _header.recoverySalt = salt;
    _header.wrappedByRecovery = await _store.crypto.wrapKey(
      _key,
      k,
      VaultStore.aadFor(profileId, 'rc'),
    );
    await _store._writeHeader(_header);
    return code;
  }

  /// 복구 코드로 연 뒤: 새 비밀번호 설정 + 새 복구 코드 발급.
  Future<String> completeRecovery(String newPassword) async {
    await changeMasterPassword(newPassword);
    final code = await regenerateRecoveryCode();
    mustResetPassword = false;
    return code;
  }

  Future<void> enableDeviceUnlock(DeviceKeyStore store) async {
    final deviceKey = _store.crypto.randomBytes(VaultCrypto.keyLength);
    await store.write(profileId, deviceKey);
    _header.wrappedByDevice = await _store.crypto.wrapKey(
      _key,
      SecretKey(deviceKey),
      VaultStore.aadFor(profileId, 'dev'),
    );
    await _store._writeHeader(_header);
  }

  Future<void> disableDeviceUnlock(DeviceKeyStore store) async {
    _header.wrappedByDevice = null;
    await _store._writeHeader(_header);
    await store.delete(profileId);
  }

  /// 마스터 비밀번호를 다시 확인(초기화·위험 동작 전에 사용). 실패 횟수에 포함하지 않는다.
  Future<bool> verifyMasterPassword(String password) async {
    try {
      final k = await _store.crypto.deriveKey(
        password,
        _header.passwordSalt,
        _header.kdf,
      );
      await _store.crypto.unwrapKey(
        _header.wrappedByPassword,
        k,
        VaultStore.aadFor(profileId, 'pw'),
      );
      return true;
    } on VaultCryptoException {
      return false;
    }
  }

  void lock() {
    _dataKey = null;
    _data = null;
  }
}
