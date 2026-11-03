import 'dart:io';

/// 기기 안에만 남는 작업 기록.
/// 대화 본문·키·토큰은 절대 기록하지 않습니다(값을 지우고 남김).
class AppLog {
  static File? _file;
  static final List<String> _memory = [];
  static const _maxBytes = 1024 * 1024;

  static void init(File file) {
    _file = file;
    try {
      file.parent.createSync(recursive: true);
      if (file.existsSync() && file.lengthSync() > _maxBytes) {
        final old = File('${file.path}.1');
        if (old.existsSync()) old.deleteSync();
        file.renameSync(old.path);
      }
    } catch (_) {}
  }

  static final _secretPatterns = <RegExp>[
    RegExp(r'sk-ant-[A-Za-z0-9_\-]+'),
    RegExp(r'sk-[A-Za-z0-9]{16,}'),
    RegExp(r'Bearer\s+\S+', caseSensitive: false),
    RegExp(r'ya29\.[A-Za-z0-9_\-\.]+'),
    RegExp(r'AIza[0-9A-Za-z_\-]{20,}'),
  ];

  /// 비밀값처럼 보이는 글자를 가립니다.
  static String redact(String s) {
    var out = s;
    for (final p in _secretPatterns) {
      out = out.replaceAll(p, '[가림]');
    }
    return out;
  }

  /// 본문이 들어갈 수 있는 이름의 값은 아예 버립니다.
  static const _blockedFields = {'text', 'body', 'content', 'message', 'prompt', 'key', 'apiKey', 'token', 'password', 'note'};

  static String _format(String level, String event, Map<String, Object?>? fields) {
    final f = <String>[];
    fields?.forEach((k, v) {
      if (_blockedFields.contains(k)) {
        f.add('$k=[기록안함]');
      } else {
        var s = '$v';
        if (s.length > 200) s = '${s.substring(0, 200)}…';
        f.add('$k=${redact(s)}');
      }
    });
    return '${DateTime.now().toIso8601String()} [$level] ${redact(event)} ${f.join(' ')}';
  }

  static void _write(String line) {
    _memory.add(line);
    if (_memory.length > 500) _memory.removeAt(0);
    try {
      _file?.writeAsStringSync('$line\n', mode: FileMode.append, flush: false);
    } catch (_) {}
  }

  static void info(String event, [Map<String, Object?>? fields]) => _write(_format('정보', event, fields));
  static void warn(String event, [Map<String, Object?>? fields]) => _write(_format('주의', event, fields));
  static void error(String event, Object error, [StackTrace? st]) {
    final where = st?.toString().split('\n').take(6).join(' | ') ?? '';
    _write(_format('오류', event, {'type': error.runtimeType, 'detail': error.toString(), 'at': where}));
  }

  static List<String> recent() => List.unmodifiable(_memory);

  static Future<String> readAll() async {
    try {
      if (_file != null && await _file!.exists()) return await _file!.readAsString();
    } catch (_) {}
    return _memory.join('\n');
  }
}
