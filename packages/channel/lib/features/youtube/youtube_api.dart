import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/failure.dart';
import '../../core/http_json.dart';
import '../../core/retry.dart';
import 'models.dart';

/// 유튜브와 주고받는 기능. 안전을 위해 "삭제" 와 "공개 전환" 기능은 일부러 만들지 않았다.
abstract class YouTubeApi {
  Future<List<YtChannel>> myChannels(String token);
  Future<VideoPage> listUploads(String token, String uploadsPlaylistId, {String? pageToken});
  Future<List<YtVideo>> videosByIds(String token, List<String> ids);

  /// 제목·설명·키워드만 바꾼다. 공개 범위(privacy)는 절대 건드리지 않는다.
  Future<YtVideo> updateMeta(String token, YtVideo current, VideoMeta meta);

  /// 항상 "비공개(private)" 로만 올린다. 돌려주는 값은 새 영상 ID.
  /// 실제 유튜브는 토큰이 가리키는 채널에 올라간다 ([channelId] 는 가짜 유튜브에서만 사용).
  Future<String> uploadPrivate(String token, String channelId, File file, UploadMeta meta);

  /// 내 영상의 썸네일 그림 바꾸기 (한도 50). 유튜브 계정 인증이 안 된 채널은 실패할 수 있다.
  Future<void> setThumbnail(String token, String videoId, File png);
}

/// YouTube Data API v3 실제 연결.
class RealYouTubeApi implements YouTubeApi {
  RealYouTubeApi(this.http_, this.rawClient);

  final JsonHttp http_;
  final http.Client rawClient;
  static const _base = 'https://www.googleapis.com/youtube/v3';

  Map<String, String> _h(String token) => {'authorization': 'Bearer $token'};

  @override
  Future<List<YtChannel>> myChannels(String token) async {
    final j = await http_.send(
      'GET',
      Uri.parse('$_base/channels?part=snippet,statistics,contentDetails&mine=true&maxResults=50'),
      headers: _h(token),
    );
    final items = (j['items'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    return items.map((it) {
      final sn = it['snippet'] as Map<String, dynamic>? ?? const {};
      final st = it['statistics'] as Map<String, dynamic>? ?? const {};
      final cd = it['contentDetails'] as Map<String, dynamic>? ?? const {};
      final rel = cd['relatedPlaylists'] as Map<String, dynamic>? ?? const {};
      final thumbs = sn['thumbnails'] as Map<String, dynamic>? ?? const {};
      final def = thumbs['default'] as Map<String, dynamic>? ?? const {};
      final handle = (sn['customUrl'] as String?) ?? '';
      final id = it['id'] as String;
      return YtChannel(
        channelId: id,
        title: (sn['title'] as String?) ?? '',
        url: handle.isNotEmpty ? 'https://www.youtube.com/$handle' : 'https://www.youtube.com/channel/$id',
        handle: handle,
        thumbnail: (def['url'] as String?) ?? '',
        subscriberCount: int.tryParse('${st['subscriberCount'] ?? 0}') ?? 0,
        videoCount: int.tryParse('${st['videoCount'] ?? 0}') ?? 0,
        viewCount: int.tryParse('${st['viewCount'] ?? 0}') ?? 0,
        uploadsPlaylist: (rel['uploads'] as String?) ?? '',
      );
    }).toList();
  }

  @override
  Future<VideoPage> listUploads(String token, String uploadsPlaylistId, {String? pageToken}) async {
    final q = {'part': 'contentDetails', 'playlistId': uploadsPlaylistId, 'maxResults': '50', 'pageToken': ?pageToken};
    final j = await http_.send(
      'GET',
      Uri.parse('$_base/playlistItems').replace(queryParameters: q),
      headers: _h(token),
    );
    final items = (j['items'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    return VideoPage(
      items
          .map((e) => ((e['contentDetails'] as Map<String, dynamic>?)?['videoId'] as String?) ?? '')
          .where((e) => e.isNotEmpty)
          .toList(),
      j['nextPageToken'] as String?,
    );
  }

  @override
  Future<List<YtVideo>> videosByIds(String token, List<String> ids) async {
    if (ids.isEmpty) return [];
    final q = {'part': 'snippet,statistics,status', 'id': ids.take(50).join(','), 'maxResults': '50'};
    final j = await http_.send('GET', Uri.parse('$_base/videos').replace(queryParameters: q), headers: _h(token));
    final items = (j['items'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    return items.map(_videoFromJson).toList();
  }

  static YtVideo _videoFromJson(Map<String, dynamic> it) {
    final sn = it['snippet'] as Map<String, dynamic>? ?? const {};
    final st = it['statistics'] as Map<String, dynamic>? ?? const {};
    final status = it['status'] as Map<String, dynamic>? ?? const {};
    final thumbs = sn['thumbnails'] as Map<String, dynamic>? ?? const {};
    final med = (thumbs['medium'] ?? thumbs['default']) as Map<String, dynamic>? ?? const {};
    return YtVideo(
      videoId: it['id'] as String,
      channelId: (sn['channelId'] as String?) ?? '',
      title: (sn['title'] as String?) ?? '',
      description: (sn['description'] as String?) ?? '',
      tags: ((sn['tags'] as List<dynamic>?) ?? const []).map((e) => '$e').toList(),
      thumbnailUrl: (med['url'] as String?) ?? '',
      viewCount: int.tryParse('${st['viewCount'] ?? 0}') ?? 0,
      publishedAt: (sn['publishedAt'] as String?) ?? '',
      privacy: (status['privacyStatus'] as String?) ?? 'public',
      categoryId: (sn['categoryId'] as String?) ?? '22',
    );
  }

  @override
  Future<YtVideo> updateMeta(String token, YtVideo current, VideoMeta meta) async {
    // part=snippet 만 보낸다 → 공개 범위(status)는 바뀌지 않는다.
    final body = {
      'id': current.videoId,
      'snippet': {
        'title': meta.title,
        'description': meta.description,
        'tags': meta.tags,
        'categoryId': current.categoryId,
      },
    };
    final j = await http_.send('PUT', Uri.parse('$_base/videos?part=snippet'), headers: _h(token), body: body);
    final sn = j['snippet'] as Map<String, dynamic>? ?? const {};
    return current.copyWith(
      title: (sn['title'] as String?) ?? meta.title,
      description: (sn['description'] as String?) ?? meta.description,
      tags: ((sn['tags'] as List<dynamic>?) ?? meta.tags).map((e) => '$e').toList(),
    );
  }

  @override
  Future<void> setThumbnail(String token, String videoId, File png) async {
    await http_.send(
      'POST',
      Uri.parse('https://www.googleapis.com/upload/youtube/v3/thumbnails/set?videoId=$videoId'),
      headers: {..._h(token), 'content-type': 'image/png'},
      body: await png.readAsBytes(),
    );
  }

  @override
  Future<String> uploadPrivate(String token, String channelId, File file, UploadMeta meta) async {
    final length = await file.length();
    final metadata = {
      'snippet': {
        'title': meta.title,
        'description': meta.description,
        'tags': meta.tags,
        'categoryId': meta.categoryId,
      },
      'status': {
        // 안전 규칙: 항상 비공개. 사용자가 유튜브에서 확인 후 직접 공개한다.
        'privacyStatus': 'private',
        'selfDeclaredMadeForKids': false,
        'containsSyntheticMedia': meta.containsSyntheticMedia,
      },
    };
    // 1) 이어 올리기(resumable) 세션 시작
    final start = await withRetry(
      () => rawClient.post(
        Uri.parse('https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status'),
        headers: {
          ..._h(token),
          'content-type': 'application/json; charset=utf-8',
          'x-upload-content-length': '$length',
          'x-upload-content-type': 'video/*',
        },
        body: jsonEncode(metadata),
      ),
    );
    if (start.statusCode >= 300) throw classifyHttpError(start.statusCode, start.body);
    final location = start.headers['location'];
    if (location == null) throw AppFailure(FailureKind.unknown, 'no upload location');
    // 2) 파일 보내기
    final req = http.StreamedRequest('PUT', Uri.parse(location));
    req.headers['content-type'] = 'video/*';
    req.contentLength = length;
    file.openRead().listen(req.sink.add, onDone: req.sink.close, onError: req.sink.addError);
    final res = await http.Response.fromStream(await rawClient.send(req).timeout(const Duration(hours: 2)));
    if (res.statusCode >= 300) throw classifyHttpError(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return j['id'] as String;
  }
}
