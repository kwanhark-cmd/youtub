import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/app_log.dart';

/// 외부 AI로 보낼 범위(사용자 동의).
enum ShareScope { titlesOnly, partial, full }

extension ShareScopeInfo on ShareScope {
  String get label => switch (this) {
    ShareScope.titlesOnly => '제목만',
    ShareScope.partial => '요약에 필요한 일부(대화마다 앞부분 약 600자)',
    ShareScope.full => '대화 전체(대화마다 최대 8,000자)',
  };
  int get charLimit => switch (this) {
    ShareScope.titlesOnly => 0,
    ShareScope.partial => 600,
    ShareScope.full => 8000,
  };
}

enum AiErrorKind { noKey, badKey, noCredit, rateLimited, overloaded, network, timeout, refused, budget, unknown }

class AiError implements Exception {
  final AiErrorKind kind;
  const AiError(this.kind);

  /// 사용자에게 보여줄 쉬운 안내.
  String get message => switch (kind) {
    AiErrorKind.noKey => 'AI 연결 키가 아직 없어요. 설정 > AI 연결에서 넣어 주세요.',
    AiErrorKind.badKey => 'AI 연결 키가 맞지 않거나 만료됐어요. 새 키를 넣어 주세요.',
    AiErrorKind.noCredit => 'AI 사용 잔액이 부족해요. 클로드 콘솔에서 결제 정보를 확인해 주세요.',
    AiErrorKind.rateLimited => '잠깐 사이에 너무 많이 요청했어요. 1~2분 뒤에 다시 해 주세요.',
    AiErrorKind.overloaded => 'AI 서버가 바빠요. 잠시 뒤에 다시 해 주세요.',
    AiErrorKind.network => '인터넷에 연결되어 있지 않아요. 검색은 인터넷 없이도 쓸 수 있어요.',
    AiErrorKind.timeout => 'AI 응답이 너무 늦어요. 잠시 뒤에 다시 해 주세요.',
    AiErrorKind.refused => 'AI가 이 내용은 처리하지 않았어요. 해당 대화는 건너뛰었어요.',
    AiErrorKind.budget => '이번 달 비용 한도에 닿았어요. 설정에서 한도를 바꿀 수 있어요.',
    AiErrorKind.unknown => 'AI 작업 중 문제가 생겼어요. 설정 > 문제 신고로 알려 주세요.',
  };
  @override
  String toString() => 'AiError($kind)';
}

class AiUsage {
  final int inputTokens;
  final int outputTokens;
  const AiUsage(this.inputTokens, this.outputTokens);
}

class AiReply {
  final Map<String, dynamic> json;
  final AiUsage usage;
  final String model;
  const AiReply(this.json, this.usage, this.model);
}

class ModelPrice {
  final String id;
  final String label;
  final double inputPerMillion;
  final double outputPerMillion;
  const ModelPrice(this.id, this.label, this.inputPerMillion, this.outputPerMillion);

  double cost(int inTok, int outTok) => inTok / 1e6 * inputPerMillion + outTok / 1e6 * outputPerMillion;
}

/// AI 제공자 추상화. 다른 회사 AI로 바꾸려면 이 클래스를 구현하면 됩니다.
abstract class AiProvider {
  String get name;
  List<ModelPrice> get models;

  /// [schema]에 맞는 JSON을 돌려받습니다.
  Future<AiReply> askJson({
    required String model,
    required String system,
    required String user,
    required Map<String, dynamic> schema,
    int maxTokens = 4000,
  });
}

/// Claude API(공식 HTTP API) 연결.
class ClaudeProvider implements AiProvider {
  final String apiKey;
  final http.Client client;
  final Duration timeout;
  final int maxRetries;
  final Future<void> Function(Duration) sleep;

  ClaudeProvider({
    required this.apiKey,
    http.Client? client,
    this.timeout = const Duration(seconds: 90),
    this.maxRetries = 2,
    Future<void> Function(Duration)? sleep,
  }) : client = client ?? http.Client(),
       sleep = sleep ?? Future<void>.delayed;

  static const endpoint = 'https://api.anthropic.com/v1/messages';

  @override
  String get name => '클로드';

  // 가격: 백만 토큰당 달러(2026-10 기준). 바뀌면 여기만 고치면 됩니다.
  static const priceList = [
    ModelPrice('claude-opus-5-5', '가장 똑똑함(오퍼스 5.5)', 4.0, 20.0),
    ModelPrice('claude-sonnet-5-5', '균형(소네트 5.5)', 2.0, 10.0),
    ModelPrice('claude-haiku-5-5', '가장 저렴함(하이쿠 5.5)', 0.10, 0.50),
  ];
  static const defaultModel = 'claude-opus-5-5';

  @override
  List<ModelPrice> get models => priceList;

  static ModelPrice priceOf(String model) => priceList.firstWhere((p) => p.id == model, orElse: () => priceList.first);

  static bool _supportsFallback(String model) => model.startsWith('claude-opus-5') || model.startsWith('claude-sonnet-5-5');

  @override
  Future<AiReply> askJson({
    required String model,
    required String system,
    required String user,
    required Map<String, dynamic> schema,
    int maxTokens = 4000,
  }) async {
    if (apiKey.trim().isEmpty) throw const AiError(AiErrorKind.noKey);
    final body = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'system': system,
      'messages': [
        {'role': 'user', 'content': user},
      ],
      'output_config': {
        'effort': 'low',
        'format': {'type': 'json_schema', 'schema': schema},
      },
      if (_supportsFallback(model)) 'fallbacks': 'default',
    };
    final headers = {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2026-10-21',
      if (_supportsFallback(model)) 'anthropic-beta': 'server-side-fallback-2026-07-01',
    };
    var attempt = 0;
    while (true) {
      attempt++;
      http.Response res;
      try {
        res = await client.post(Uri.parse(endpoint), headers: headers, body: jsonEncode(body)).timeout(timeout);
      } on TimeoutException {
        if (attempt <= maxRetries) {
          await sleep(Duration(seconds: 2 * attempt));
          continue;
        }
        throw const AiError(AiErrorKind.timeout);
      } on SocketException {
        throw const AiError(AiErrorKind.network);
      } on http.ClientException {
        throw const AiError(AiErrorKind.network);
      }
      final code = res.statusCode;
      if (code == 200) return _parse(res.body, model);
      final kind = _classify(code, res.body);
      AppLog.warn('AI 요청 실패', {'status': code, 'kind': kind.name, 'attempt': attempt});
      final retryable = kind == AiErrorKind.overloaded || kind == AiErrorKind.rateLimited;
      if (retryable && attempt <= maxRetries) {
        final after = int.tryParse(res.headers['retry-after'] ?? '') ?? (2 * attempt);
        await sleep(Duration(seconds: after.clamp(1, 30)));
        continue;
      }
      throw AiError(kind);
    }
  }

  static AiErrorKind _classify(int code, String body) {
    String type = '';
    String msg = '';
    try {
      final j = jsonDecode(body);
      type = j['error']?['type']?.toString() ?? '';
      msg = j['error']?['message']?.toString().toLowerCase() ?? '';
    } catch (_) {}
    if (code == 401 || type == 'authentication_error') return AiErrorKind.badKey;
    if (code == 403 || type == 'permission_error') return AiErrorKind.badKey;
    if (code == 402 || msg.contains('credit balance') || msg.contains('billing')) return AiErrorKind.noCredit;
    if (code == 429 || type == 'rate_limit_error') return AiErrorKind.rateLimited;
    if (code == 529 || code >= 500 || type == 'overloaded_error') return AiErrorKind.overloaded;
    return AiErrorKind.unknown;
  }

  static AiReply _parse(String raw, String model) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final usage = j['usage'] as Map<String, dynamic>? ?? const {};
    final u = AiUsage((usage['input_tokens'] as num?)?.toInt() ?? 0, (usage['output_tokens'] as num?)?.toInt() ?? 0);
    if (j['stop_reason'] == 'refusal') throw const AiError(AiErrorKind.refused);
    final content = j['content'] as List? ?? const [];
    final text = content.whereType<Map>().where((b) => b['type'] == 'text').map((b) => b['text']?.toString() ?? '').join();
    try {
      final parsed = jsonDecode(text);
      if (parsed is Map<String, dynamic>) return AiReply(parsed, u, j['model']?.toString() ?? model);
    } catch (_) {}
    throw const AiError(AiErrorKind.unknown);
  }
}
