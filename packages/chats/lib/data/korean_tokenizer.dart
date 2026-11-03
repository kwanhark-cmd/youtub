/// 한글 검색용 색인 글자 만들기.
/// 한글은 2글자 조각(바이그램)과 1글자로, 영어·숫자는 단어로 나눕니다.
class KoreanTokenizer {
  static final _wordSplit = RegExp(r'[^0-9A-Za-zÀ-ɏ가-힣ㄱ-ㆎ]+');
  static final _hangulRun = RegExp(r'[가-힣ㄱ-ㆎ]+|[^가-힣ㄱ-ㆎ]+');

  static bool isHangul(int rune) => (rune >= 0xAC00 && rune <= 0xD7A3) || (rune >= 0x3131 && rune <= 0x318E);

  static List<String> words(String text) => text.toLowerCase().split(_wordSplit).where((w) => w.isNotEmpty).toList();

  /// 2글자 조각 색인(문장 순서 유지 → 구절 검색 가능).
  static String bigramIndex(String text) {
    final out = StringBuffer();
    for (final w in words(text)) {
      for (final m in _hangulRun.allMatches(w)) {
        final part = m.group(0)!;
        if (isHangul(part.runes.first)) {
          final r = part.runes.toList();
          if (r.length == 1) {
            out
              ..write(String.fromCharCode(r[0]))
              ..write(' ');
          } else {
            for (var i = 0; i < r.length - 1; i++) {
              out
                ..write(String.fromCharCodes([r[i], r[i + 1]]))
                ..write(' ');
            }
          }
        } else {
          out
            ..write(part)
            ..write(' ');
        }
      }
      out.write('| '); // 단어 경계(색인에서는 무시되는 기호)
    }
    return out.toString();
  }

  /// 1글자 색인(한 글자 검색용, 중복 없이).
  static String unigramIndex(String text) {
    final set = <int>{};
    for (final r in text.runes) {
      if (isHangul(r)) set.add(r);
    }
    return set.map(String.fromCharCode).join(' ');
  }

  /// 검색어 한 낱말을 FTS5 검색식으로 바꿉니다.
  static String termQuery(String term) {
    final t = term.toLowerCase().trim();
    if (t.isEmpty) return '';
    final pieces = <String>[];
    for (final m in _hangulRun.allMatches(t)) {
      final part = m.group(0)!;
      if (isHangul(part.runes.first)) {
        final r = part.runes.toList();
        if (r.length == 1) {
          pieces.add('__U__${String.fromCharCode(r[0])}');
        } else {
          for (var i = 0; i < r.length - 1; i++) {
            pieces.add(String.fromCharCodes([r[i], r[i + 1]]));
          }
        }
      } else {
        for (final w in words(part)) {
          pieces.add('$w*');
        }
      }
    }
    if (pieces.isEmpty) return '';
    if (pieces.length == 1 && pieces.first.startsWith('__U__')) {
      return 'u : "${pieces.first.substring(5)}"';
    }
    final grams = pieces.where((p) => !p.startsWith('__U__')).toList();
    final uni = pieces.where((p) => p.startsWith('__U__')).map((p) => p.substring(5)).toList();
    final parts = <String>[];
    // 한글 조각과 영어 단어를 섞은 구절: 영어 접두 검색은 구절 안에서 쓸 수 없어 따로 AND
    final hangulGrams = grams.where((g) => !g.endsWith('*')).toList();
    final latin = grams.where((g) => g.endsWith('*')).toList();
    if (hangulGrams.isNotEmpty) {
      parts.add('{t b} : "${hangulGrams.join(' ')}"');
    }
    for (final l in latin) {
      parts.add('{t b} : ${_quoteLatin(l)}');
    }
    for (final u in uni) {
      parts.add('u : "$u"');
    }
    return parts.length == 1 ? parts.first : '(${parts.join(' AND ')})';
  }

  static String _quoteLatin(String w) {
    final base = w.substring(0, w.length - 1).replaceAll('"', '');
    return '"$base"*';
  }
}
