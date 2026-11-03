import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 대화 본문을 AES-256-GCM으로 암호화합니다.
/// 저장 형식: [버전 1바이트][nonce 12바이트][암호문][태그 16바이트]
class ContentCipher {
  static const _version = 1;
  final AesGcm _algo = AesGcm.with256bits();
  final SecretKey _key;

  ContentCipher(List<int> keyBytes) : _key = SecretKey(keyBytes);

  static List<int> newKeyBytes() {
    final r = Random.secure();
    return List<int>.generate(32, (_) => r.nextInt(256));
  }

  Future<Uint8List> encryptString(String plain) async {
    final compressed = gzip.encode(utf8.encode(plain));
    final box = await _algo.encrypt(compressed, secretKey: _key);
    final out = BytesBuilder(copy: false)
      ..addByte(_version)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.toBytes();
  }

  Future<String> decryptString(Uint8List data) async {
    if (data.isEmpty || data[0] != _version) {
      throw const FormatException('알 수 없는 암호화 형식');
    }
    final nonce = data.sublist(1, 13);
    final mac = Mac(data.sublist(data.length - 16));
    final cipher = data.sublist(13, data.length - 16);
    final plain = await _algo.decrypt(
      SecretBox(cipher, nonce: nonce, mac: mac),
      secretKey: _key,
    );
    return utf8.decode(gzip.decode(plain));
  }
}

/// 백업 파일처럼 비밀번호로 잠그는 암호화(PBKDF2 + AES-GCM).
class PasswordCipher {
  static const _magic = 'AICB1';
  static const iterations = 120000;

  static Future<Uint8List> encrypt(List<int> data, String password) async {
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final key = await _derive(password, salt);
    final box = await AesGcm.with256bits().encrypt(gzip.encode(data), secretKey: key);
    return (BytesBuilder()
          ..add(ascii.encode(_magic))
          ..add(salt)
          ..add(box.nonce)
          ..add(box.mac.bytes)
          ..add(box.cipherText))
        .toBytes();
  }

  static Future<List<int>> decrypt(Uint8List data, String password) async {
    if (data.length < 49 || ascii.decode(data.sublist(0, 5), allowInvalid: true) != _magic) {
      throw const FormatException('백업 파일이 아니에요');
    }
    final salt = data.sublist(5, 21);
    final nonce = data.sublist(21, 33);
    final mac = Mac(data.sublist(33, 49));
    final cipher = data.sublist(49);
    final key = await _derive(password, salt);
    final plain = await AesGcm.with256bits().decrypt(
      SecretBox(cipher, nonce: nonce, mac: mac),
      secretKey: key,
    );
    return gzip.decode(plain);
  }

  static Future<SecretKey> _derive(String password, List<int> salt) {
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    return kdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  }
}
