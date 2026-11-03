import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_organizer/classify/ai_provider.dart';
import 'package:ai_chat_organizer/classify/keyword_classifier.dart';
import 'package:ai_chat_organizer/data/topic_store.dart';
import 'package:ai_chat_organizer/classify/classification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers/test_env.dart';

http.Response ok(Map<String, dynamic> json, {int inTok = 100, int outTok = 20}) => http.Response(
  jsonEncode({
    'model': 'claude-opus-5-5',
    'stop_reason': 'end_turn',
    'content': [
      {'type': 'text', 'text': jsonEncode(json)},
    ],
    'usage': {'input_tokens': inTok, 'output_tokens': outTok},
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

ClaudeProvider provider(MockClient client, {int retries = 2}) =>
    ClaudeProvider(apiKey: 'sk-ant-test', client: client, maxRetries: retries, sleep: (_) async {});

void main() {
  group('클로드 연결(가짜 서버, 실제 호출 없음)', () {
    test('요청 형식과 응답 읽기', () async {
      late Map<String, dynamic> sent;
      late Map<String, String> headers;
      final p = provider(
        MockClient((req) async {
          sent = jsonDecode(req.body);
          headers = req.headers;
          return ok({'results': []});
        }),
      );
      final r = await p.askJson(model: 'claude-opus-5-5', system: 's', user: 'u', schema: {'type': 'object'});
      expect(r.usage.inputTokens, 100);
      expect(headers['x-api-key'], 'sk-ant-test');
      expect(headers['anthropic-version'], isNotEmpty);
      expect(sent['model'], 'claude-opus-5-5');
      expect(sent['output_config']['format']['type'], 'json_schema');
      expect(sent.containsKey('thinking'), isFalse);
      expect(sent.containsKey('temperature'), isFalse);
    });
    test('키 오류·잔액 부족·한도 초과·서버 바쁨을 구분한다', () async {
      Future<AiErrorKind> kindFor(int code, Map<String, dynamic> body) async {
        try {
          await provider(
            MockClient((_) async => http.Response(jsonEncode(body), code)),
            retries: 0,
          ).askJson(model: 'claude-haiku-5-5', system: '', user: '', schema: {});
        } on AiError catch (e) {
          return e.kind;
        }
        return AiErrorKind.unknown;
      }

      expect(
        await kindFor(401, {
          'error': {'type': 'authentication_error', 'message': 'invalid x-api-key'},
        }),
        AiErrorKind.badKey,
      );
      expect(
        await kindFor(400, {
          'error': {'type': 'invalid_request_error', 'message': 'Your credit balance is too low'},
        }),
        AiErrorKind.noCredit,
      );
      expect(
        await kindFor(429, {
          'error': {'type': 'rate_limit_error', 'message': 'slow down'},
        }),
        AiErrorKind.rateLimited,
      );
      expect(
        await kindFor(529, {
          'error': {'type': 'overloaded_error', 'message': 'busy'},
        }),
        AiErrorKind.overloaded,
      );
    });
    test('한도 초과는 재시도해서 성공한다', () async {
      var n = 0;
      final p = provider(
        MockClient((_) async => ++n < 3 ? http.Response('{"error":{"type":"rate_limit_error"}}', 429) : ok({'results': []})),
      );
      await p.askJson(model: 'claude-opus-5-5', system: '', user: '', schema: {});
      expect(n, 3);
    });
    test('인터넷 없음·거절·키 없음', () async {
      final net = provider(MockClient((_) async => throw const SocketException('없음')));
      expect(
        () => net.askJson(model: 'm', system: '', user: '', schema: {}),
        throwsA(isA<AiError>().having((e) => e.kind, 'kind', AiErrorKind.network)),
      );
      final refused = provider(
        MockClient((_) async => http.Response(jsonEncode({'stop_reason': 'refusal', 'content': [], 'usage': {}}), 200)),
      );
      expect(
        () => refused.askJson(model: 'm', system: '', user: '', schema: {}),
        throwsA(isA<AiError>().having((e) => e.kind, 'kind', AiErrorKind.refused)),
      );
      final noKey = ClaudeProvider(apiKey: '', client: MockClient((_) async => ok({})));
      expect(
        () => noKey.askJson(model: 'm', system: '', user: '', schema: {}),
        throwsA(isA<AiError>().having((e) => e.kind, 'kind', AiErrorKind.noKey)),
      );
    });
    test('모든 오류 안내는 한국어', () {
      for (final k in AiErrorKind.values) {
        expect(RegExp(r'[가-힣]').hasMatch(AiError(k).message), isTrue);
      }
    });
  });

  group('분류', () {
    test('무료(키워드) 분류와 요약', () async {
      final s = await storeWithSamples();
      final t = TopicStore(s.db);
      final svc = ClassificationService(s, t);
      await svc.classifyOffline(s.list(limit: 100).map((c) => c.id).toList());
      final names = t.all().map((x) => x.name).toSet();
      expect(names, containsAll(['유튜브·영상', '투자·재테크', '여행']));
      final split = s.list().firstWhere((c) => c.title.contains('세븐 스플릿'));
      expect(t.topicsOf(split.id).map((x) => x.name), contains('투자·재테크'));
      expect(s.get(split.id)!.summary, contains('→'));
    });
    test('사용자가 옮긴 대화는 다시 분류해도 그대로, 이름 바꾼 주제를 계속 씀, 고친 낱말을 기억', () async {
      final s = await storeWithSamples();
      final t = TopicStore(s.db);
      final svc = ClassificationService(s, t);
      final ids = s.list(limit: 100).map((c) => c.id).toList();
      await svc.classifyOffline(ids);
      final travel = s.list().firstWhere((c) => c.title.contains('제주도'));
      final family = t.create('가족 일정');
      await svc.userMove(travel.id, family);
      final videoTopic = t.byName('유튜브·영상')!;
      t.rename(videoTopic.id, '영상 만들기');
      await svc.classifyOffline(ids);
      expect(t.topicsOf(travel.id).map((x) => x.name), ['가족 일정']);
      expect(t.byName('유튜브·영상'), isNull);
      expect(t.byId(t.byName('영상 만들기')!.id)!.count, greaterThan(0));
      expect(t.corrections().keys, isNotEmpty);
      final r = KeywordClassifier.classify('제주도 맛집', '제주도 일정', corrections: t.corrections());
      expect(r.learnedTopicIds, contains(family));
    });
    test('합치기·나누기·하위 주제', () async {
      final s = await storeWithSamples();
      final t = TopicStore(s.db);
      final a = t.create('가'), b = t.create('나');
      final ids = s.list().map((c) => c.id).toList();
      t.setOrigin(ids[0], a, 'user');
      t.setOrigin(ids[1], a, 'user');
      t.merge(a, b);
      expect(t.byName('가'), isNull);
      expect(t.byId(b)!.count, 2);
      final c2 = t.split(b, '다', [ids[0]]);
      expect(t.byId(c2)!.count, 1);
      expect(t.byId(b)!.count, 1);
      expect(t.setParent(c2, b), isTrue);
      expect(t.setParent(b, c2), isFalse); // 자기 아래로는 못 감
      expect(s.count(topicId: b), 2); // 하위 주제 포함
    });
    test('AI 분류: 보내는 범위·비용 기록·한도', () async {
      final s = await storeWithSamples();
      final t = TopicStore(s.db);
      final svc = ClassificationService(s, t);
      final ids = s.list(limit: 100).map((c) => c.id).toList();
      final bodies = <String>[];
      final p = provider(
        MockClient((req) async {
          bodies.add(req.body);
          final user = jsonDecode(jsonDecode(req.body)['messages'][0]['content'] as String);
          final convs = user['대화'] as List;
          return ok({
            'results': [
              for (final c in convs)
                {
                  'id': c['id'],
                  'topics': ['AI주제'],
                  'summary': 'AI 요약',
                },
            ],
          });
        }),
      );
      final out = await svc.classifyWithAi(ids, provider: p, model: 'claude-haiku-5-5', scope: ShareScope.titlesOnly, monthlyCapUsd: 5);
      expect(out.done, ids.length);
      expect(bodies.every((b) => !b.contains('일출봉')), isTrue, reason: '제목만 보내야 함');
      expect(s.costTotal(), greaterThan(0));
      expect(t.byId(t.byName('AI주제')!.id)!.count, ids.length);
      expect(s.get(ids.first)!.summary, 'AI 요약');
      final est = await svc.estimate(ids, ShareScope.full, 'claude-opus-5-5');
      expect(est.usd, greaterThan(0));
      final capped = await svc.classifyWithAi(ids, provider: p, model: 'claude-opus-5-5', scope: ShareScope.full, monthlyCapUsd: 0);
      expect(capped.stoppedBy?.kind, AiErrorKind.budget);
    });
  });
}
