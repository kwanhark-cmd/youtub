import 'dart:io';

import 'redact.dart';

/// 본체 앱 기록. 모든 실패를 파일에 남기고, 비밀 값은 가린다.
class CoreLog {
  CoreLog._();
  static File? _file;
  static final List<String> recent = [];

  static void init(File file) {
    file.parent.createSync(recursive: true);
    _file = file;
    try {
      if (file.existsSync() && file.lengthSync() > 2 * 1024 * 1024) {
        file.renameSync('${file.path}.1');
      }
    } catch (_) {}
  }

  static void info(String msg) => _write('정보', msg);
  static void warn(String msg) => _write('주의', msg);
  static void error(String msg, [Object? e, StackTrace? st]) =>
      _write('오류', '$msg${e == null ? '' : ' — $e'}${st == null ? '' : '\n$st'}');

  static void _write(String level, String msg) {
    final line = '${DateTime.now().toIso8601String()} [$level] ${Redact.text(msg)}';
    recent.add(line);
    if (recent.length > 300) recent.removeAt(0);
    try {
      _file?.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}
