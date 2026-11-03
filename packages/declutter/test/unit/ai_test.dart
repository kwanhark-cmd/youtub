import 'dart:async';
import 'dart:convert';

import 'package:binugi/core/errors.dart';
import 'package:binugi/data/models.dart';
import 'package:binugi/services/ai/ai_provider.dart';
import 'package:binugi/services/ai/claude_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers.dart';

http.Response _ok(Map<String, Object?> json, {int inTok = 3000, int outTok = 400, String stop = 'end_turn'}) => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'content': [
        {'type': 'thinking', 'thinking': ''},
        {'type': 'text', 'text': jsonEncode(json)},
      ],
      'stop_reason': stop,
      'usage': {'input_tokens': inTok, 'output_tokens': outTok},
    }),
  ),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('가짜 HTTP로 Claude 요청 형식과 응답 해석 확인 (실제 호출 없음)', () async {
    late http.Request sent;
    final client = MockClient((req) async {
      sent = req;
      return _ok({
        'items': [
          {'name': '커피 머신', 'kind': '소형 가전', 'condition': '잘 작동함', 'suggestion': 'sell', 'reason': '쓸 만해요'},
          {'name': '', 'kind': '', 'condition': '', 'suggestion': 'use', 'reason': ''},
        ],
      });
    });
    final ai = ClaudeAi(apiKey: 'sk-ant-test', client: client);
    final r = await ai.recognize(fakeJpeg(w: 100, h: 80), width: 100, height: 80, hint: '10년 됨');
    expect(r.value.length, 1);
    expect(r.value.first.suggestion, Decision.sell);
    expect(r.usd, closeTo(3000 * 4 / 1e6 + 400 * 20 / 1e6, 1e-9));
    expect(sent.url.toString(), 'https://api.anthropic.com/v1/messages');
    expect(sent.headers['x-api-key'], 'sk-ant-test');
    expect(sent.headers['anthropic-version'], '2026-10-21');
    final body = jsonDecode(sent.body) as Map;
    expect(body['model'], 'claude-opus-5-5');
    expect(body['fallbacks'], 'default');
    expect(body.containsKey('temperature'), isFalse);
    expect((body['output_config'] as Map)['format']['type'], 'json_schema');
    final content = (body['messages'] as List).first['content'] as List;
    expect(content.first['type'], 'image');
  });

  test('오류 종류 구분: 키 틀림, 시간 초과, 거절, 서버 오류, 이상한 답', () async {
    Future<AiErrorKind> kindFor(Future<http.Response> Function() f, {Duration timeout = const Duration(seconds: 5)}) async {
      final ai = ClaudeAi(apiKey: 'k', client: MockClient((_) => f()), timeout: timeout);
      try {
        await ai.suggest(Item(userId: 1, name: 'x', createdAt: DateTime(2026)));
        fail('오류가 나야 함');
      } on AiException catch (e) {
        return e.kind;
      }
    }

    expect(await kindFor(() async => http.Response('{}', 401)), AiErrorKind.badKey);
    expect(await kindFor(() async => http.Response('{}', 529)), AiErrorKind.server);
    expect(await kindFor(() async => _ok({}, stop: 'refusal')), AiErrorKind.refused);
    expect(
      await kindFor(
        () async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': '말로만'},
              ],
            }),
          ),
          200,
        ),
      ),
      AiErrorKind.recognitionFailed,
    );
    expect(await kindFor(() => Completer<http.Response>().future, timeout: const Duration(milliseconds: 50)), AiErrorKind.timeout);
    final noKey = ClaudeAi(apiKey: '', client: MockClient((_) async => http.Response('', 200)));
    expect(
      () => noKey.suggest(Item(userId: 1, name: 'x', createdAt: DateTime(2026))),
      throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.noKey)),
    );
  });

  test('키가 없으면 연습 모드, 비용 0원', () async {
    final (s, _) = await makeState();
    final r = await s.ai.recognize(s.uid, s.user, fakeJpeg(w: 64, h: 64), width: 64, height: 64);
    expect(r.practice, isTrue);
    expect(r.value, isNotEmpty);
    expect(await s.monthCost(), 0);
  });

  test('사진 보내기 동의가 꺼져 있으면 사진이 외부로 나가지 않음', () async {
    var calls = 0;
    final (s, _) = await makeState(
      httpClient: MockClient((_) async {
        calls++;
        return _ok({'items': []});
      }),
    );
    s.user
      ..aiProvider = 'claude'
      ..apiKey = 'sk-ant-x'
      ..sendPhotosToAi = false;
    final r = await s.ai.recognize(s.uid, s.user, fakeJpeg(w: 64, h: 64), width: 64, height: 64);
    expect(r.practice, isTrue);
    expect(calls, 0);
  });

  test('월 한도를 넘으면 호출하지 않고 한도 초과 안내', () async {
    var calls = 0;
    final (s, _) = await makeState(
      httpClient: MockClient((_) async {
        calls++;
        return _ok({
          'items': [
            {'name': '컵', 'kind': '', 'condition': '', 'suggestion': 'sell', 'reason': ''},
          ],
        });
      }),
    );
    s.user
      ..aiProvider = 'claude'
      ..apiKey = 'sk-ant-x'
      ..sendPhotosToAi = true
      ..monthlyLimitUsd = 0.03;
    final first = await s.ai.recognize(s.uid, s.user, fakeJpeg(w: 64, h: 64), width: 1568, height: 1176);
    expect(first.practice, isFalse);
    expect(await s.monthCost(), greaterThan(0));
    expect(
      () => s.ai.recognize(s.uid, s.user, fakeJpeg(w: 64, h: 64), width: 1568, height: 1176),
      throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.budgetExceeded)),
    );
    expect(calls, 1);
  });

  test('추천·판매글 실패 시 기본 규칙으로 대신하고 안내', () async {
    final (s, _) = await makeState(httpClient: MockClient((_) async => http.Response('', 500)));
    s.user
      ..aiProvider = 'claude'
      ..apiKey = 'sk-ant-x';
    final it = await s.addItem(name: '전기 주전자', condition: '잘 작동함');
    final sug = await s.ai.suggest(s.uid, s.user, it);
    expect(sug.practice, isTrue);
    expect(sug.message, isNotNull);
    final l = await s.ai.writeListing(s.uid, s.user, it);
    expect(l.value.title, contains('전기 주전자'));
    expect(l.value.priceLow, lessThanOrEqualTo(l.value.priceHigh));
  });

  test('사진 한 장 예상 비용', () {
    expect(AiPricing.imageTokens(1568, 1176), 2459);
    final usd = AiPricing.estimatePhotoUsd();
    expect(usd, greaterThan(0.005));
    expect(usd, lessThan(0.05));
  });
}
