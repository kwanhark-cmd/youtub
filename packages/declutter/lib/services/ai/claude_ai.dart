import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import 'ai_provider.dart';

/// Claude API (사진 입력). Dart용 공식 SDK가 없어 HTTP로 직접 호출합니다.
class ClaudeAi implements AiProvider {
  static const model = 'claude-opus-5-5';
  static const endpoint = 'https://api.anthropic.com/v1/messages';
  static const apiVersion = '2026-10-21';

  final String apiKey;
  final http.Client client;
  final Duration timeout;

  ClaudeAi({required this.apiKey, http.Client? client, this.timeout = const Duration(seconds: 90)}) : client = client ?? http.Client();

  @override
  String get name => 'Claude';
  @override
  bool get isPractice => false;

  static const _system =
      '너는 한국의 집 정리 도우미다. 사용자가 집을 비우도록 돕는다. 분류는 반드시 세 가지 중 하나만 쓴다: '
      'use(지금 쓰는 것), sell(판매), discard(폐기). 보관이나 보류는 없다. 모든 글은 쉬운 한국어로 쓴다. '
      '가격은 한국 중고거래(당근마켓·번개장터) 기준 원 단위 정수로 추정한다.';

  static const _decision = {
    'type': 'string',
    'enum': ['use', 'sell', 'discard'],
  };

  static final _recognizeSchema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['items'],
    'properties': {
      'items': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['name', 'kind', 'condition', 'suggestion', 'reason'],
          'properties': {
            'name': {'type': 'string'},
            'kind': {'type': 'string'},
            'condition': {'type': 'string'},
            'suggestion': _decision,
            'reason': {'type': 'string'},
          },
        },
      },
    },
  };

  static final _suggestSchema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['decision', 'reason'],
    'properties': {
      'decision': _decision,
      'reason': {'type': 'string'},
    },
  };

  static final _listingSchema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['title', 'body', 'category', 'price_low', 'price_high'],
    'properties': {
      'title': {'type': 'string'},
      'body': {'type': 'string'},
      'category': {'type': 'string'},
      'price_low': {'type': 'integer'},
      'price_high': {'type': 'integer'},
    },
  };

  Map<String, Object?> _image(Uint8List jpeg) => {
    'type': 'image',
    'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': base64Encode(jpeg)},
  };

  Future<(Map<String, dynamic>, double)> _call(List<Map<String, Object?>> content, Map<String, Object?> schema) async {
    if (apiKey.trim().isEmpty) throw AiException(AiErrorKind.noKey);
    final body = jsonEncode({
      'model': model,
      'max_tokens': 4000,
      'system': _system,
      'fallbacks': 'default',
      'output_config': {
        'effort': 'low',
        'format': {'type': 'json_schema', 'schema': schema},
      },
      'messages': [
        {'role': 'user', 'content': content},
      ],
    });
    http.Response res;
    try {
      res = await client
          .post(
            Uri.parse(endpoint),
            headers: {
              'x-api-key': apiKey.trim(),
              'anthropic-version': apiVersion,
              'anthropic-beta': 'server-side-fallback-2026-07-01',
              'content-type': 'application/json',
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw AiException(AiErrorKind.timeout);
    } on SocketException catch (e) {
      throw AiException(AiErrorKind.network, e.message);
    } on http.ClientException catch (e) {
      throw AiException(AiErrorKind.network, e.message);
    }
    if (res.statusCode == 401 || res.statusCode == 403) throw AiException(AiErrorKind.badKey);
    if (res.statusCode == 429) throw AiException(AiErrorKind.server, '요청이 많음');
    if (res.statusCode >= 500 || res.statusCode == 529) throw AiException(AiErrorKind.server, '${res.statusCode}');
    if (res.statusCode != 200) throw AiException(AiErrorKind.server, '${res.statusCode}');
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw AiException(AiErrorKind.recognitionFailed);
    }
    final usage = (json['usage'] as Map?) ?? const {};
    final usd = AiPricing.usdFor(inputTokens: (usage['input_tokens'] as num?)?.toInt() ?? 0, outputTokens: (usage['output_tokens'] as num?)?.toInt() ?? 0);
    if (json['stop_reason'] == 'refusal') throw AiException(AiErrorKind.refused);
    final text = ((json['content'] as List?) ?? const []).whereType<Map>().where((b) => b['type'] == 'text').map((b) => b['text'] as String? ?? '').join();
    try {
      return (jsonDecode(text) as Map<String, dynamic>, usd);
    } catch (_) {
      throw AiException(AiErrorKind.recognitionFailed);
    }
  }

  static Decision? _d(Object? s) => DecisionInfo.parse(s as String?);

  @override
  Future<AiResult<List<DetectedItem>>> recognize(Uint8List jpeg, {int width = 0, int height = 0, String? hint}) async {
    final (j, usd) = await _call([
      _image(jpeg),
      {
        'type': 'text',
        'text':
            '이 사진에 보이는 물건을 하나씩 골라 목록으로 만들어 줘. 물건마다 이름, 종류, 보이는 상태, '
            '세 가지 분류 추천(use/sell/discard)과 짧은 이유를 적어 줘. 너무 작은 물건은 묶어서 하나로 적어도 돼.'
            '${hint == null || hint.isEmpty ? '' : ' 사용자 설명: "$hint"'}',
      },
    ], _recognizeSchema);
    final list = ((j['items'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (m) => DetectedItem(
            name: (m['name'] as String?)?.trim() ?? '',
            kind: (m['kind'] as String?) ?? '',
            condition: (m['condition'] as String?) ?? '',
            suggestion: _d(m['suggestion']),
            reason: (m['reason'] as String?) ?? '',
          ),
        )
        .where((d) => d.name.isNotEmpty)
        .toList();
    if (list.isEmpty) throw AiException(AiErrorKind.recognitionFailed);
    return AiResult(list, usd);
  }

  @override
  Future<AiResult<Suggestion>> suggest(Item item) async {
    final (j, usd) = await _call([
      {
        'type': 'text',
        'text':
            '물건: ${item.name}\n종류: ${item.kind}\n상태: ${item.condition}\n설명: ${item.description}\n사연: ${item.story}\n'
            '이 물건을 use/sell/discard 중 하나로 추천하고 이유를 한 문장으로 적어 줘.',
      },
    ], _suggestSchema);
    final d = _d(j['decision']) ?? Decision.sell;
    return AiResult(Suggestion(d, (j['reason'] as String?) ?? ''), usd);
  }

  @override
  Future<AiResult<ListingDraft>> writeListing(Item item, {Uint8List? jpeg, int width = 0, int height = 0}) async {
    final (j, usd) = await _call([
      if (jpeg != null) _image(jpeg),
      {
        'type': 'text',
        'text':
            '당근마켓·번개장터에 올릴 판매글을 써 줘. 물건: ${item.name}, 종류: ${item.kind}, 상태: ${item.condition}, '
            '설명: ${item.description}. 제목은 짧게, 본문은 상태·거래 방법을 쉽게. 카테고리 이름과 '
            '중고 시세 범위(price_low, price_high, 원)를 추정해 줘. 과장하지 마.',
      },
    ], _listingSchema);
    int p(Object? v) => roundTo1000((v as num?) ?? 0);
    final lo = p(j['price_low']);
    final hi = p(j['price_high']);
    return AiResult(
      ListingDraft(
        title: (j['title'] as String?) ?? item.name,
        body: (j['body'] as String?) ?? '',
        category: (j['category'] as String?) ?? '기타 중고물품',
        priceLow: lo <= hi ? lo : hi,
        priceHigh: lo <= hi ? hi : lo,
      ),
      usd,
    );
  }
}
