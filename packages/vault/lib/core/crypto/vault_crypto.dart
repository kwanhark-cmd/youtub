import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 암호화 작업이 실패했을 때(틀린 키, 손상된 데이터) 쓰는 예외.
/// 메시지에는 비밀 정보를 절대 넣지 않는다.
class VaultCryptoException implements Exception {
  const VaultCryptoException(this.reason);
  final String reason;
  @override
  String toString() => 'VaultCryptoException($reason)';
}

/// Argon2id 설정. 금고 머리글에 함께 저장해 나중에 강도를 올릴 수 있게 한다.
class KdfParams {
  const KdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  /// OWASP 권장 최소값(m=19MiB, t=2, p=1). 휴대폰에서도 1초 안팎.
  static const standard = KdfParams(
    memoryKiB: 19456,
    iterations: 2,
    parallelism: 1,
  );

  /// 테스트 전용(빠름). 실제 금고에는 쓰지 않는다.
  static const fastForTests = KdfParams(
    memoryKiB: 64,
    iterations: 1,
    parallelism: 1,
  );

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  Map<String, Object?> toJson() => {
    'alg': 'argon2id',
    'm': memoryKiB,
    't': iterations,
    'p': parallelism,
  };

  static KdfParams fromJson(Map<String, Object?> j) {
    if (j['alg'] != 'argon2id') {
      throw const VaultCryptoException('지원하지 않는 키 생성 방식');
    }
    final m = j['m'], t = j['t'], p = j['p'];
    if (m is! int || t is! int || p is! int || m < 8 || t < 1 || p < 1) {
      throw const VaultCryptoException('잘못된 키 생성 설정');
    }
    return KdfParams(memoryKiB: m, iterations: t, parallelism: p);
  }
}

/// AES-256-GCM 으로 암호화된 덩어리. (nonce 12바이트, 본문, 인증 태그 16바이트)
class EncryptedBlob {
  const EncryptedBlob({
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;

  Map<String, Object?> toJson() => {
    'n': base64Encode(nonce),
    'c': base64Encode(cipherText),
    'm': base64Encode(mac),
  };

  static EncryptedBlob fromJson(Object? raw) {
    if (raw is! Map) throw const VaultCryptoException('암호 덩어리 형식 오류');
    try {
      final n = base64Decode(raw['n'] as String);
      final c = base64Decode(raw['c'] as String);
      final m = base64Decode(raw['m'] as String);
      if (n.length != 12 || m.length != 16) {
        throw const VaultCryptoException('암호 덩어리 길이 오류');
      }
      return EncryptedBlob(nonce: n, cipherText: c, mac: m);
    } on VaultCryptoException {
      rethrow;
    } catch (_) {
      throw const VaultCryptoException('암호 덩어리 형식 오류');
    }
  }
}

/// 금고에서 쓰는 모든 암호화 기능을 한곳에 모은 클래스.
/// 표준 라이브러리(cryptography)만 호출하며, 직접 만든 알고리즘은 없다.
class VaultCrypto {
  VaultCrypto({Random? random}) : _random = random ?? Random.secure();

  final Random _random;
  final AesGcm _aes = AesGcm.with256bits();

  static const keyLength = 32;
  static const saltLength = 16;

  List<int> randomBytes(int length) => Uint8List.fromList(
    List<int>.generate(length, (_) => _random.nextInt(256)),
  );

  /// 마스터 비밀번호(또는 복구 코드)에서 32바이트 키를 만든다.
  Future<SecretKey> deriveKey(
    String secret,
    List<int> salt,
    KdfParams params,
  ) async {
    if (salt.length < saltLength) {
      throw const VaultCryptoException('소금값 길이 오류');
    }
    final saltCopy = List<int>.of(salt);
    final m = params.memoryKiB, t = params.iterations, p = params.parallelism;
    // 계산이 무거워(약 1초) 화면이 멈추지 않도록 별도 작업 공간(isolate)에서 실행한다.
    final bytes = await Isolate.run(() async {
      final argon = Argon2id(
        parallelism: p,
        memory: m,
        iterations: t,
        hashLength: keyLength,
      );
      final k = await argon.deriveKeyFromPassword(
        password: secret,
        nonce: saltCopy,
      );
      return k.extractBytes();
    });
    return SecretKey(bytes);
  }

  Future<SecretKey> newRandomKey() async => SecretKey(randomBytes(keyLength));

  Future<EncryptedBlob> encrypt(
    List<int> plain,
    SecretKey key, {
    List<int> aad = const [],
  }) async {
    final box = await _aes.encrypt(
      plain,
      secretKey: key,
      nonce: randomBytes(12),
      aad: aad,
    );
    return EncryptedBlob(
      nonce: box.nonce,
      cipherText: box.cipherText,
      mac: box.mac.bytes,
    );
  }

  /// 복호화. 키가 틀리거나 데이터가 바뀌었으면 [VaultCryptoException].
  Future<List<int>> decrypt(
    EncryptedBlob blob,
    SecretKey key, {
    List<int> aad = const [],
  }) async {
    try {
      return await _aes.decrypt(
        SecretBox(blob.cipherText, nonce: blob.nonce, mac: Mac(blob.mac)),
        secretKey: key,
        aad: aad,
      );
    } on SecretBoxAuthenticationError {
      throw const VaultCryptoException('인증 실패');
    } catch (_) {
      throw const VaultCryptoException('복호화 실패');
    }
  }

  /// 금고 키(데이터 키)를 다른 키로 감싼다.
  Future<EncryptedBlob> wrapKey(
    SecretKey dataKey,
    SecretKey wrappingKey,
    List<int> aad,
  ) async {
    final bytes = await dataKey.extractBytes();
    return encrypt(bytes, wrappingKey, aad: aad);
  }

  Future<SecretKey> unwrapKey(
    EncryptedBlob wrapped,
    SecretKey wrappingKey,
    List<int> aad,
  ) async {
    final bytes = await decrypt(wrapped, wrappingKey, aad: aad);
    if (bytes.length != keyLength) {
      throw const VaultCryptoException('키 길이 오류');
    }
    return SecretKey(bytes);
  }

  Future<String> sha256Hex(List<int> data) async {
    final h = await Sha256().hash(data);
    return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<String> sha1HexUpper(String text) async {
    final h = await Sha1().hash(utf8.encode(text));
    return h.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }
}
