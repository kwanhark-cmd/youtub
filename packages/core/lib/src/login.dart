import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'log.dart';
import 'settings.dart';

/// 개인비서 사용자 (이 기기 안에만 있는 계정).
class AssistantUser {
  const AssistantUser(this.id, this.name);
  final int id;
  final String name;
}

String _pbkdf2(String password, List<int> salt, {int iterations = 20000}) {
  final hmac = Hmac(sha256, utf8.encode(password));
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final out = List<int>.from(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return base64Encode(out);
}

/// 하나의 로그인. 비밀번호는 저장하지 않고 해시만 둔다. 자동 로그인은 사용자 번호만 보안 저장소에.
class AuthService {
  AuthService({required this.file, required this.secrets, this.iterations = 20000});
  final File file;
  final SecretStore secrets;
  final int iterations;
  static const _autoKey = 'autoLoginUser';

  List<Map<String, Object?>> _rows() {
    if (!file.existsSync()) return [];
    try {
      return (jsonDecode(file.readAsStringSync()) as List).cast<Map>().map((e) => Map<String, Object?>.from(e)).toList();
    } catch (e) {
      CoreLog.error('사용자 목록을 읽지 못함', e);
      return [];
    }
  }

  void _write(List<Map<String, Object?>> rows) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(rows), flush: true);
  }

  List<AssistantUser> list() => _rows().map((r) => AssistantUser(r['id'] as int, r['name'] as String)).toList();

  /// 새 사용자. 이름은 비어 있으면 안 되고, 비밀번호는 4자 이상.
  AssistantUser create(String name, String password) {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('이름을 적어 주세요.');
    if (password.length < 4) throw ArgumentError('비밀번호는 4자 이상이어야 해요.');
    final rows = _rows();
    if (rows.any((r) => r['name'] == n)) throw ArgumentError('같은 이름이 이미 있어요.');
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final id = rows.isEmpty ? 1 : rows.map((e) => e['id'] as int).reduce(max) + 1;
    rows.add({'id': id, 'name': n, 'salt': base64Encode(salt), 'hash': _pbkdf2(password, salt, iterations: iterations), 'it': iterations});
    _write(rows);
    CoreLog.info('사용자 만듦 #$id');
    return AssistantUser(id, n);
  }

  AssistantUser? verify(int id, String password) {
    for (final r in _rows()) {
      if (r['id'] != id) continue;
      final it = (r['it'] as int?) ?? iterations;
      if (_pbkdf2(password, base64Decode(r['salt'] as String), iterations: it) == r['hash']) {
        return AssistantUser(id, r['name'] as String);
      }
      return null;
    }
    return null;
  }

  Future<void> setAutoLogin(AssistantUser u, bool on) => on ? secrets.write(_autoKey, '${u.id}') : secrets.delete(_autoKey);

  Future<AssistantUser?> tryAutoLogin() async {
    final id = int.tryParse(await secrets.read(_autoKey) ?? '');
    if (id == null) return null;
    for (final u in list()) {
      if (u.id == id) return u;
    }
    return null;
  }

  Future<void> logout() => secrets.delete(_autoKey);
}
