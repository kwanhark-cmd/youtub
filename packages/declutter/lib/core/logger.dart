import 'dart:io';

/// 앱 로그. API 키·사진 데이터는 절대 기록하지 않습니다.
class AppLogger {
  static final AppLogger instance = AppLogger._();
  AppLogger._();

  final List<String> _memory = [];
  File? _file;
  static const int _maxMemory = 500;
  static const int _maxFileBytes = 512 * 1024;

  List<String> get recent => List.unmodifiable(_memory);

  Future<void> attachFile(File f) async {
    _file = f;
    try {
      if (await f.exists() && await f.length() > _maxFileBytes) {
        await f.writeAsString('');
      }
    } catch (_) {}
  }

  /// 민감 정보 지우기: API 키, 긴 base64(사진), 이메일, 비밀번호 표시
  static String redact(String input) {
    var s = input;
    s = s.replaceAll(RegExp(r'sk-ant-[A-Za-z0-9_\-]+'), '[키 숨김]');
    s = s.replaceAll(RegExp(r'(x-api-key|api[_-]?key|authorization|password|비밀번호)\s*[:=]\s*\S+', caseSensitive: false), r'$1: [숨김]');
    s = s.replaceAll(RegExp(r'[A-Za-z0-9+/=]{200,}'), '[긴 데이터 숨김]');
    s = s.replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'), '[이메일 숨김]');
    return s;
  }

  void info(String msg) => _write('정보', msg);
  void warn(String msg) => _write('주의', msg);
  void error(String msg, [Object? err, StackTrace? st]) {
    final buf = StringBuffer(msg);
    if (err != null) buf.write(' | $err');
    if (st != null) buf.write('\n${st.toString().split('\n').take(8).join('\n')}');
    _write('오류', buf.toString());
  }

  void _write(String level, String msg) {
    final line = '${DateTime.now().toIso8601String()} [$level] ${redact(msg)}';
    _memory.add(line);
    if (_memory.length > _maxMemory) _memory.removeAt(0);
    final f = _file;
    if (f != null) {
      try {
        f.writeAsStringSync('$line\n', mode: FileMode.append, flush: false);
      } catch (_) {}
    }
  }

  Future<String> exportText({required String appVersion, required String platform}) async {
    final buf = StringBuffer()
      ..writeln('집안 물건 비우기 판매 폐기 비서 — 문제 신고용 기록')
      ..writeln('앱 버전: $appVersion')
      ..writeln('기기: $platform')
      ..writeln('만든 시각: ${DateTime.now().toIso8601String()}')
      ..writeln('(사진과 AI 키는 기록에 들어 있지 않습니다)')
      ..writeln('----');
    final f = _file;
    if (f != null && await f.exists()) {
      buf.write(redact(await f.readAsString()));
    } else {
      buf.writeAll(_memory, '\n');
    }
    return buf.toString();
  }
}

final log = AppLogger.instance;
