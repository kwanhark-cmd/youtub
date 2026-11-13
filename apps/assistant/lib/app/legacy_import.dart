import 'dart:convert';
import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:path/path.dart' as p;

/// 단독 앱 하나의 식별자 (운영체제마다 자료 폴더 위치가 여기서 정해진다)
class LegacyApp {
  const LegacyApp({required this.module, required this.linuxId, required this.macId, required this.winCompany, required this.winProduct, required this.subfolder});
  final ModuleId module;
  final String linuxId;
  final String macId;
  final String winCompany;
  final String winProduct;

  /// 단독 앱 사용자 폴더 안에서 모듈 자료가 있는 하위 폴더 ('' = 사용자 폴더 전체)
  final String subfolder;

  /// 통합 앱 쪽 폴더 이름
  String get targetFolder => switch (module) {
        ModuleId.channel => 'channel_biseo',
        ModuleId.chats => 'ai_chat_organizer',
        ModuleId.declutter => 'binugi',
        ModuleId.vault => 'vault_app',
        ModuleId.harddisk => '',
        ModuleId.metaclean => '', // 따로 저장해 두는 자료가 없어 가져올 것이 없다
      };
}

const legacyApps = [
  LegacyApp(module: ModuleId.channel, linuxId: 'com.channelbiseo.channel_biseo', macId: 'com.channelbiseo.channelBiseo', winCompany: 'com.channelbiseo', winProduct: 'channel_biseo', subfolder: ''),
  LegacyApp(module: ModuleId.chats, linuxId: 'com.aichatorganizer.ai_chat_organizer', macId: 'com.aichatorganizer.aiChatOrganizer', winCompany: 'com.aichatorganizer', winProduct: 'ai_chat_organizer', subfolder: 'ai_chat_organizer'),
  LegacyApp(module: ModuleId.declutter, linuxId: 'com.binugi.binugi', macId: 'com.binugi.binugi', winCompany: 'com.binugi', winProduct: 'binugi', subfolder: 'binugi'),
  LegacyApp(module: ModuleId.vault, linuxId: 'com.kwanhark.vaultassistant.account_vault', macId: 'com.kwanhark.vaultassistant.accountVault', winCompany: 'com.kwanhark.vaultassistant', winProduct: 'account_vault', subfolder: 'vault_app'),
];

class LegacySource {
  LegacySource(this.app, this.dir, {this.alreadyImported = false, this.files = 0, this.bytes = 0, this.warning});
  final LegacyApp app;
  final Directory dir;
  final bool alreadyImported;
  final int files;
  final int bytes;
  final String? warning;
  ModuleId get module => app.module;

  String describe() {
    final mb = (bytes / 1024 / 1024).toStringAsFixed(1);
    return '파일 $files개 · $mb MB${warning == null ? '' : '\n$warning'}';
  }
}

class ImportResult {
  const ImportResult(this.ok, this.message);
  final bool ok;
  final String message;
}

/// 기존 앱에서 가져오기. 원본은 읽기만 하고 통합 앱 폴더로 복사한다.
/// - 통합 앱에 이미 자료가 있으면 먼저 통째로 백업한 뒤 덮는다.
/// - 금고는 파일을 그대로 옮기므로 기존 마스터 비밀번호로 열린다(암호화 방식 변경 없음).
/// - 대화 기록은 암호 열쇠가 기기 보안 저장소에 있어, 열쇠 파일이 함께 있을 때만 옮긴다.
///   (없으면 단독 앱의 "백업 만들기" → 대화 모듈의 "백업에서 되살리기"로 옮기라고 안내)
class LegacyImporter {
  LegacyImporter({required this.target, Map<String, String>? env, String? os, this.appsOverride})
      : _env = env ?? Platform.environment,
        _os = os ?? Platform.operatingSystem;

  final Directory target;
  final Map<String, String> _env;
  final String _os;

  /// 시험용: 모듈 → 단독 앱 사용자 폴더
  final Map<ModuleId, Directory>? appsOverride;

  File get _marker => File(p.join(target.path, 'assistant', 'imported.json'));

  Map<String, Object?> _marks() {
    try {
      return Map<String, Object?>.from(jsonDecode(_marker.readAsStringSync()) as Map);
    } catch (_) {
      return {};
    }
  }

  List<Directory> candidates(LegacyApp a) {
    final o = appsOverride?[a.module];
    if (o != null) return [o];
    final home = _env['HOME'] ?? _env['USERPROFILE'] ?? '';
    return switch (_os) {
      'linux' => [Directory(p.join(_env['XDG_DATA_HOME'] ?? p.join(home, '.local', 'share'), a.linuxId))],
      'macos' => [
          Directory(p.join(home, 'Library', 'Containers', a.macId, 'Data', 'Library', 'Application Support', a.macId)),
          Directory(p.join(home, 'Library', 'Application Support', a.macId)),
        ],
      'windows' => [Directory(p.join(_env['APPDATA'] ?? p.join(home, 'AppData', 'Roaming'), a.winCompany, a.winProduct))],
      _ => const [],
    };
  }

  Future<List<LegacySource>> discover() async {
    final out = <LegacySource>[];
    final marks = _marks();
    for (final a in legacyApps) {
      for (final root in candidates(a)) {
        final d = a.subfolder.isEmpty ? root : Directory(p.join(root.path, a.subfolder));
        if (!d.existsSync()) continue;
        var n = 0, bytes = 0;
        for (final f in d.listSync(recursive: true, followLinks: false).whereType<File>()) {
          n++;
          bytes += f.lengthSync();
        }
        if (n == 0) continue;
        String? warn;
        if (a.module == ModuleId.chats && !_chatsKeysPresent(d)) {
          warn = '대화 암호 열쇠가 기기 보안 저장소에 있어 그대로 옮길 수 없어요. 단독 앱에서 "백업 만들기" 후 대화 모듈에서 "백업에서 되살리기"를 해 주세요.';
        }
        out.add(LegacySource(a, d, alreadyImported: marks[a.module.name] != null, files: n, bytes: bytes, warning: warn));
        break;
      }
    }
    return out;
  }

  bool _chatsKeysPresent(Directory d) {
    final f = File(p.join(d.path, '.keys'));
    if (!f.existsSync()) return false;
    try {
      final m = jsonDecode(utf8.decode(base64.decode(f.readAsStringSync().trim()))) as Map;
      return m.keys.any((k) => '$k'.startsWith('datakey-'));
    } catch (_) {
      return false;
    }
  }

  Future<ImportResult> importOne(LegacySource s) async {
    if (s.module == ModuleId.chats && s.warning != null) return ImportResult(false, s.warning!);
    final dest = Directory(p.join(target.path, s.app.targetFolder));
    // 이미 통합 앱에 자료가 있으면 먼저 백업
    if (dest.existsSync() && dest.listSync().isNotEmpty) {
      final bak = Directory(p.join(target.path, 'backups', '${s.app.targetFolder}_가져오기전_${DateTime.now().millisecondsSinceEpoch}'));
      await _copy(dest, bak);
      await dest.delete(recursive: true);
      CoreLog.info('가져오기 전 백업: ${bak.path}');
    }
    final copied = await _copy(s.dir, dest, skip: (rel) => _skip(s.module, rel));
    final marks = _marks()..[s.module.name] = DateTime.now().toIso8601String();
    _marker.parent.createSync(recursive: true);
    _marker.writeAsStringSync(jsonEncode(marks));
    CoreLog.info('${s.module.title} 가져오기: 파일 $copied개');
    final note = switch (s.module) {
      ModuleId.vault => ' 금고는 기존 마스터 비밀번호로 열려요.',
      ModuleId.channel => ' 구글·AI 연결은 설정 → 연결 상태에서 열쇠 하나로 다시 이어 주세요.',
      _ => '',
    };
    return ImportResult(true, '파일 $copied개를 가져왔어요.$note');
  }

  /// 옮기지 않는 것: 임시 파일, 기록 파일, 업데이트 내려받기, 단독 앱 다른 모듈 폴더
  bool _skip(ModuleId m, String rel) {
    final first = p.split(rel).first;
    if (first == 'tmp' || first == 'logs' || first == 'updates' || rel.endsWith('.lock')) return true;
    if (m == ModuleId.channel) {
      // 1번 앱은 사용자 폴더 전체를 쓰므로, 같은 폴더에 있을 수 있는 남의 것은 빼고 옮긴다
      return const {'ai_chat_organizer', 'binugi', 'vault_app', 'flutter_secure_storage.dat'}.contains(first);
    }
    return false;
  }

  Future<int> _copy(Directory from, Directory to, {bool Function(String rel)? skip}) async {
    var n = 0;
    await to.create(recursive: true);
    await for (final e in from.list(recursive: true, followLinks: false)) {
      final rel = p.relative(e.path, from: from.path);
      if (skip?.call(rel) ?? false) continue;
      if (e is Directory) {
        await Directory(p.join(to.path, rel)).create(recursive: true);
      } else if (e is File) {
        final out = File(p.join(to.path, rel));
        await out.parent.create(recursive: true);
        await e.copy(out.path);
        n++;
      }
    }
    return n;
  }
}
