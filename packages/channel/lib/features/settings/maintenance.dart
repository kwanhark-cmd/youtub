import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../core/db.dart';
import '../../core/failure.dart';
import '../../core/logger.dart';

/// 백업·복원, 문제 신고 파일 만들기.
class Maintenance {
  Maintenance({
    required this.db,
    required this.logger,
    required this.appVersion,
    required this.platform,
    required this.now,
  });

  final AppDatabase db;
  final AppLogger logger;
  final String appVersion;
  final String platform;
  final DateTime Function() now;

  static const backupMagicTable = 'settings';

  /// 백업 파일 만들기. 토큰·API 키는 보안 저장소에 있어서 백업에 들어가지 않는다.
  String backupTo(String dir) {
    final stamp = now().toIso8601String().substring(0, 19).replaceAll(':', '-');
    final path = p.join(dir, '채널비서-백업-$stamp.sqlite');
    db.copyTo(path);
    logger.info('백업 만듦');
    return path;
  }

  /// 백업 파일이 이 앱의 것인지 확인.
  static bool isValidBackup(String path) {
    try {
      final d = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        final v = d.select('PRAGMA user_version').first.values.first as int;
        final t = d.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('settings','channels','edits')",
        );
        return v >= 1 && t.length == 3;
      } finally {
        d.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// 복원: 현재 DB 파일을 백업 파일로 바꾼다. (현재 자료는 자동 백업 후 교체)
  /// 복원 후에는 앱이 DB 를 다시 열어 필요하면 자동 변환한다.
  static void restoreFile({required String backupPath, required String targetDbPath, required String safetyDir}) {
    if (!isValidBackup(backupPath)) throw AppFailure(FailureKind.invalidInput, 'not a backup');
    final target = File(targetDbPath);
    if (target.existsSync()) {
      Directory(safetyDir).createSync(recursive: true);
      target.copySync(p.join(safetyDir, 'before-restore-${DateTime.now().millisecondsSinceEpoch}.sqlite'));
    }
    File(backupPath).copySync(targetDbPath);
    // 복원한 자료의 계정은 토큰이 없으므로 "다시 연결" 상태로 표시
    final d = sqlite3.open(targetDbPath);
    try {
      d.execute("UPDATE accounts SET status = 'revoked' WHERE mock = 0");
    } finally {
      d.close();
    }
  }

  /// 문제 신고용 글 (민감정보 제거).
  String reportText() {
    final b = StringBuffer()
      ..writeln('# 문제 신고')
      ..writeln('앱 버전: $appVersion')
      ..writeln('기기: $platform')
      ..writeln('만든 시각: ${now().toIso8601String()}')
      ..writeln('자료 버전: ${db.version}')
      ..writeln();
    try {
      final counts = {
        '채널': db.select('SELECT COUNT(*) AS n FROM channels').first['n'],
        '영상': db.select('SELECT COUNT(*) AS n FROM videos').first['n'],
        '수정 내역': db.select('SELECT COUNT(*) AS n FROM edits').first['n'],
        '대기 작업': db.select("SELECT COUNT(*) AS n FROM jobs WHERE status='waiting'").first['n'],
      };
      b.writeln('## 자료 개수');
      counts.forEach((k, v) => b.writeln('- $k: $v'));
      b.writeln();
      b.writeln('## 최근 자동 작업 기록');
      for (final r in db.select('SELECT at, message FROM job_log ORDER BY id DESC LIMIT 30')) {
        b.writeln('- ${r['at']} ${r['message']}');
      }
      b.writeln();
    } catch (_) {}
    b.writeln('## 최근 로그');
    for (final l in logger.recentLines(300)) {
      b.writeln(l);
    }
    return redact(b.toString());
  }

  String writeReport(String dir) {
    final stamp = now().toIso8601String().substring(0, 19).replaceAll(':', '-');
    final f = File(p.join(dir, '채널비서-문제신고-$stamp.txt'));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(reportText(), encoding: utf8);
    return f.path;
  }
}
