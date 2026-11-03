import 'dart:io';

/// 앱 기록(로그). 비밀번호·계정 정보·키는 절대 기록하지 않는다.
/// 기록 함수에는 "무슨 일이 있었는지"만 넘기고, 혹시 섞여 들어간 값은 [redact] 로 가린다.
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  final List<String> _buffer = [];
  File? _file;
  static const _maxLines = 600;

  Future<void> attachFile(File file) async {
    _file = file;
    try {
      if (file.existsSync() && file.lengthSync() > 512 * 1024) {
        final old = File('${file.path}.1');
        if (old.existsSync()) old.deleteSync();
        file.renameSync(old.path);
      }
    } catch (_) {}
  }

  void info(String event) => _write('INFO', event);
  void warn(String event) => _write('WARN', event);

  /// 오류는 종류와 (가려진) 메시지만 남긴다. 스택에는 값이 없으므로 앞부분만 남긴다.
  void error(String event, Object error, [StackTrace? st]) {
    final stack = st == null
        ? ''
        : '\n${st.toString().split('\n').take(8).join('\n')}';
    _write(
      'ERROR',
      '$event: ${error.runtimeType}: ${redact(error.toString())}$stack',
    );
  }

  void _write(String level, String msg) {
    final line = '${DateTime.now().toIso8601String()} [$level] ${redact(msg)}';
    _buffer.add(line);
    if (_buffer.length > _maxLines) {
      _buffer.removeRange(0, _buffer.length - _maxLines);
    }
    try {
      _file?.writeAsStringSync('$line\n', mode: FileMode.append, flush: false);
    } catch (_) {}
  }

  List<String> get lines => List.unmodifiable(_buffer);

  /// "문제 신고"용 묶음. 다시 한 번 가린다.
  Future<String> exportText({required String appVersion}) async {
    final buf = StringBuffer()
      ..writeln('로그인 계정과 구독 결제 관리 비서 — 문제 신고 기록')
      ..writeln('앱 버전: $appVersion')
      ..writeln(
        '운영체제: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      )
      ..writeln('만든 시각: ${DateTime.now().toIso8601String()}')
      ..writeln('※ 이 기록에는 비밀번호·계정 정보가 들어 있지 않습니다.')
      ..writeln('----');
    var text = '';
    try {
      final f = _file;
      if (f != null && f.existsSync()) text = await f.readAsString();
    } catch (_) {}
    if (text.isEmpty) text = _buffer.join('\n');
    buf.write(redact(text));
    return buf.toString();
  }

  void clearMemory() => _buffer.clear();
}

/// 비밀처럼 보이는 값을 가린다: 이메일, 긴 숫자, API 키, 토큰, key=value 의 값.
String redact(String s) => s
    .replaceAll(RegExp(r'sk-ant-[A-Za-z0-9_\-]+'), '[키]')
    .replaceAll(RegExp(r'ya29\.[A-Za-z0-9_\-.]+'), '[토큰]')
    .replaceAll(RegExp(r'1//[A-Za-z0-9_\-]+'), '[토큰]')
    .replaceAll(
      RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}'),
      '[이메일]',
    )
    .replaceAll(RegExp(r'\d[\d \-]{7,}\d'), '[숫자]')
    .replaceAllMapped(
      RegExp(
        r'(password|passwd|pwd|secret|token|api[_-]?key|비밀번호|암호|code|코드)(\s*[=:]\s*)(\S+)',
        caseSensitive: false,
      ),
      (m) => '${m[1]}${m[2]}[가림]',
    );

final log = AppLogger.instance;
