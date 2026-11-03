import 'dart:io';

import 'package:path/path.dart' as p;

/// 앱 전용 폴더 구조
class AppPaths {
  final Directory root;
  AppPaths(this.root);

  Directory _d(String name) {
    final d = Directory(p.join(root.path, name));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Directory get photos => _d('사진');
  Directory get thumbs => _d('썸네일');
  Directory get originals => _d('원본');
  Directory get frames => _d('영상장면');
  Directory get timelapse => _d('타임랩스사진');
  Directory get logs => _d('기록');
  Directory get backups => _d('백업');
  Directory get exports => _d('내보내기');
  Directory get exportStories => _d(p.join('내보내기', '1번앱_사연'));
  Directory get exportTimelapse => _d(p.join('내보내기', '1번앱_타임랩스'));
  Directory get exportDigital => _d(p.join('내보내기', '3번앱_디지털기록'));
  Directory get exportReports => _d(p.join('내보내기', '문제신고'));
  String get dbPath => p.join(root.path, 'binugi.db');

  /// 저장 경로를 앱 폴더 기준 상대 경로로 (백업·복원 시 기기가 바뀌어도 동작)
  String rel(String abs) => p.relative(abs, from: root.path);
  String abs(String rel) => p.isAbsolute(rel) ? rel : p.join(root.path, rel);
}
