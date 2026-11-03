import '../models/models.dart';

/// 검색 조건.
class SearchQuery {
  final List<String> keywords;
  final DateTime? from;
  final DateTime? to;
  final AiSource? source;
  final bool exact;
  final bool similar;
  final String? dateLabel;
  final String raw;

  const SearchQuery({
    this.keywords = const [],
    this.from,
    this.to,
    this.source,
    this.exact = false,
    this.similar = false,
    this.dateLabel,
    this.raw = '',
  });

  bool get isEmpty => keywords.isEmpty && from == null && to == null && source == null;

  SearchQuery copyWith({bool? exact, bool? similar, AiSource? source, bool clearSource = false}) => SearchQuery(
    keywords: keywords,
    from: from,
    to: to,
    source: clearSource ? null : (source ?? this.source),
    exact: exact ?? this.exact,
    similar: similar ?? this.similar,
    dateLabel: dateLabel,
    raw: raw,
  );
}

/// "지난달에 유튜브 앱 얘기한 대화 찾아줘" 같은 말을 검색 조건으로 바꿉니다.
class QueryParser {
  static final _sourceWords = <AiSource, List<String>>{
    AiSource.claude: ['클로드', 'claude', '클라우드'],
    AiSource.chatgpt: ['챗지피티', '챗gpt', 'chatgpt', '지피티', 'gpt', '챗 지피티', '오픈ai'],
    AiSource.gemini: ['제미나이', '제미니', 'gemini', '바드', 'bard'],
  };

  // 뒤에서부터 지울 말(길이가 긴 것 먼저)
  static final _fillers = <String>[
    '찾아주세요',
    '찾아 주세요',
    '찾아줘요',
    '찾아 줘요',
    '찾아줘',
    '찾아 줘',
    '찾아봐',
    '찾아 봐',
    '찾아',
    '보여주세요',
    '보여 주세요',
    '보여줘',
    '보여 줘',
    '검색해줘',
    '검색해 줘',
    '검색해',
    '검색',
    '알려줘',
    '알려 줘',
    '있었던',
    '있던',
    '이야기했던',
    '이야기한',
    '이야기',
    '얘기했던',
    '얘기한',
    '얘기',
    '말했던',
    '말한',
    '나눈',
    '나눴던',
    '했던',
    '물어본',
    '물어봤던',
    '대화들',
    '대화를',
    '대화',
    '기록',
    '내용',
    '관련된',
    '관련',
    '에 대한',
    '에대한',
    '에 관한',
    '거',
    '것',
    '좀',
    '내가',
    '제가',
    '혹시',
    '에서',
    '에게',
    '한테',
  ];

  static const _particles = ['에서', '으로', '에게', '한테', '이랑', '하고', '은', '는', '이', '가', '을', '를', '에', '의', '로', '와', '과', '랑', '도'];

  static SearchQuery parse(String input, {DateTime? now, bool exact = false, bool similar = false}) {
    final n = now ?? DateTime.now();
    var text = ' ${input.trim()} ';
    DateTime? from;
    DateTime? to;
    String? label;

    void range(DateTime a, DateTime b, String l) {
      from = a;
      to = b;
      label = l;
    }

    final today = DateTime(n.year, n.month, n.day);
    final rules = <(RegExp, void Function(Match))>[
      (
        RegExp(r'최근\s*(\d+)\s*일'),
        (m) => range(today.subtract(Duration(days: int.parse(m[1]!) - 1)), today.add(const Duration(days: 1)), '최근 ${m[1]}일'),
      ),
      (
        RegExp(r'(?:최근|지난)\s*(\d+)\s*(?:개월|달)'),
        (m) => range(DateTime(n.year, n.month - int.parse(m[1]!), n.day), today.add(const Duration(days: 1)), '최근 ${m[1]}개월'),
      ),
      (
        RegExp(r'(\d{4})\s*년\s*(\d{1,2})\s*월'),
        (m) {
          final y = int.parse(m[1]!), mo = int.parse(m[2]!);
          range(DateTime(y, mo), DateTime(y, mo + 1), '$y년 $mo월');
        },
      ),
      (
        RegExp(r'(\d{4})\s*년'),
        (m) {
          final y = int.parse(m[1]!);
          range(DateTime(y), DateTime(y + 1), '$y년');
        },
      ),
      (
        RegExp(r'(?<!\d)(\d{1,2})\s*월'),
        (m) {
          final mo = int.parse(m[1]!);
          if (mo < 1 || mo > 12) return;
          var y = n.year;
          if (mo > n.month) y -= 1; // 앞으로 올 달이면 작년
          range(DateTime(y, mo), DateTime(y, mo + 1), '$y년 $mo월');
        },
      ),
      (RegExp(r'그저께|그제'), (_) => range(today.subtract(const Duration(days: 2)), today.subtract(const Duration(days: 1)), '그저께')),
      (RegExp(r'어제'), (_) => range(today.subtract(const Duration(days: 1)), today, '어제')),
      (RegExp(r'오늘'), (_) => range(today, today.add(const Duration(days: 1)), '오늘')),
      (
        RegExp(r'지지난\s*주'),
        (_) {
          final start = today.subtract(Duration(days: today.weekday - 1 + 14));
          range(start, start.add(const Duration(days: 7)), '지지난주');
        },
      ),
      (
        RegExp(r'지난\s*주|저번\s*주'),
        (_) {
          final start = today.subtract(Duration(days: today.weekday - 1 + 7));
          range(start, start.add(const Duration(days: 7)), '지난주');
        },
      ),
      (
        RegExp(r'이번\s*주'),
        (_) {
          final start = today.subtract(Duration(days: today.weekday - 1));
          range(start, start.add(const Duration(days: 7)), '이번 주');
        },
      ),
      (RegExp(r'지지난\s*달'), (_) => range(DateTime(n.year, n.month - 2), DateTime(n.year, n.month - 1), '지지난달')),
      (RegExp(r'지난\s*달|저번\s*달|전\s*달'), (_) => range(DateTime(n.year, n.month - 1), DateTime(n.year, n.month), '지난달')),
      (RegExp(r'이번\s*달|이달'), (_) => range(DateTime(n.year, n.month), DateTime(n.year, n.month + 1), '이번 달')),
      (RegExp(r'재작년'), (_) => range(DateTime(n.year - 2), DateTime(n.year - 1), '재작년')),
      (RegExp(r'작년|지난\s*해'), (_) => range(DateTime(n.year - 1), DateTime(n.year), '작년')),
      (RegExp(r'올해|금년'), (_) => range(DateTime(n.year), DateTime(n.year + 1), '올해')),
    ];
    for (final (re, apply) in rules) {
      final m = re.firstMatch(text);
      if (m != null) {
        apply(m);
        if (label != null) {
          text = text.replaceRange(m.start, m.end, ' ');
          break;
        }
      }
    }
    // 날짜 뒤 조사 "에", "에서" 정리
    text = text.replaceAll(RegExp(r'\s(에|에서|부터|까지)\s'), ' ');

    AiSource? source;
    final lower = text.toLowerCase();
    outer:
    for (final e in _sourceWords.entries) {
      for (final w in e.value) {
        final idx = lower.indexOf(w);
        if (idx >= 0) {
          source = e.key;
          text = '${text.substring(0, idx)} ${text.substring(idx + w.length)}';
          break outer;
        }
      }
    }

    final words = <String>[];
    for (var w in text.split(RegExp(r'[\s,.?!~]+'))) {
      w = w.trim();
      if (w.isEmpty) continue;
      if (exact) {
        // 정확히 일치: 적은 그대로 찾음(조사도 떼지 않음)
        words.add(w);
        continue;
      }
      w = _stripFillers(w);
      if (w.isEmpty) continue;
      w = _stripParticle(w);
      if (w.isEmpty || _fillers.contains(w)) continue;
      words.add(w);
    }
    // 두 낱말로 된 채움말("찾아 줘") 처리
    final cleaned = <String>[];
    for (final w in words) {
      if (exact) {
        cleaned.add(w);
        continue;
      }
      if (const ['줘', '주세요', '줘요', '봐', '해', '해줘', '해주세요', '에서', '에'].contains(w)) continue;
      cleaned.add(w);
    }
    return SearchQuery(keywords: cleaned, from: from, to: to, source: source, exact: exact, similar: similar, dateLabel: label, raw: input);
  }

  static String _stripFillers(String w) {
    for (final f in _fillers) {
      if (w == f) return '';
    }
    // 낱말 끝에 붙은 채움말 ("얘기한대화" 같은 경우는 드묾) — "대화를" 등
    for (final f in const ['대화를', '대화', '얘기한', '이야기한']) {
      if (w.endsWith(f) && w.length > f.length + 1) return w.substring(0, w.length - f.length);
    }
    return w;
  }

  static String _stripParticle(String w) {
    if (w.runes.length <= 2) {
      // "앱을" → "앱", "글" 처럼 짧은 낱말은 1글자 조사만
      for (final p in const ['을', '를', '은', '는', '이', '가', '에', '의', '로', '도']) {
        if (w.runes.length == 2 && w.endsWith(p)) return w.substring(0, w.length - p.length);
      }
      return w;
    }
    for (final p in _particles) {
      if (w.endsWith(p) && w.length - p.length >= 2) return w.substring(0, w.length - p.length);
    }
    return w;
  }
}
