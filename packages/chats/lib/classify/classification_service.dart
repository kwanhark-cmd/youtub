import 'dart:convert';

import '../core/app_log.dart';
import '../core/cancel_token.dart';
import '../data/conversation_store.dart';
import '../data/topic_store.dart';
import '../models/models.dart';
import '../search/keywords.dart';
import '../summary/summarizer.dart';
import 'ai_provider.dart';
import 'keyword_classifier.dart';

class CostEstimate {
  final int conversations;
  final int inputTokens;
  final int outputTokens;
  final double usd;
  const CostEstimate(this.conversations, this.inputTokens, this.outputTokens, this.usd);

  static const wonPerUsd = 1400;
  String get wonText {
    final won = (usd * wonPerUsd).ceil();
    return won < 10 ? '10원 미만' : '약 ${_comma(won)}원';
  }

  static String _comma(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

class ClassifyOutcome {
  int done = 0;
  int skippedUserSet = 0;
  int aiFailed = 0;
  AiError? stoppedBy;
  bool cancelled = false;
}

/// 주제 분류와 대화 요약.
class ClassificationService {
  final ConversationStore store;
  final TopicStore topics;
  ClassificationService(this.store, this.topics);

  // ---------- 키워드(무료) ----------

  Future<ClassifyOutcome> classifyOffline(List<int> ids, {void Function(int, int)? onProgress, CancelToken? cancel}) async {
    final out = ClassifyOutcome();
    final corrections = topics.corrections();
    for (var i = 0; i < ids.length; i++) {
      if (cancel?.isCancelled == true) {
        out.cancelled = true;
        break;
      }
      final id = ids[i];
      final c = store.get(id);
      if (c == null) continue;
      final msgs = await store.messages(id);
      if (topics.hasUserTopic(id)) {
        out.skippedUserSet++;
      } else {
        final body = msgs.map((m) => m.text).join('\n');
        final r = KeywordClassifier.classify(c.title, body, corrections: corrections);
        _applyAuto(id, [for (final k in r.ruleKeys) _topicIdForKey(k), ...r.learnedTopicIds]);
      }
      if (c.summary == null) {
        store.setSummary(id, OfflineSummarizer.summarize(c.title, msgs), byAi: false);
      }
      out.done++;
      onProgress?.call(i + 1, ids.length);
      if (i % 20 == 0) await Future<void>.delayed(Duration.zero);
    }
    return out;
  }

  int _topicIdForKey(String key) {
    final existing = topics.topicForKey(key);
    if (existing != null) return existing;
    return topics.create(KeywordClassifier.nameFor(key), key: key);
  }

  void _applyAuto(int convId, List<int> topicIds) {
    final removed = topics.removedTopicsOf(convId);
    topics.clearAuto(convId);
    for (final t in topicIds.toSet()) {
      if (!removed.contains(t)) topics.addAuto(convId, t);
    }
  }

  /// 사용자가 대화를 옮기면 그 대화의 주요 낱말을 기억해 다음 분류에 반영합니다.
  Future<void> userMove(int convId, int topicId) async {
    topics.moveTo(convId, topicId);
    final c = store.get(convId);
    if (c == null) return;
    final msgs = await store.messages(convId);
    final words = KeywordExtractor.top('${c.title} ${c.title} ${msgs.map((m) => m.text).join(' ')}', count: 5);
    topics.rememberCorrection(words, topicId);
    AppLog.info('사용자 주제 이동 기억', {'words': words.length});
  }

  // ---------- AI ----------

  static const batchSize = 12;

  Future<String> _contentFor(ConversationSummary c, ShareScope scope) async {
    if (scope == ShareScope.titlesOnly) return '';
    final msgs = await store.messages(c.id);
    final buf = StringBuffer();
    for (final m in msgs) {
      if (scope == ShareScope.partial && m.role != Role.user) continue;
      buf.writeln('${m.role == Role.user ? '사용자' : 'AI'}: ${m.text}');
      if (buf.length > scope.charLimit) break;
    }
    final s = buf.toString();
    return s.length > scope.charLimit ? s.substring(0, scope.charLimit) : s;
  }

  Future<CostEstimate> estimate(List<int> ids, ShareScope scope, String model) async {
    var chars = 0;
    for (final id in ids) {
      final c = store.get(id);
      if (c == null) continue;
      chars += c.title.length + 20;
      if (scope != ShareScope.titlesOnly) {
        // 실제 길이를 재되, 범위 한도를 넘지 않게
        chars += (await _contentFor(c, scope)).length;
      }
    }
    final batches = (ids.length / batchSize).ceil();
    final inTok = (chars * 1.0).round() + batches * 600; // 한글은 대략 글자당 1토큰으로 넉넉하게
    final outTok = ids.length * 80;
    final usd = ClaudeProvider.priceOf(model).cost(inTok, outTok);
    return CostEstimate(ids.length, inTok, outTok, usd);
  }

  static const _schema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['results'],
    'properties': {
      'results': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['id', 'topics', 'summary'],
          'properties': {
            'id': {'type': 'integer'},
            'topics': {
              'type': 'array',
              'items': {'type': 'string'},
            },
            'summary': {'type': 'string'},
          },
        },
      },
    },
  };

  Future<ClassifyOutcome> classifyWithAi(
    List<int> ids, {
    required AiProvider provider,
    required String model,
    required ShareScope scope,
    required double monthlyCapUsd,
    void Function(int, int)? onProgress,
    CancelToken? cancel,
  }) async {
    final out = ClassifyOutcome();
    final existing = topics.all().map((t) => t.name).toList();
    final examples = _correctionExamples();
    for (var i = 0; i < ids.length; i += batchSize) {
      if (cancel?.isCancelled == true) {
        out.cancelled = true;
        break;
      }
      final chunk = ids.sublist(i, (i + batchSize).clamp(0, ids.length));
      final est = await estimate(chunk, scope, model);
      if (store.costThisMonth() + est.usd > monthlyCapUsd) {
        out.stoppedBy = const AiError(AiErrorKind.budget);
        break;
      }
      final items = <Map<String, dynamic>>[];
      final convs = <int, ConversationSummary>{};
      for (final id in chunk) {
        final c = store.get(id);
        if (c == null) continue;
        convs[id] = c;
        items.add({'id': id, 'title': c.title, if (scope != ShareScope.titlesOnly) 'content': await _contentFor(c, scope)});
      }
      try {
        final reply = await provider.askJson(
          model: model,
          system:
              '당신은 사용자의 AI 대화 기록을 정리하는 비서입니다. 각 대화에 어울리는 주제 1~3개와 한두 줄 한국어 요약을 만드세요. '
              '주제 이름은 짧은 한국어(2~8글자)로, 가능하면 이미 있는 주제 이름을 그대로 쓰세요. 요약은 60자 안팎, 무엇을 물었고 무엇을 정했는지 위주로.',
          user: jsonEncode({'이미 있는 주제': existing, if (examples.isNotEmpty) '사용자가 고친 예시(낱말 → 주제)': examples, '대화': items}),
          schema: _schema,
        );
        final usd = ClaudeProvider.priceOf(model).cost(reply.usage.inputTokens, reply.usage.outputTokens);
        store.addCost(reply.model, reply.usage.inputTokens, reply.usage.outputTokens, usd);
        final results = reply.json['results'];
        if (results is List) {
          for (final r in results) {
            if (r is! Map) continue;
            final id = (r['id'] as num?)?.toInt();
            if (id == null || !convs.containsKey(id)) continue;
            final names = (r['topics'] as List? ?? const []).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).take(3);
            if (!topics.hasUserTopic(id)) {
              final tids = <int>[];
              for (final n in names) {
                tids.add(topics.create(n));
                if (!existing.contains(n)) existing.add(n);
              }
              if (tids.isNotEmpty) _applyAuto(id, tids);
            } else {
              out.skippedUserSet++;
            }
            final summary = r['summary']?.toString().trim() ?? '';
            if (summary.isNotEmpty) store.setSummary(id, summary, byAi: true);
            out.done++;
          }
        }
      } on AiError catch (e) {
        if (e.kind == AiErrorKind.refused) {
          out.aiFailed += chunk.length;
          continue;
        }
        out.stoppedBy = e;
        break;
      }
      onProgress?.call((i + chunk.length).clamp(0, ids.length), ids.length);
    }
    return out;
  }

  Map<String, String> _correctionExamples() {
    final names = {for (final t in topics.all()) t.id: t.name};
    final out = <String, String>{};
    topics.corrections().forEach((word, list) {
      list.sort((a, b) => b.$2.compareTo(a.$2));
      final n = names[list.first.$1];
      if (n != null && out.length < 30) out[word] = n;
    });
    return out;
  }

  // ---------- 지금까지 정한 내용 ----------

  Future<List<Decision>> decisionsForTopic(int topicId) async {
    final convs = store.list(topicId: topicId, limit: 500, newestFirst: false);
    final out = <Decision>[];
    for (final c in convs) {
      final msgs = await store.messages(c.id);
      for (final d in OfflineSummarizer.decisionsIn(msgs)) {
        out.add(Decision(d, c.createdAt, c.id, c.title, c.source));
      }
    }
    return out;
  }

  static const _digestSchema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['points'],
    'properties': {
      'points': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
  };

  Future<String> aiDigest(int topicId, {required AiProvider provider, required String model, required double monthlyCapUsd}) async {
    final ds = await decisionsForTopic(topicId);
    final convs = store.list(topicId: topicId, limit: 60);
    final payload = {
      '정한 내용 후보': ds.map((d) => '${d.when.year}.${d.when.month}.${d.when.day} ${d.text}').toList(),
      '대화 요약': convs.map((c) => '${c.title}: ${c.summary ?? ''}').toList(),
    };
    final text = jsonEncode(payload);
    final est = ClaudeProvider.priceOf(model).cost(text.length + 400, 600);
    if (store.costThisMonth() + est > monthlyCapUsd) throw const AiError(AiErrorKind.budget);
    final reply = await provider.askJson(
      model: model,
      system: '사용자가 이 주제로 여러 AI와 나눈 대화에서 "지금까지 정한 내용"을 쉬운 한국어 항목 3~10개로 정리하세요. 최신 결정이 앞선 결정과 다르면 최신 것을 쓰고 바뀌었다고 적으세요.',
      user: text,
      schema: _digestSchema,
      maxTokens: 2000,
    );
    store.addCost(
      reply.model,
      reply.usage.inputTokens,
      reply.usage.outputTokens,
      ClaudeProvider.priceOf(model).cost(reply.usage.inputTokens, reply.usage.outputTokens),
    );
    final points = (reply.json['points'] as List? ?? const []).map((e) => '• $e').join('\n');
    topics.setDigest(topicId, points, byAi: true);
    return points;
  }
}
