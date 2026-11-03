import 'dart:convert';
import 'dart:io';

import 'package:channel_biseo/core/db.dart';
import 'package:channel_biseo/core/failure.dart';
import 'package:channel_biseo/core/http_json.dart';
import 'package:channel_biseo/core/oauth.dart';
import 'package:channel_biseo/core/secret_store.dart';
import 'package:channel_biseo/features/ai/ai_service.dart';
import 'package:channel_biseo/features/ai/brain.dart';
import 'package:channel_biseo/features/settings/maintenance.dart';
import 'package:channel_biseo/features/voice/voice_commands.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers.dart';

void main() {
  group('AI 연결과 비용', () {
    test('키가 없으면 연습 모드, 규칙으로 결과를 만든다', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      expect(u.ai.isPracticeMode, isTrue);
      final s = await u.brain.analyzeStyle('집밥 요리 교실', u.youtube.videos('UC_mock_cook'));
      expect(s.topics, isNotEmpty);
      expect(u.ai.monthCostUsd, 0);
    });

    test('키를 넣으면 실제 AI 사용, 비용이 기록되고 한도에 도달하면 연습 모드로', () async {
      final fake = FakeAiProvider(
        (r) => '{"mood":"밝음","tone":"반말","topics":["요리"],"titlePattern":"짧게","audience":"주부","notes":""}',
      );
      final k = TestKit(aiProviders: {'claude': fake});
      final u = await k.userWithChannels();
      await u.ai.setKey('sk-ant-test');
      expect(k.secrets.data.values, contains('sk-ant-test')); // 보안 저장소에만
      expect(u.db.select('SELECT value FROM settings').map((r) => r['value']).join(), isNot(contains('sk-ant-test')));
      expect(u.ai.isPracticeMode, isFalse);
      final s = await u.brain.analyzeStyle('집밥', u.youtube.videos('UC_mock_cook'));
      expect(s.mood, '밝음');
      expect(fake.calls, 1);
      expect(u.ai.monthCostUsd, greaterThan(0));
      u.settings.monthlyCostLimitUsd = u.ai.monthCostUsd; // 한도 도달
      expect(u.ai.overLimit, isTrue);
      expect(u.ai.isPracticeMode, isTrue);
      await u.brain.analyzeStyle('집밥', u.youtube.videos('UC_mock_cook'));
      expect(fake.calls, 1); // 더 부르지 않음
    });

    test('예상 비용이 한도를 넘으면 호출하지 않는다', () async {
      final fake = FakeAiProvider((r) => '{}');
      final k = TestKit(aiProviders: {'claude': fake});
      final u = await k.user();
      await u.ai.setKey('k');
      u.settings.monthlyCostLimitUsd = 0.0000001;
      await expectLater(
        u.ai.complete(AiRequest(task: 't', system: 's', prompt: 'p' * 1000)),
        throwsA(isA<AppFailure>().having((e) => e.kind, 'k', FailureKind.costLimit)),
      );
      expect(fake.calls, 0);
    });

    test('AI 답을 읽지 못하면 규칙 결과로 대신 (흐름이 멈추지 않음)', () async {
      final k = TestKit(aiProviders: {'claude': FakeAiProvider((r) => '죄송해요 JSON 이 아니에요')});
      final u = await k.userWithChannels();
      await u.ai.setKey('k');
      final s = await u.brain.analyzeStyle('여행', u.youtube.videos('UC_mock_trip'));
      expect(s.notes, contains('연습 모드'));
    });

    test('Claude 요청 모양: 기본 모델, 버전 헤더, temperature 없음', () async {
      late http.Request sent;
      final client = MockClient((r) async {
        sent = r;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'model': 'claude-opus-5-5',
              'stop_reason': 'end_turn',
              'content': [
                {'type': 'text', 'text': '{"ok":1}'},
              ],
              'usage': {'input_tokens': 1000, 'output_tokens': 500},
            }),
          ),
          200,
        );
      });
      final p = ClaudeProvider(JsonHttp(client, sleep: (_) async {}));
      final r = await p.complete(
        AiRequest(task: 't', system: 's', prompt: '안녕'),
        apiKey: 'sk-ant-x',
        model: 'claude-opus-5-5',
      );
      expect(r.text, '{"ok":1}');
      expect(sent.headers['x-api-key'], 'sk-ant-x');
      expect(sent.headers['anthropic-version'], '2026-10-21');
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['model'], 'claude-opus-5-5');
      expect(body.containsKey('temperature'), isFalse);
      expect(body['fallbacks'], 'default');
      expect(AiPrice.of('claude-opus-5-5').cost(1000000, 0), 4);
      expect(AiPrice.of('claude-haiku-5-5').cost(0, 1000000), 0.5);
    });

    test('거절(refusal) 응답은 오류로 처리', () async {
      final client = MockClient((r) async => http.Response(jsonEncode({'stop_reason': 'refusal', 'content': []}), 200));
      final p = ClaudeProvider(JsonHttp(client, sleep: (_) async {}));
      await expectLater(
        p.complete(
          AiRequest(task: 't', system: 's', prompt: 'x'),
          apiKey: 'k',
          model: 'claude-opus-5-5',
        ),
        throwsA(isA<AppFailure>()),
      );
    });

    test('자막 만들기 (SRT)', () {
      final srt = Brain.makeSrt('안녕하세요. 오늘은 김치찌개를 만들어요! 맛있게 드세요.', const Duration(seconds: 30));
      expect(srt, contains('1\n00:00:00,000 --> '));
      expect(srt, contains('--> 00:00:30,000'));
      expect('\n'.allMatches(srt).length, greaterThan(8));
    });

    test('키워드 정리: 중복 제거, 500자 제한', () {
      final m = Brain.mockSuggestMeta(
        (TestKit().mockYt.videos.values.first).copyWith(tags: List.generate(40, (i) => '키워드$i' * 5)),
        Brain.mockStyle('요리', ['김치찌개']),
      );
      expect(m!.tags.join().length, lessThanOrEqualTo(450));
      expect(m.tags.toSet().length, m.tags.length);
    });
  });

  group('음성 명령 해석', () {
    final p = VoiceCommandParser();
    const titles = ['집밥 요리 교실', '느린 여행 일기'];
    test('지시서 예시 문장', () {
      expect(p.parse('이번 주 조회수 보여줘').type, CommandType.weeklyViews);
      final make = p.parse('요리 채널에 쇼츠 하나 만들어', channelTitles: titles);
      expect(make.type, CommandType.makeContent);
      expect(make.channelHint, '집밥 요리 교실');
      expect(make.format, ContentFormat.shorts);
      expect(p.parse('비공개 영상 목록 읽어줘').type, CommandType.readPrivateList);
    });

    test('여러 표현', () {
      expect(p.parse('아침 브리핑 해줘').type, CommandType.briefing);
      expect(p.parse('메모 다음 주에 강릉 커피 영상 찍기').text, '다음 주에 강릉 커피 영상 찍기');
      expect(p.parse('오늘 수정 내역 알려줘').type, CommandType.todayEdits);
      expect(p.parse('오늘 수정한 거 다 되돌려').type, CommandType.revertToday);
      expect(p.parse('여행 채널 다큐 만들어줘', channelTitles: titles).format, ContentFormat.docu);
      expect(p.parse('도움말').type, CommandType.help);
      expect(p.parse('음… 날씨 어때').type, CommandType.channelSummary);
      expect(p.parse('ㅁㄴㅇㄹ').type, CommandType.unknown);
    });

    test('공개 전환·삭제는 하지 않고, 업로드·되돌리기는 확인이 필요', () {
      expect(p.parse('이 영상 공개로 바꿔').notAllowed, isTrue);
      expect(p.parse('영상 삭제해 줘').notAllowed, isTrue);
      expect(p.parse('비공개 영상 목록 읽어줘').notAllowed, isFalse);
      expect(p.parse('요리 채널에 업로드해 줘').needsConfirmation, isTrue);
      expect(p.parse('오늘 수정 되돌려').needsConfirmation, isTrue);
    });
  });

  group('음성 실행과 아침 브리핑', () {
    test('중요한 명령은 확인 전에는 실행하지 않는다', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      await u.edits.apply(await u.edits.plan('UC_mock_cook'));
      final r = await u.voice.handle('오늘 수정 되돌려');
      expect(r.needsConfirmation, isTrue);
      expect(u.editLog.list().where((e) => e.status.name == 'applied').length, 2);
      final r2 = await u.voice.handle('오늘 수정 되돌려', confirmed: true);
      expect(r2.spoken, contains('2개를 되돌렸어요'));
    });

    test('공개 전환을 말해도 앱은 하지 않는다', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      final r = await u.voice.handle('영상 공개로 전환해');
      expect(r.spoken, contains('직접 공개'));
      expect(k.mockYt.videos.values.where((v) => v.privacy != 'public'), isEmpty);
    });

    test('메모·조회수·브리핑', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      expect((await u.voice.handle('메모 강릉 커피 영상 찍기')).spoken, contains('저장'));
      expect(u.memos.list().single.text, '강릉 커피 영상 찍기');
      // 어제 기록이 있도록 하루 진행
      k.clock.advance(const Duration(days: 1));
      k.mockYt.addViews(10);
      for (final c in u.youtube.channels()) {
        await u.youtube.syncChannel(c.channelId);
      }
      final w = await u.voice.handle('이번 주 조회수 보여줘');
      expect(w.spoken, contains('이번 주 전체 조회수'));
      final b = u.briefing.compose();
      expect(b.spoken, contains('어제 채널 변화'));
      expect(b.today.join(), contains('남은 유튜브 사용량'));
    });

    test('브리핑 시간: 켜야 하고, 정한 시각이 지나야 하고, 하루 한 번', () async {
      final k = TestKit(start: DateTime(2026, 11, 2, 7, 0));
      final u = await k.user();
      expect(u.briefing.isDue(), isFalse);
      u.settings.briefingEnabled = true;
      u.settings.briefingHour = 8;
      expect(u.briefing.isDue(), isFalse);
      k.clock.advance(const Duration(hours: 1, minutes: 1));
      expect(u.briefing.isDue(), isTrue);
      u.briefing.markDone();
      expect(u.briefing.isDue(), isFalse);
    });

    test('구글 테스트 모드 연결은 만료 임박을 알려 준다', () async {
      final k = TestKit();
      final u = await k.user();
      u.db.execute("INSERT INTO accounts(provider,label,connected_at,status,mock) VALUES('google','내 계정',?, 'ok', 0)", [
        k.clock().subtract(const Duration(days: 6)).toIso8601String(),
      ]);
      expect(u.briefing.compose().expiring.join(), contains('1일 뒤 만료'));
    });
  });

  group('자동 작업 실행기', () {
    test('기본은 꺼짐', () async {
      final k = TestKit(start: DateTime(2026, 11, 2, 3, 0));
      final u = await k.userWithChannels();
      expect(u.settings.runnerEnabled, isFalse);
      expect(await u.runner.tick(), isFalse);
      expect(k.notifier.shown, isEmpty);
    });

    test('휴대폰에서는 켜져 있어도 실행하지 않는다', () async {
      final k = TestKit(isDesktop: false, start: DateTime(2026, 11, 2, 3, 0));
      final u = await k.userWithChannels();
      u.settings.runnerEnabled = true;
      expect(await u.runner.tick(), isFalse);
    });

    test('정한 시간대에 하루 한 번, 실행 전후 알림, 업로드는 하지 않음', () async {
      final k = TestKit(start: DateTime(2026, 11, 2, 1, 0));
      final u = await k.userWithChannels();
      u.settings.runnerEnabled = true;
      expect(await u.runner.tick(), isFalse); // 2시 전
      k.clock.advance(const Duration(hours: 2));
      expect(await u.runner.tick(), isTrue);
      expect(k.notifier.shown.length, 2);
      expect(k.notifier.shown.first.$2, contains('시작'));
      expect(k.notifier.shown.last.$2, contains('끝났어요'));
      expect(u.editLog.countOn(dayKey(k.clock())), 6);
      expect(k.mockYt.uploadCalls, 0);
      expect(await u.runner.tick(), isFalse); // 같은 날 두 번 안 함
      expect(u.jobs.recentLog(), isNotEmpty);
    });

    test('한도 초과 작업은 다음 날로 넘기고 기록', () async {
      final k = TestKit(start: DateTime(2026, 11, 2, 3, 0));
      final u = await k.userWithChannels();
      var runs = 0;
      u.runner.handlers['test'] = (job, cancel) async {
        runs++;
        throw AppFailure(FailureKind.quotaExceeded);
      };
      final id = u.jobs.add('test', {});
      u.settings.editsPerChannelPerDay = 0;
      await u.runner.runNow();
      expect(runs, 1);
      final j = u.jobs.all().firstWhere((j) => j.id == id);
      expect(j.status, 'waiting');
      expect(j.runDay, dayKey(k.clock().add(const Duration(days: 1))));
      expect(u.jobs.recentLog().join(), contains('내일'));
    });

    test('자동 작업 중 오류가 나도 다음 채널은 계속', () async {
      final k = TestKit(start: DateTime(2026, 11, 2, 3, 0));
      final u = await k.userWithChannels();
      k.mockYt.failNext.add(FailureKind.permissionRevoked); // 첫 채널 불러오기 실패
      final r = await u.runner.runNow();
      expect(r.edits, 4);
    });
  });

  group('OAuth 토큰', () {
    test('PKCE 값이 규칙대로 만들어진다', () {
      final p = makePkce();
      expect(p.verifier.length, greaterThanOrEqualTo(43));
      final expected = base64UrlEncode(sha256.convert(ascii.encode(p.verifier)).bytes).replaceAll('=', '');
      expect(p.challenge, expected);
    });

    test('만료된 토큰은 자동 갱신, 거절되면 "다시 연결"', () async {
      var mode = 'ok';
      final client = MockClient((r) async {
        expect(r.body, contains('grant_type=refresh_token'));
        if (mode == 'ok') return http.Response(jsonEncode({'access_token': 'new', 'expires_in': 3600}), 200);
        return http.Response('{"error":"invalid_grant"}', 400);
      });
      final clock = TestClock();
      final flow = OAuthFlow(JsonHttp(client, sleep: (_) async {}), (u) async => true, now: clock.call);
      final tm = TokenManager(UserSecrets(MemorySecretStore(), 1), flow, now: clock.call);
      final cfg = OAuthConfig.google('id', '', const ['s']);
      await tm.save(
        1,
        OAuthTokens(accessToken: 'old', refreshToken: 'r', expiresAt: clock().subtract(const Duration(minutes: 1))),
      );
      expect(await tm.accessToken(1, cfg), 'new');
      expect((await tm.load(1))!.refreshToken, 'r');
      expect(await tm.accessToken(1, cfg), 'new'); // 아직 유효
      clock.advance(const Duration(hours: 2));
      mode = 'revoked';
      await expectLater(
        tm.accessToken(1, cfg),
        throwsA(isA<AppFailure>().having((e) => e.kind, 'k', FailureKind.permissionRevoked)),
      );
    });

    test('토큰 갱신이 거절되면 계정이 "다시 연결" 상태로 표시된다', () async {
      final k = TestKit(client: MockClient((r) async => http.Response('{"error":"invalid_grant"}', 400)));
      final u = await k.user();
      u.settings.googleClientId = 'cid';
      final id = u.db.insert(
        "INSERT INTO accounts(provider,label,connected_at,status,mock) VALUES('google','g',?, 'ok', 0)",
        [k.clock().toIso8601String()],
      );
      u.db.execute(
        "INSERT INTO channels(account_id, channel_id, title, uploads_playlist, added_at) VALUES(?, 'C1', '실채널', 'UU', '')",
        [id],
      );
      await u.tokens.save(id, OAuthTokens(accessToken: 'a', refreshToken: 'r', expiresAt: DateTime(2000)));
      await expectLater(u.youtube.syncChannel('C1'), throwsA(isA<AppFailure>()));
      expect(u.youtube.brokenAccounts().single.id, id);
    });
  });

  group('백업·복원·문제 신고', () {
    test('백업 파일은 이 앱 것인지 확인하고, 복원하면 실제 계정은 다시 연결 상태', () async {
      final dir = Directory.systemTemp.createTempSync('bk');
      final k = TestKit();
      final u = await k.userWithChannels();
      u.db.execute(
        "INSERT INTO accounts(provider,label,connected_at,status,mock) VALUES('google','실계정','2026-01-01','ok',0)",
      );
      final path = u.maintenance.backupTo(dir.path);
      expect(Maintenance.isValidBackup(path), isTrue);
      final junk = File('${dir.path}/junk.sqlite')..writeAsStringSync('not sqlite');
      expect(Maintenance.isValidBackup(junk.path), isFalse);
      final target = '${dir.path}/restored.sqlite';
      Maintenance.restoreFile(backupPath: path, targetDbPath: target, safetyDir: '${dir.path}/safe');
      final restored = AppDatabase.open(target, userDataMigrations);
      expect(restored.select('SELECT COUNT(*) AS n FROM channels').first['n'], 3);
      expect(restored.select('SELECT status FROM accounts WHERE mock = 0').first['status'], 'revoked');
    });

    test('문제 신고 파일에는 버전이 있고 비밀 정보가 없다', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      await u.ai.setKey('sk-ant-supersecret');
      k.logger.info('요청 헤더 x-api-key: sk-ant-supersecret Authorization: Bearer ya29.tokenvalue');
      final t = u.maintenance.reportText();
      expect(t, contains('0.0.0+test'));
      expect(t, isNot(contains('supersecret')));
      expect(t, isNot(contains('ya29.tokenvalue')));
    });
  });
}
