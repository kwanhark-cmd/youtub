import 'dart:convert';
import 'dart:io';

import 'package:channel_biseo/core/failure.dart';
import 'package:channel_biseo/core/http_json.dart';
import 'package:channel_biseo/features/youtube/models.dart';
import 'package:channel_biseo/features/youtube/youtube_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers.dart';

void main() {
  group('채널 등록·현황 (연습 모드)', () {
    test('구글 연결 한 번으로 계정의 채널을 모두 등록', () async {
      final k = TestKit();
      final u = await k.user();
      expect(u.youtube.isPracticeMode, isTrue);
      final rows = await u.youtube.connectGoogle(channelUrl: 'https://www.youtube.com/@UC_mock_cook');
      expect(rows.length, 3);
      expect(u.youtube.accounts().single.mock, isTrue);
      expect(u.youtube.channel('UC_mock_cook')!.url, 'https://www.youtube.com/@UC_mock_cook');
    });

    test('영상 120개를 나눠서 불러오고, 화면도 나눠서 읽는다', () async {
      final k = TestKit();
      final u = await k.user();
      await u.youtube.connectGoogle();
      final fractions = <double>[];
      final n = await u.youtube.syncChannel('UC_mock_cook', progress: (f, _) => fractions.add(f));
      expect(n, 120);
      expect(fractions.length, 3); // 50 + 50 + 20
      expect(u.youtube.videoTotal('UC_mock_cook'), 120);
      final page1 = u.youtube.videos('UC_mock_cook', limit: 30);
      final page2 = u.youtube.videos('UC_mock_cook', offset: 30, limit: 30);
      expect(page1.length, 30);
      expect(page1.map((v) => v.videoId).toSet().intersection(page2.map((v) => v.videoId).toSet()), isEmpty);
      // 한도: 연결 1 + 페이지당 2
      expect(u.quota.used, 1 + 3 * 2);
    });

    test('한도가 모자라면 불러오기를 멈춘다', () async {
      final k = TestKit();
      final u = await k.user();
      await u.youtube.connectGoogle();
      u.settings.quotaDailyLimit = 100;
      u.quota.reserve(98);
      await expectLater(
        u.youtube.syncChannel('UC_mock_cook'),
        throwsA(isA<AppFailure>().having((e) => e.kind, 'k', FailureKind.quotaExceeded)),
      );
    });

    test('연결 해제하면 앱 안 자료만 지우고 계정 토큰도 정리', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      for (final c in u.youtube.channels()) {
        await u.youtube.disconnectChannel(c.channelId);
      }
      expect(u.youtube.channels(), isEmpty);
      expect(u.youtube.accounts(), isEmpty);
      expect(u.db.select('SELECT COUNT(*) AS n FROM videos').first['n'], 0);
      // 가짜 유튜브의 영상은 그대로 (실제 유튜브 영상을 지우지 않는다)
      expect(k.mockYt.videos.length, greaterThan(100));
    });

    test('네트워크가 끊겨도 저장된 자료는 보인다', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      k.mockYt.failNext.addAll([FailureKind.network, FailureKind.network, FailureKind.network]);
      await expectLater(u.youtube.syncChannel('UC_mock_trip'), throwsA(isA<AppFailure>()));
      expect(u.youtube.videos('UC_mock_trip'), isNotEmpty);
    });

    test('일시적인 네트워크 오류는 자동 재시도로 넘어간다', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      k.mockYt.failNext.add(FailureKind.network);
      expect(await u.youtube.syncChannel('UC_mock_trip'), 24);
    });
  });

  group('실제 YouTube API 요청 모양 (가짜 응답)', () {
    late List<http.BaseRequest> sent;
    late List<String> bodies;

    RealYouTubeApi api(http.Response Function(http.Request r) handler) {
      sent = [];
      bodies = [];
      final client = MockClient((r) async {
        sent.add(r);
        bodies.add(r.body);
        return handler(r);
      });
      return RealYouTubeApi(JsonHttp(client, sleep: (_) async {}), client);
    }

    test('내 채널 읽기', () async {
      final a = api(
        (r) => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'items': [
                {
                  'id': 'UC1',
                  'snippet': {'title': '내 채널', 'customUrl': '@me'},
                  'statistics': {'subscriberCount': '10', 'videoCount': '2', 'viewCount': '300'},
                  'contentDetails': {
                    'relatedPlaylists': {'uploads': 'UU1'},
                  },
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final c = await a.myChannels('tok');
      expect(c.single.title, '내 채널');
      expect(c.single.uploadsPlaylist, 'UU1');
      expect(sent.single.headers['authorization'], 'Bearer tok');
      expect(sent.single.url.queryParameters['mine'], 'true');
    });

    test('제목 수정은 snippet 만 보내고 공개 범위는 건드리지 않는다', () async {
      final a = api(
        (r) =>
            http.Response.bytes(utf8.encode(jsonEncode({'id': 'v1', 'snippet': jsonDecode(r.body)['snippet']})), 200),
      );
      final v = YtVideo(videoId: 'v1', channelId: 'c', title: '옛 제목', categoryId: '26');
      final nv = await a.updateMeta('t', v, const VideoMeta(title: '새 제목', description: 'd', tags: ['a']));
      expect(nv.title, '새 제목');
      expect(sent.single.method, 'PUT');
      expect(sent.single.url.queryParameters['part'], 'snippet');
      final body = jsonDecode(bodies.single) as Map<String, dynamic>;
      expect(body.containsKey('status'), isFalse);
      expect((body['snippet'] as Map)['categoryId'], '26');
    });

    test('업로드는 항상 비공개', () async {
      final f = File('${Directory.systemTemp.createTempSync('up').path}/v.mp4')..writeAsBytesSync([1, 2, 3]);
      final a = api((r) {
        if (r.url.path.contains('/upload/')) {
          return http.Response('', 200, headers: {'location': 'https://upload.example/session'});
        }
        return http.Response(jsonEncode({'id': 'newid'}), 200);
      });
      // 파일 전송(StreamedRequest)은 MockClient 가 처리
      final id = await a.uploadPrivate(
        't',
        'c',
        f,
        UploadMeta(title: 't', description: 'd', tags: const [], containsSyntheticMedia: true),
      );
      expect(id, 'newid');
      final meta = jsonDecode(bodies.first) as Map<String, dynamic>;
      expect((meta['status'] as Map)['privacyStatus'], 'private');
      expect((meta['status'] as Map)['containsSyntheticMedia'], true);
    });

    test('403 한도 초과 / 401 토큰 만료 구분', () async {
      final a1 = api((r) => http.Response('{"error":{"errors":[{"reason":"quotaExceeded"}]}}', 403));
      await expectLater(
        a1.myChannels('t'),
        throwsA(isA<AppFailure>().having((e) => e.kind, 'k', FailureKind.quotaExceeded)),
      );
      final a2 = api((r) => http.Response('unauthorized', 401));
      await expectLater(
        a2.myChannels('t'),
        throwsA(isA<AppFailure>().having((e) => e.kind, 'k', FailureKind.tokenExpired)),
      );
    });

    test('YouTubeApi 에는 삭제·공개 전환 기능이 없다', () {
      final src = File('lib/features/youtube/youtube_api.dart').readAsStringSync();
      expect(src.contains("'DELETE'"), isFalse);
      expect(RegExp(r"privacyStatus'\s*:\s*'public'").hasMatch(src), isFalse);
      expect(RegExp(r"privacyStatus'\s*:\s*'unlisted'").hasMatch(src), isFalse);
    });
  });
}
