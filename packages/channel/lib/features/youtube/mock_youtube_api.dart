import 'dart:io';

import '../../core/failure.dart';
import 'models.dart';
import 'youtube_api.dart';

/// 연습 모드와 테스트에서 쓰는 가짜 유튜브. 실제 유튜브에는 아무 영향이 없다.
class MockYouTubeApi implements YouTubeApi {
  MockYouTubeApi({int videosPerChannel = 24, int bigChannelVideos = 120, bool emptyChannel = false}) {
    _seed(videosPerChannel, bigChannelVideos);
    if (emptyChannel) {
      // 영상이 하나도 없는 채널 (테스트용)
      channels['UC_mock_empty'] = YtChannel(
        channelId: 'UC_mock_empty',
        title: '새로 만든 빈 채널',
        uploadsPlaylist: 'UUUC_mock_empty',
      );
      uploads['UUUC_mock_empty'] = [];
    }
  }

  /// 테스트용: 채널이 하나도 없는 구글 계정처럼 동작.
  bool noChannels = false;

  final Map<String, YtChannel> channels = {};
  final Map<String, YtVideo> videos = {};
  final Map<String, List<String>> uploads = {};
  int calls = 0;
  int updateCalls = 0;
  int uploadCalls = 0;

  /// 테스트용: 다음 호출을 일부러 실패시키기.
  final List<FailureKind> failNext = [];

  static const _topics = {
    'UC_mock_cook': ('집밥 요리 교실', ['김치찌개', '된장국', '계란말이', '불고기', '잡채', '떡볶이', '비빔밥', '닭볶음탕']),
    'UC_mock_trip': ('느린 여행 일기', ['제주 올레길', '부산 해운대', '강릉 커피거리', '전주 한옥마을', '경주 야경', '남해 독일마을']),
    'UC_mock_money': ('알뜰 재테크 이야기', ['적금 비교', '가계부 쓰는 법', '연말정산', '주식 기초', '절약 습관', '노후 준비']),
  };

  void _seed(int perChannel, int big) {
    var n = 0;
    _topics.forEach((id, v) {
      final (title, words) = v;
      final count = id == 'UC_mock_cook' ? big : perChannel;
      channels[id] = YtChannel(
        channelId: id,
        title: title,
        url: 'https://www.youtube.com/@$id',
        handle: '@$id',
        subscriberCount: 1200 + n * 3000,
        videoCount: count,
        viewCount: 0,
        uploadsPlaylist: 'UU$id',
      );
      final list = <String>[];
      for (var i = 0; i < count; i++) {
        final w = words[i % words.length];
        final vid = '${id}_v$i';
        final day = DateTime.utc(2026, 1, 1).add(Duration(days: i * 2));
        videos[vid] = YtVideo(
          videoId: vid,
          channelId: id,
          title: i.isEven ? '$w 만들기 $i편' : '$w ($i)',
          description: i % 3 == 0 ? '' : '$w 영상입니다.',
          tags: i % 4 == 0 ? const [] : [w],
          viewCount: 100 + (i * 37) % 900,
          publishedAt: day.toIso8601String(),
        );
        list.add(vid);
      }
      uploads['UU$id'] = list.reversed.toList();
      n++;
    });
  }

  void _maybeFail() {
    calls++;
    if (failNext.isNotEmpty) throw AppFailure(failNext.removeAt(0), 'mock failure');
  }

  @override
  Future<List<YtChannel>> myChannels(String token) async {
    _maybeFail();
    if (noChannels) return [];
    return channels.values.map((c) {
      final total = (uploads[c.uploadsPlaylist] ?? const []).fold<int>(0, (s, id) => s + (videos[id]?.viewCount ?? 0));
      return YtChannel(
        channelId: c.channelId,
        title: c.title,
        url: c.url,
        handle: c.handle,
        subscriberCount: c.subscriberCount,
        videoCount: uploads[c.uploadsPlaylist]?.length ?? 0,
        viewCount: total,
        uploadsPlaylist: c.uploadsPlaylist,
      );
    }).toList();
  }

  @override
  Future<VideoPage> listUploads(String token, String uploadsPlaylistId, {String? pageToken}) async {
    _maybeFail();
    final all = uploads[uploadsPlaylistId] ?? const [];
    final start = int.tryParse(pageToken ?? '0') ?? 0;
    final end = (start + 50).clamp(0, all.length);
    return VideoPage(all.sublist(start, end), end < all.length ? '$end' : null);
  }

  @override
  Future<List<YtVideo>> videosByIds(String token, List<String> ids) async {
    _maybeFail();
    return ids.map((i) => videos[i]).whereType<YtVideo>().toList();
  }

  @override
  Future<YtVideo> updateMeta(String token, YtVideo current, VideoMeta meta) async {
    _maybeFail();
    updateCalls++;
    final v = videos[current.videoId];
    if (v == null) throw AppFailure(FailureKind.notFound, 'no video');
    final nv = v.copyWith(title: meta.title, description: meta.description, tags: meta.tags);
    videos[v.videoId] = nv;
    return nv;
  }

  @override
  Future<String> uploadPrivate(String token, String channelId, File file, UploadMeta meta) async {
    _maybeFail();
    uploadCalls++;
    final ch = channels[channelId] ?? channels.values.first;
    final id = 'mock_upload_${videos.length}';
    videos[id] = YtVideo(
      videoId: id,
      channelId: ch.channelId,
      title: meta.title,
      description: meta.description,
      tags: meta.tags,
      privacy: 'private',
      publishedAt: DateTime.now().toUtc().toIso8601String(),
    );
    uploads[ch.uploadsPlaylist]!.insert(0, id);
    return id;
  }

  final Map<String, String> thumbnails = {};

  /// 테스트용: 썸네일 올리기만 실패시키기 (예: 인증 안 된 채널).
  bool failThumbnail = false;

  @override
  Future<void> setThumbnail(String token, String videoId, File png) async {
    _maybeFail();
    if (failThumbnail) throw AppFailure(FailureKind.permissionRevoked, 'thumbnail not allowed');
    thumbnails[videoId] = png.path;
  }

  /// 테스트용: 사용자가 유튜브에서 직접 내용을 바꾼 상황.
  void externalEdit(String videoId, String title) {
    videos[videoId] = videos[videoId]!.copyWith(title: title);
  }

  /// 테스트용: 하루가 지나 조회수가 늘어난 상황.
  void addViews(int n) {
    videos.updateAll((k, v) => v.copyWith(viewCount: v.viewCount + n));
  }
}
