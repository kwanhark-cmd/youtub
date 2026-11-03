import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:uuid/uuid.dart';

import '../models/models.dart';

/// 기기 안의 사용자(로컬 계정) 목록. 사용자마다 폴더·DB·암호화 키가 따로입니다.
class UserService {
  final Directory root;
  UserService(this.root);

  File get _file => File('${root.path}/users.json');

  List<UserProfile> load() {
    try {
      if (!_file.existsSync()) return [];
      final list = jsonDecode(_file.readAsStringSync()) as List;
      return list.map((e) => UserProfile.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  void _save(List<UserProfile> users) {
    root.createSync(recursive: true);
    final tmp = File('${_file.path}.tmp');
    tmp.writeAsStringSync(jsonEncode(users.map((u) => u.toJson()).toList()));
    tmp.renameSync(_file.path);
  }

  Directory dirOf(String userId) => Directory('${root.path}/users/$userId');

  static String hashPin(String userId, String pin) => crypto.sha256.convert(utf8.encode('aico:$userId:$pin')).toString();

  UserProfile create(String name, {String emoji = '🙂', String? pin}) {
    final id = const Uuid().v4();
    final u = UserProfile(
      id: id,
      name: name.trim().isEmpty ? '나' : name.trim(),
      emoji: emoji,
      pinHash: (pin == null || pin.isEmpty) ? null : hashPin(id, pin),
      createdAt: DateTime.now(),
    );
    _save([...load(), u]);
    dirOf(id).createSync(recursive: true);
    return u;
  }

  bool checkPin(UserProfile u, String pin) => u.pinHash == null || u.pinHash == hashPin(u.id, pin);

  void rename(String id, String name) {
    _save(
      load()
          .map((u) => u.id == id ? UserProfile(id: u.id, name: name, emoji: u.emoji, pinHash: u.pinHash, createdAt: u.createdAt) : u)
          .toList(),
    );
  }

  /// 앱 안의 이 사용자 자료만 지웁니다(사용자가 넣은 원본 파일과 무관).
  void remove(String id) {
    _save(load().where((u) => u.id != id).toList());
    final d = dirOf(id);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }
}
