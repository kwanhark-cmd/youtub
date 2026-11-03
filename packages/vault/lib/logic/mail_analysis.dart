import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/models.dart';
import 'services_catalog.dart';
import 'voice_assistant.dart' show parseKoreanDate;

/// 메일에서 찾아낸 등록 제안. 사용자가 확인해야 실제로 저장된다.
class MailSuggestion {
  MailSuggestion({
    required this.kind,
    required this.serviceName,
    this.amount,
    this.currency = Currency.krw,
    this.cycle = BillingCycle.monthly,
    this.date,
    this.cardLast4,
    this.creditText = '',
    this.source = 'rules',
  });

  /// 'subscription' 또는 'credit'
  final String kind;
  final String serviceName;
  final int? amount;
  final Currency currency;
  final BillingCycle cycle;

  /// 구독이면 결제(갱신)일, 크레딧이면 만료일.
  final DateTime? date;
  final String? cardLast4;
  final String creditText;
  final String source;

  bool get isCredit => kind == 'credit';
}

/// 카드 번호처럼 보이는 긴 숫자(12자리 이상)를 가린다. 분석·AI 전송 전에 항상 호출.
String maskSensitive(String text) => text
    .replaceAllMapped(RegExp(r'\d(?:[ \-]?\d){11,18}'), (m) {
      final digits = m[0]!.replaceAll(RegExp(r'\D'), '');
      return '****${digits.substring(digits.length - 4)}';
    })
    .replaceAll(RegExp(r'sk-ant-[A-Za-z0-9_\-]+'), '[가림]');

/// 메일 본문에서 필요한 부분만 잘라 낸다(인용·서명·광고 줄 제외, 최대 3000자).
String extractRelevant(String text) {
  final lines = maskSensitive(text)
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('>'))
      .toList();
  final keep = <String>[];
  final pattern = RegExp(
    r'(결제|영수증|청구|금액|합계|총|카드|갱신|구독|만료|크레딧|체험|플랜|요금|'
    r'receipt|invoice|total|amount|paid|charged|card|renew|subscription|plan|expire|credit|trial|\$|₩|원|usd|krw)',
    caseSensitive: false,
  );
  for (var i = 0; i < lines.length; i++) {
    if (i < 3 || pattern.hasMatch(lines[i])) keep.add(lines[i]);
  }
  final joined = keep.join('\n');
  return joined.length > 3000 ? joined.substring(0, 3000) : joined;
}

/// 규칙 기반 분석(인터넷·AI 없이). 실패하면 null → 수동 입력 안내.
MailSuggestion? analyzeWithRules(
  String subject,
  String from,
  String body,
  DateTime now,
) {
  final text = maskSensitive('$subject\n$from\n$body');
  final service = _detectService(text);
  if (service == null) return null;
  final isCredit = RegExp(
    r'(크레딧|credit|체험|trial|무료 이용|보너스).{0,40}(만료|소멸|expire|end)|'
    r'(만료|소멸|expire|ends?).{0,40}(크레딧|credit|체험|trial)',
    caseSensitive: false,
  ).hasMatch(text);

  final card = RegExp(
    r'(?:\*{2,}|x{2,}|끝자리|ending in|ends in|•{2,})\s*(\d{4})',
    caseSensitive: false,
  ).firstMatch(text);

  DateTime? date = _findEnglishDate(text) ?? parseKoreanDate(text, now);

  if (isCredit) {
    final amount = RegExp(
      r'([\d,]+)\s*(크레딧|credits?)',
      caseSensitive: false,
    ).firstMatch(text);
    return MailSuggestion(
      kind: 'credit',
      serviceName: service,
      date: date,
      creditText: amount == null ? '' : '${amount[1]} 크레딧',
    );
  }

  int? amount;
  var currency = Currency.krw;
  final usd = RegExp(
    r'(?:\$|USD\s?)\s?(\d{1,4}(?:[.,]\d{2})?)',
    caseSensitive: false,
  ).firstMatch(text);
  final krw = RegExp(r'(?:₩\s?([\d,]{3,9}))|(?:([\d,]{3,9})\s?원)')
      .firstMatch(text);
  if (krw != null) {
    amount = int.tryParse((krw[1] ?? krw[2]!).replaceAll(',', ''));
  } else if (usd != null) {
    currency = Currency.usd;
    amount = (double.parse(usd[1]!.replaceAll(',', '.')) * 100).round();
  }
  if (amount == null) return null;
  final yearly = RegExp(
    r'(연간|1년|annual|yearly|/yr|per year)',
    caseSensitive: false,
  ).hasMatch(text);
  return MailSuggestion(
    kind: 'subscription',
    serviceName: service,
    amount: amount,
    currency: currency,
    cycle: yearly ? BillingCycle.yearly : BillingCycle.monthly,
    date: date,
    cardLast4: card?[1],
  );
}

String? _detectService(String text) {
  final n = normalizeName(text);
  for (final s in knownServices) {
    for (final a in s.names) {
      final na = normalizeName(a);
      if (na.length >= 4 && n.contains(na)) return s.displayName;
    }
  }
  for (final s in knownServices) {
    for (final a in s.names) {
      final na = normalizeName(a);
      if (na.length >= 2 &&
          na.length < 4 &&
          n.contains(na) &&
          !RegExp(r'^[a-z]+$').hasMatch(na)) {
        return s.displayName;
      }
    }
  }
  return null;
}

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

DateTime? _findEnglishDate(String text) {
  final m = RegExp(
    r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})',
    caseSensitive: false,
  ).firstMatch(text);
  if (m == null) return null;
  final mon = _months[m[1]!.toLowerCase()]!;
  return DateTime(int.parse(m[3]!), mon, int.parse(m[2]!));
}

/// AI 분석 제공자. 나중에 다른 회사로 바꿀 수 있도록 창구를 둔다.
abstract class MailAiProvider {
  /// 예상 비용(원) — 요청 전에 월 한도와 비교한다.
  double estimateCostWon(String text);
  Future<(MailSuggestion?, double)> analyze(String relevantText, DateTime now);
}

class AiLimitExceeded implements Exception {
  const AiLimitExceeded();
}

class AiRequestFailed implements Exception {
  const AiRequestFailed(this.message);
  final String message;
}

/// Claude API(Messages API)를 HTTP 로 직접 부른다(Dart 공식 SDK 없음).
class ClaudeMailAnalyzer implements MailAiProvider {
  ClaudeMailAnalyzer({
    required this.apiKey,
    required this.model,
    this.usdToKrw = 1400,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final int usdToKrw;
  final http.Client _client;

  /// 1백만 토큰당 달러(입력, 출력). 2026-10 기준.
  static const prices = {
    'claude-opus-5-5': (4.0, 20.0),
    'claude-sonnet-5-5': (2.0, 10.0),
    'claude-haiku-5-5': (0.10, 0.50),
  };

  static const models = {
    'claude-opus-5-5': 'Claude Opus 5.5 (가장 정확, 기본값)',
    'claude-sonnet-5-5': 'Claude Sonnet 5.5 (중간)',
    'claude-haiku-5-5': 'Claude Haiku 5.5 (가장 저렴)',
  };

  (double, double) get _price => prices[model] ?? prices['claude-opus-5-5']!;

  double _won(int inTok, int outTok) =>
      (inTok * _price.$1 + outTok * _price.$2) / 1e6 * usdToKrw;

  @override
  double estimateCostWon(String text) {
    // 한국어는 대략 글자 1개 ≈ 토큰 1개로 넉넉하게 잡는다. 지시문 약 600 토큰, 답 약 1500 토큰(생각 포함).
    return _won(text.length + 600, 1500);
  }

  static const _schema = {
    'type': 'object',
    'additionalProperties': false,
    'required': [
      'found',
      'kind',
      'service_name',
      'amount',
      'currency',
      'cycle',
      'date',
      'card_last4',
      'credit_text',
    ],
    'properties': {
      'found': {'type': 'boolean'},
      'kind': {
        'type': 'string',
        'enum': ['subscription', 'credit'],
      },
      'service_name': {'type': 'string'},
      'amount': {'type': 'number'},
      'currency': {
        'type': 'string',
        'enum': ['KRW', 'USD'],
      },
      'cycle': {
        'type': 'string',
        'enum': ['weekly', 'monthly', 'yearly'],
      },
      'date': {'type': 'string', 'description': 'YYYY-MM-DD 또는 빈 문자열'},
      'card_last4': {'type': 'string', 'description': '숫자 4자리 또는 빈 문자열'},
      'credit_text': {'type': 'string'},
    },
  };

  @override
  Future<(MailSuggestion?, double)> analyze(
    String relevantText,
    DateTime now,
  ) async {
    final body = {
      'model': model,
      'max_tokens': 2000,
      'output_config': {
        'effort': 'low',
        'format': {'type': 'json_schema', 'schema': _schema},
      },
      'fallbacks': 'default',
      'system':
          '너는 결제 영수증·크레딧 안내 메일에서 정보를 뽑는 도우미다. 오늘은 ${now.toIso8601String().substring(0, 10)}이다. '
          '구독 결제면 kind=subscription, 무료·보너스 크레딧이나 체험판 만료 안내면 kind=credit. '
          'date 는 구독이면 다음 결제일(없으면 결제일), 크레딧이면 만료일. '
          '금액은 USD 면 달러 단위 소수, KRW 면 원 단위 정수. 카드 번호 전체는 절대 쓰지 말고 끝 4자리만. '
          '결제·크레딧 메일이 아니면 found=false.',
      'messages': [
        {'role': 'user', 'content': '다음 메일 내용(일부)을 분석해 줘:\n\n$relevantText'},
      ],
    };
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'content-type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2026-10-21',
              'anthropic-beta': 'server-side-fallback-2026-07-01',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      throw const AiRequestFailed('인터넷 연결을 확인해 주세요.');
    }
    if (res.statusCode == 401) {
      throw const AiRequestFailed('AI 연결 키가 맞지 않아요. 설정에서 다시 넣어 주세요.');
    }
    if (res.statusCode == 429) {
      throw const AiRequestFailed('AI 사용량이 많아 잠시 뒤 다시 시도해 주세요.');
    }
    if (res.statusCode != 200) {
      throw AiRequestFailed('AI 분석에 실패했어요(코드 ${res.statusCode}).');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final usage = (j['usage'] as Map?) ?? {};
    final cost = _won(
      (usage['input_tokens'] as num?)?.toInt() ?? 0,
      (usage['output_tokens'] as num?)?.toInt() ?? 0,
    );
    if (j['stop_reason'] == 'refusal') return (null, cost);
    final texts = (j['content'] as List? ?? [])
        .whereType<Map>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join();
    try {
      final o = jsonDecode(texts) as Map<String, dynamic>;
      return (suggestionFromAiJson(o), cost);
    } catch (_) {
      return (null, cost);
    }
  }
}

MailSuggestion? suggestionFromAiJson(Map<String, dynamic> o) {
  if (o['found'] != true) return null;
  final name = (o['service_name'] as String? ?? '').trim();
  if (name.isEmpty) return null;
  final known = findKnownService(name);
  final usd = o['currency'] == 'USD';
  final amt = (o['amount'] as num?) ?? 0;
  return MailSuggestion(
    kind: o['kind'] == 'credit' ? 'credit' : 'subscription',
    serviceName: known?.displayName ?? name,
    amount: usd ? (amt * 100).round() : amt.round(),
    currency: usd ? Currency.usd : Currency.krw,
    cycle: BillingCycle.parse(o['cycle']),
    date: DateTime.tryParse((o['date'] as String?) ?? ''),
    cardLast4: sanitizeCardLast4(o['card_last4'] as String?),
    creditText: (o['credit_text'] as String?) ?? '',
    source: 'ai',
  );
}
