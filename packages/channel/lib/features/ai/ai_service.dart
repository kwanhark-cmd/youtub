import 'dart:convert';

import '../../core/db.dart';
import '../../core/failure.dart';
import '../../core/http_json.dart';
import '../../core/logger.dart';
import '../../core/secret_store.dart';
import '../settings/user_settings.dart';

class AiRequest {
  AiRequest({required this.task, required this.system, required this.prompt, this.maxTokens = 2000});
  final String task;
  final String system;
  final String prompt;
  final int maxTokens;
}

class AiReply {
  AiReply({required this.text, required this.model, required this.inputTokens, required this.outputTokens});
  final String text;
  final String model;
  final int inputTokens;
  final int outputTokens;
}

/// AI 제공자. 설정에서 다른 제공자로 바꿀 수 있게 이 틀만 지키면 된다.
abstract class AiProvider {
  String get id;
  Future<AiReply> complete(AiRequest r, {required String apiKey, required String model});
}

/// 모델별 가격 (100만 토큰당 달러). 2026-10 기준.
class AiPrice {
  const AiPrice(this.inputPerM, this.outputPerM);
  final double inputPerM;
  final double outputPerM;

  static const table = <String, AiPrice>{
    'claude-opus-5-5': AiPrice(4, 20),
    'claude-sonnet-5-5': AiPrice(2, 10),
    'claude-haiku-5-5': AiPrice(0.10, 0.50),
  };

  static AiPrice of(String model) => table[model] ?? const AiPrice(4, 20);

  double cost(int inTok, int outTok) => inTok / 1e6 * inputPerM + outTok / 1e6 * outputPerM;
}

const aiModelChoices = <String, String>{
  'claude-opus-5-5': 'Claude Opus 5.5 (가장 똑똑함, 기본)',
  'claude-sonnet-5-5': 'Claude Sonnet 5.5 (빠르고 저렴함)',
  'claude-haiku-5-5': 'Claude Haiku 5.5 (아주 저렴함)',
};

/// Claude API (Messages API, 직접 HTTP 호출).
class ClaudeProvider implements AiProvider {
  ClaudeProvider(this.http);
  final JsonHttp http;

  @override
  String get id => 'claude';

  @override
  Future<AiReply> complete(AiRequest r, {required String apiKey, required String model}) async {
    final useFallback = model == 'claude-opus-5-5' || model == 'claude-sonnet-5-5';
    final j = await http.send(
      'POST',
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2026-10-21',
        if (useFallback) 'anthropic-beta': 'server-side-fallback-2026-07-01',
      },
      body: {
        'model': model,
        'max_tokens': r.maxTokens,
        'system': r.system,
        'messages': [
          {'role': 'user', 'content': r.prompt},
        ],
        // 짧은 글쓰기 작업이라 생각을 적게 해서 비용을 줄인다.
        'output_config': {'effort': 'low'},
        if (useFallback) 'fallbacks': 'default',
      },
    );
    if (j['stop_reason'] == 'refusal') {
      throw AppFailure(FailureKind.invalidInput, 'refusal');
    }
    final blocks = (j['content'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final text = blocks.where((b) => b['type'] == 'text').map((b) => b['text'] as String).join();
    final usage = j['usage'] as Map<String, dynamic>? ?? const {};
    return AiReply(
      text: text,
      model: (j['model'] as String?) ?? model,
      inputTokens: (usage['input_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (usage['output_tokens'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 테스트용 가짜 제공자: 정해 둔 답을 돌려준다 (비용 계산 확인용).
class FakeAiProvider implements AiProvider {
  FakeAiProvider(this.reply);
  String Function(AiRequest r) reply;
  int calls = 0;

  @override
  String get id => 'fake';

  @override
  Future<AiReply> complete(AiRequest r, {required String apiKey, required String model}) async {
    calls++;
    final t = reply(r);
    return AiReply(text: t, model: model, inputTokens: (r.system.length + r.prompt.length), outputTokens: t.length);
  }
}

/// AI 사용 관리: 연습 모드 판단, 예상 비용, 이번 달 누적, 한도.
class AiService {
  AiService({
    required this.db,
    required this.settings,
    required this.secrets,
    required this.providers,
    required this.now,
    this.logger,
  });

  final AppDatabase db;
  final UserSettings settings;
  final UserSecrets secrets;
  final Map<String, AiProvider> providers;
  final DateTime Function() now;
  final AppLogger? logger;

  static const keyName = 'ai/apiKey';
  String? _cachedKey;
  bool _keyLoaded = false;

  Future<void> loadKey() async {
    _cachedKey = await secrets.read(keyName);
    _keyLoaded = true;
  }

  bool get hasKey => (_cachedKey ?? '').isNotEmpty;

  Future<void> setKey(String key) async {
    final k = key.trim();
    if (k.isEmpty) {
      await secrets.delete(keyName);
      _cachedKey = null;
    } else {
      await secrets.write(keyName, k);
      _cachedKey = k;
    }
    _keyLoaded = true;
  }

  double get monthCostUsd {
    final r = db.select('SELECT COALESCE(SUM(cost_usd), 0) AS s FROM ai_costs WHERE month = ?', [monthKey(now())]);
    return (r.first['s'] as num).toDouble();
  }

  bool get overLimit => monthCostUsd >= settings.monthlyCostLimitUsd;

  /// 키가 없거나, 한도를 넘었거나, 제공자가 없으면 연습 모드.
  bool get isPracticeMode => !_keyLoaded || !hasKey || overLimit || !providers.containsKey(settings.aiProvider);

  /// 예상 비용(달러). 한국어는 글자 1자 ≈ 토큰 1개로 넉넉하게 잡는다.
  double estimateCost(String system, String prompt, {int expectedOutput = 1200}) {
    final inTok = system.length + prompt.length;
    return AiPrice.of(settings.aiModel).cost(inTok, expectedOutput);
  }

  /// 실제 AI 호출. 연습 모드이면 [AppFailure] (costLimit 또는 notConnected).
  Future<AiReply> complete(AiRequest r) async {
    if (!_keyLoaded) await loadKey();
    if (!hasKey) throw AppFailure(FailureKind.notConnected, 'no ai key');
    final est = estimateCost(r.system, r.prompt, expectedOutput: r.maxTokens ~/ 2);
    if (monthCostUsd + est > settings.monthlyCostLimitUsd) {
      throw AppFailure(FailureKind.costLimit, 'monthly limit');
    }
    final provider = providers[settings.aiProvider];
    if (provider == null) throw AppFailure(FailureKind.notConnected, 'no provider');
    final reply = await provider.complete(r, apiKey: _cachedKey!, model: settings.aiModel);
    final cost = AiPrice.of(reply.model).cost(reply.inputTokens, reply.outputTokens);
    db.execute(
      'INSERT INTO ai_costs(month, at, task, model, input_tokens, output_tokens, cost_usd) VALUES(?,?,?,?,?,?,?)',
      [monthKey(now()), now().toIso8601String(), r.task, reply.model, reply.inputTokens, reply.outputTokens, cost],
    );
    logger?.info('AI 사용: ${r.task} \$${cost.toStringAsFixed(4)}');
    return reply;
  }
}

/// AI 답에서 JSON 부분만 꺼낸다.
Map<String, dynamic> extractJson(String text) {
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) throw const FormatException('no json');
  return jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
}
