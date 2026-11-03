import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/logger.dart';

/// 자료 폴더 위치 (앱 파일과 분리되어 있어 앱을 덮어써도 남음)
///  - 맥: ~/Library/Application Support/com.binugi.binugi/binugi
///  - 윈도우: %APPDATA%\com.binugi\binugi\binugi
///  - 안드로이드: 앱 전용 자료 폴더
///  - 리눅스: ~/.local/share/com.binugi.binugi/binugi
///
/// 1.0.0 맥 버전은 "샌드박스" 안(~/Library/Containers/...)에 자료를 두었습니다.
/// 1.1.0부터는 앱이 스스로 업데이트할 수 있도록 샌드박스를 끄므로, 예전 자료를 1회 옮깁니다.
Future<bool> migrateLegacyData(Directory newRoot, {Directory? legacyRoot}) async {
  final legacy = legacyRoot ?? _macLegacy();
  if (legacy == null || !legacy.existsSync()) return false;
  if (File(p.join(newRoot.path, 'binugi.db')).existsSync()) return false; // 이미 옮김
  if (!File(p.join(legacy.path, 'binugi.db')).existsSync()) return false;
  try {
    await newRoot.create(recursive: true);
    await _copyDir(legacy, newRoot);
    await File(p.join(legacy.path, '옮김_안내.txt')).writeAsString('이 자료는 ${newRoot.path} 로 옮겨졌어요. 새 버전 앱이 그 자료를 씁니다.');
    log.info('예전 자료 폴더에서 1회 이전 완료');
    return true;
  } catch (e, st) {
    log.error('예전 자료 이전 실패', e, st);
    return false;
  }
}

Directory? _macLegacy() {
  if (!Platform.isMacOS) return null;
  final home = Platform.environment['HOME'];
  if (home == null) return null;
  return Directory(p.join(home, 'Library', 'Containers', 'com.binugi.binugi', 'Data', 'Library', 'Application Support', 'com.binugi.binugi', 'binugi'));
}

Future<void> _copyDir(Directory from, Directory to) async {
  await for (final e in from.list(recursive: false)) {
    final name = p.basename(e.path);
    if (e is Directory) {
      final d = Directory(p.join(to.path, name));
      await d.create(recursive: true);
      await _copyDir(e, d);
    } else if (e is File) {
      await e.copy(p.join(to.path, name));
    }
  }
}
