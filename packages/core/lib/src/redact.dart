/// 비밀번호·열쇠가 로그·검색 결과·음성에 절대 나가지 않게 가리는 도구.
class Redact {
  static final _patterns = <RegExp>[
    RegExp(r'(password|passwd|pw|비밀번호|암호|secret|token|api[_-]?key|열쇠|client_secret|refresh_token|access_token)\s*[:=]\s*\S+', caseSensitive: false),
    RegExp(r'sk-[A-Za-z0-9_\-]{8,}'),
    RegExp(r'AIza[0-9A-Za-z_\-]{20,}'),
    RegExp(r'ya29\.[0-9A-Za-z_\-]+'),
    RegExp(r'GOCSPX-[0-9A-Za-z_\-]+'),
    RegExp(r'Bearer\s+[A-Za-z0-9._\-]+', caseSensitive: false),
  ];

  /// 글에서 비밀 값을 [가림] 으로 바꾼다.
  static String text(String input) {
    var s = input;
    for (final p in _patterns) {
      s = s.replaceAllMapped(p, (m) {
        final g = m.group(0)!;
        final i = g.indexOf(RegExp(r'[:=]'));
        if (i > 0 && i < 40) return '${g.substring(0, i + 1)} [가림]';
        return '[가림]';
      });
    }
    return s;
  }

  /// 이 글에 비밀 값처럼 보이는 것이 들어 있는가.
  static bool looksSecret(String input) => text(input) != input;
}
