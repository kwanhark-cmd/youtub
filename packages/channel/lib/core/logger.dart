import 'dart:io';

/// 비밀번호·토큰·키 같은 민감정보를 지운다.
/// 로그 파일, 문제 신고 파일, 화면 어디에도 민감정보가 나가지 않게 모든 기록은 이 함수를 거친다.
String redact(String input) {
  var s = input;
  final patterns = <RegExp>[
    // Authorization: Bearer xxx
    RegExp(r'(Bearer\s+)[A-Za-z0-9\-\._~\+\/]+=*', caseSensitive: false),
    // 구글 액세스 토큰 / 리프레시 토큰
    RegExp(r'ya29\.[A-Za-z0-9\-_\.]+'),
    RegExp(r'1//[A-Za-z0-9\-_]{10,}'),
    // Anthropic 키
    RegExp(r'sk-ant-[A-Za-z0-9\-_]+'),
    // 일반 sk- 키
    RegExp(r'sk-[A-Za-z0-9]{16,}'),
    // 구글 API 키
    RegExp(r'AIza[0-9A-Za-z\-_]{20,}'),
    // 구글 클라이언트 시크릿
    RegExp(r'GOCSPX-[A-Za-z0-9\-_]+'),
  ];
  for (final p in patterns) {
    s = s.replaceAllMapped(p, (m) {
      final prefix = (m.groupCount >= 1 && m.group(1) != null) ? m.group(1)! : '';
      return '$prefix[가림]';
    });
  }
  // key=value / "key": "value" 형태
  final kv = RegExp(
    r'''(["']?(?:access_token|refresh_token|id_token|client_secret|api[_-]?key|x-api-key|password|passwd|pin|token|secret|code_verifier|code)["']?\s*[:=]\s*["']?)([^"'&\s,}]+)''',
    caseSensitive: false,
  );
  s = s.replaceAllMapped(kv, (m) => '${m.group(1)}[가림]');
  // 이메일 주소 일부 가림
  s = s.replaceAllMapped(
    RegExp(r'([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*@([A-Za-z0-9.-]+\.[A-Za-z]{2,})'),
    (m) => '${m.group(1)}***@${m.group(2)}',
  );
  return s;
}

enum LogLevel { info, warn, error }

/// 기기 안 로그 파일. 파일이 커지면 앞부분을 잘라 낸다.
class AppLogger {
  AppLogger({this.file, this.maxBytes = 512 * 1024});

  final File? file;
  final int maxBytes;
  final List<String> _memory = [];

  List<String> get recentInMemory => List.unmodifiable(_memory);

  void info(String msg) => log(LogLevel.info, msg);
  void warn(String msg) => log(LogLevel.warn, msg);
  void error(String msg, [Object? err, StackTrace? st]) {
    final buf = StringBuffer(msg);
    if (err != null) buf.write(' | $err');
    if (st != null) {
      buf.write(' | ${st.toString().split('\n').take(8).join(' / ')}');
    }
    log(LogLevel.error, buf.toString());
  }

  void log(LogLevel level, String msg) {
    final line = '${DateTime.now().toIso8601String()} [${level.name}] ${redact(msg)}';
    _memory.add(line);
    if (_memory.length > 500) _memory.removeAt(0);
    final f = file;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('$line\n', mode: FileMode.append, flush: false);
      if (f.lengthSync() > maxBytes) {
        final lines = f.readAsLinesSync();
        f.writeAsStringSync('${lines.skip(lines.length ~/ 2).join('\n')}\n');
      }
    } catch (_) {
      // 로그 기록 실패로 앱이 멈추면 안 된다.
    }
  }

  /// 최근 로그 [lines] 줄 (민감정보 제거 상태).
  List<String> recentLines([int lines = 300]) {
    final f = file;
    try {
      if (f != null && f.existsSync()) {
        final all = f.readAsLinesSync();
        return all.skip(all.length > lines ? all.length - lines : 0).map(redact).toList();
      }
    } catch (_) {}
    final mem = _memory;
    return mem.skip(mem.length > lines ? mem.length - lines : 0).toList();
  }
}
