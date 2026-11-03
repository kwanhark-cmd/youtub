import '../search/keywords.dart';

class TopicRule {
  final String key;
  final String name;
  final List<String> words;
  const TopicRule(this.key, this.name, this.words);
}

/// 비용 없는 "검색만" 모드의 간단한 분류. 낱말 사전과 사용자가 고친 내용으로 점수를 매깁니다.
class KeywordClassifier {
  static const otherKey = 'other';
  static const otherName = '기타';

  static const rules = <TopicRule>[
    TopicRule('app', '앱 만들기', [
      '앱',
      '어플',
      '플러터',
      'flutter',
      '안드로이드',
      '아이폰',
      '개발',
      '코드',
      '코딩',
      '프로그램',
      '버그',
      '오류',
      'api',
      '앱스토어',
      '플레이스토어',
      '서버',
      '화면 설계',
      '기능',
    ]),
    TopicRule('video', '유튜브·영상', ['유튜브', '영상', '동영상', '채널', '썸네일', '편집', '쇼츠', '대본', '시나리오', '촬영', '내레이션', '자막', '장면', '구독']),
    TopicRule('invest', '투자·재테크', [
      '주식',
      '투자',
      '매수',
      '매도',
      '배당',
      'etf',
      '코인',
      '재테크',
      '분할',
      '수익률',
      '증권',
      '종목',
      '하락',
      '수익',
      '스플릿',
      '가계부',
      '저축',
      '금리',
    ]),
    TopicRule('writing', '글쓰기', ['블로그', '기사', '문장', '맞춤법', '번역', '작문', '소설', '에세이', '첫 문장', '글']),
    TopicRule('health', '건강·운동', ['건강', '운동', '병원', '다이어트', '식단', '약', '수면', '증상', '혈압', '무릎', '스트레칭', '걷기']),
    TopicRule('travel', '여행', ['여행', '항공', '호텔', '숙소', '관광', '비행기', '박', '일출', '공항', '해안']),
    TopicRule('food', '요리·음식', ['요리', '레시피', '음식', '반찬', '재료', '밥', '조리']),
    TopicRule('study', '공부·학습', ['공부', '시험', '영어', '학습', '강의', '자격증', '수학']),
    TopicRule('work', '업무·문서', ['회의', '보고서', '엑셀', '문서', '이메일', '발표', '제안서', '계약', '피벗', '표']),
    TopicRule('life', '생활·쇼핑', ['쇼핑', '구매', '가격', '이사', '청소', '가전', '집']),
    TopicRule('law', '법률·세금', ['세금', '법', '소송', '계약서', '연말정산', '신고', '변호사']),
    TopicRule('ai', 'AI 활용', ['프롬프트', '챗봇', '인공지능', '클로드', '제미나이', '챗gpt']),
  ];

  /// 결과: 사전 열쇠 목록(점수 높은 순, 최대 3개). 사용자 수정은 topicId로 따로 돌려줌.
  static ClassifyResult classify(String title, String body, {Map<String, List<(int, int)>> corrections = const {}}) {
    final t = title.toLowerCase();
    final b = body.toLowerCase();
    final scores = <String, double>{};
    for (final r in rules) {
      var s = 0.0;
      for (final w in r.words) {
        final wl = w.toLowerCase();
        if (wl.runes.length == 1) {
          // 한 글자 낱말은 낱말 단위로만 셈(오탐 방지)
          final re = RegExp('(^|[^가-힣])${RegExp.escape(wl)}(?=[^가-힣]|\$|을|를|이|가|은|는|도|으로|로)');
          s += 3 * re.allMatches(t).length + re.allMatches(b).length.clamp(0, 5);
        } else {
          s += 3 * _count(t, wl) + _count(b, wl).clamp(0, 5);
        }
      }
      if (s > 0) scores[r.key] = s;
    }
    final userScores = <int, double>{};
    if (corrections.isNotEmpty) {
      for (final w in KeywordExtractor.top('$title $body', count: 20)) {
        final hits = corrections[w];
        if (hits == null) continue;
        for (final (topicId, weight) in hits) {
          userScores[topicId] = (userScores[topicId] ?? 0) + 2.0 * weight;
        }
      }
    }
    final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final keys = <String>[];
    if (ranked.isNotEmpty) {
      final top = ranked.first.value;
      for (final e in ranked) {
        if (e.value >= 2 && e.value >= top * 0.5 && keys.length < 3) keys.add(e.key);
      }
    }
    final userTopics = (userScores.entries.where((e) => e.value >= 4).toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(2)
        .map((e) => e.key)
        .toList();
    if (keys.isEmpty && userTopics.isEmpty) keys.add(otherKey);
    return ClassifyResult(keys, userTopics);
  }

  static int _count(String text, String w) {
    var n = 0;
    var i = text.indexOf(w);
    while (i >= 0) {
      n++;
      i = text.indexOf(w, i + w.length);
    }
    return n;
  }

  static String nameFor(String key) =>
      key == otherKey ? otherName : rules.firstWhere((r) => r.key == key, orElse: () => const TopicRule('', '기타', [])).name;
}

class ClassifyResult {
  final List<String> ruleKeys;
  final List<int> learnedTopicIds;
  const ClassifyResult(this.ruleKeys, this.learnedTopicIds);
}
