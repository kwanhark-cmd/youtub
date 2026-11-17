import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:path/path.dart' as p;

/// 컴퓨터에서 찾은 자료 폴더 하나와 어울리는 모듈.
class FolderMatch {
  const FolderMatch(this.path, this.module);
  final String path;
  final ModuleId module;
  String get name => p.basename(path);
}

/// "내 자료 폴더 연결": 사용자 폴더에서 모듈에 맞는 자료 폴더를 찾는다.
///
/// - 폴더 이름·위치·파일은 절대 바꾸지 않는다 (목록만 읽음).
/// - 숨김 폴더와 ~/Library 는 보지 않는다.
/// - 법률·개인생활·백업처럼 민감할 수 있는 폴더는 자동으로 고르지 않는다 (직접 고르면 연결 가능).
class DataFolderFinder {
  DataFolderFinder(this.home, {this.maxDepth = 3});
  final String home;
  final int maxDepth;

  static final _chats = RegExp(r'(claude|chatgpt|gpt|gemini|클로드|챗\s?gpt|제미나이).*(저장소|내보내기|export|대화)', caseSensitive: false);
  static const _channel = ['유튜브', 'youtube', '영상제작', '확정영상', '납품', '캡쳐', '캡처', 'capture'];
  static const _protected = {'Library', 'Applications', 'Desktop', 'Documents', 'Downloads', 'Pictures', 'Movies', 'Music', 'Public'};
  static const _sensitive = ['법률', '사건', '개인생활', '백업', 'backup', '금고', '비밀', 'password', '계정'];

  /// 이 이름은 어느 모듈 자료인가 (없으면 null)
  static ModuleId? moduleFor(String folderName) {
    final n = folderName.toLowerCase();
    if (_sensitive.any(n.contains)) return null;
    if (_chats.hasMatch(n)) return ModuleId.chats;
    if (_channel.any(n.contains)) return ModuleId.channel;
    return null;
  }

  List<FolderMatch> find() {
    final out = <FolderMatch>[];
    void walk(Directory d, int depth) {
      List<FileSystemEntity> list;
      try {
        list = d.listSync(followLinks: false);
      } catch (_) {
        return; // 읽을 수 없는 폴더는 건너뜀
      }
      for (final e in list.whereType<Directory>()) {
        final name = p.basename(e.path);
        // 맥의 보호 폴더(데스크톱·문서·다운로드 등)는 자동으로 열지 않는다: 열면 맥이 허락을 물어본다. 직접 고르기로 연결.
        if (name.startsWith('.') || (depth == 0 && _protected.contains(name))) continue;
        if (_sensitive.any(name.toLowerCase().contains)) continue; // 안으로도 들어가지 않음
        final m = moduleFor(name);
        if (m != null) {
          out.add(FolderMatch(e.path, m));
          continue; // 찾은 폴더 안은 모듈이 직접 읽음
        }
        if (depth + 1 < maxDepth) walk(e, depth + 1);
      }
    }

    walk(Directory(home), 0);
    out.sort((a, b) => a.module.index != b.module.index ? a.module.index.compareTo(b.module.index) : a.path.compareTo(b.path));
    return out;
  }
}

/// 연결한 폴더 목록 (설정 파일에 경로만 저장)
class ConnectedFolders {
  ConnectedFolders(this.settings);
  final AppSettings settings;

  List<String> of(ModuleId m) => (settings.get<List>('folders.${m.name}', const [])).cast<String>();

  void add(ModuleId m, String path) {
    final l = of(m);
    if (!l.contains(path)) settings.set('folders.${m.name}', [...l, path]);
  }

  void remove(ModuleId m, String path) => settings.set('folders.${m.name}', of(m).where((x) => x != path).toList());
}
