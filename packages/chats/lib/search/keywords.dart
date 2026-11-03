import '../data/korean_tokenizer.dart';

/// 글에서 자주 나온 중요한 낱말을 뽑습니다(분류·추천·수정 기억에 사용).
class KeywordExtractor {
  static const _stop = {
    '그리고',
    '그래서',
    '하지만',
    '그러면',
    '이렇게',
    '저렇게',
    '그렇게',
    '정말',
    '너무',
    '조금',
    '아주',
    '많이',
    '어떻게',
    '무엇',
    '어떤',
    '있어요',
    '있습니다',
    '합니다',
    '해요',
    '해주세요',
    '주세요',
    '알려',
    '추천',
    '추천해',
    '좋아요',
    '네',
    '감사합니다',
    '고마워',
    '수',
    '것',
    '거',
    '등',
    '때',
    '더',
    '저',
    '제',
    '나',
    '내',
    '우리',
    '이',
    '그',
    '저희',
    '하는',
    '하고',
    '해서',
    '하면',
    '했어요',
    '할게요',
    '먼저',
    '다음',
    '마지막',
    '하기로',
    '정했어요',
    '같아요',
    '있는',
    '없는',
    '위해',
    '대한',
    '통해',
    '그다음',
    '좋은',
    '써',
    '줘',
    '보세요',
    'the',
    'and',
    'for',
    'you',
    'that',
    'this',
    'with',
    'are',
    'can',
  };
  static const _endings = [
    '에서',
    '으로',
    '에게',
    '하고',
    '이랑',
    '처럼',
    '까지',
    '부터',
    '보다',
    '은',
    '는',
    '이',
    '가',
    '을',
    '를',
    '에',
    '의',
    '로',
    '와',
    '과',
    '도',
    '만',
  ];

  static String normalizeWord(String w) {
    var s = w.toLowerCase();
    for (final e in _endings) {
      if (s.endsWith(e) && s.runes.length - e.runes.length >= 2) {
        s = s.substring(0, s.length - e.length);
        break;
      }
    }
    return s;
  }

  static List<String> top(String text, {int count = 8}) {
    final freq = <String, int>{};
    for (final raw in KoreanTokenizer.words(text)) {
      final w = normalizeWord(raw);
      final isHangul = KoreanTokenizer.isHangul(w.runes.first);
      if (isHangul && w.runes.length < 2) continue;
      if (!isHangul && (w.length < 3 || RegExp(r'^\d+$').hasMatch(w))) continue;
      if (_stop.contains(w)) continue;
      freq[w] = (freq[w] ?? 0) + 1;
    }
    final list = freq.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
    return list.take(count).map((e) => e.key).toList();
  }
}
