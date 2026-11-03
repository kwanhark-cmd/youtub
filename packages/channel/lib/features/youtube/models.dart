import 'dart:convert';

class YtChannel {
  YtChannel({
    required this.channelId,
    required this.title,
    this.url = '',
    this.thumbnail = '',
    this.subscriberCount = 0,
    this.videoCount = 0,
    this.viewCount = 0,
    this.uploadsPlaylist = '',
    this.handle = '',
  });

  final String channelId;
  final String title;
  String url;
  final String thumbnail;
  final int subscriberCount;
  final int videoCount;
  final int viewCount;
  final String uploadsPlaylist;
  final String handle;
}

class YtVideo {
  YtVideo({
    required this.videoId,
    required this.channelId,
    required this.title,
    this.description = '',
    this.tags = const [],
    this.thumbnailUrl = '',
    this.viewCount = 0,
    this.publishedAt = '',
    this.privacy = 'public',
    this.categoryId = '22',
  });

  final String videoId;
  final String channelId;
  final String title;
  final String description;
  final List<String> tags;
  final String thumbnailUrl;
  final int viewCount;
  final String publishedAt;
  final String privacy;
  final String categoryId;

  VideoMeta get meta => VideoMeta(title: title, description: description, tags: tags);

  YtVideo copyWith({String? title, String? description, List<String>? tags, int? viewCount, String? privacy}) =>
      YtVideo(
        videoId: videoId,
        channelId: channelId,
        title: title ?? this.title,
        description: description ?? this.description,
        tags: tags ?? this.tags,
        thumbnailUrl: thumbnailUrl,
        viewCount: viewCount ?? this.viewCount,
        publishedAt: publishedAt,
        privacy: privacy ?? this.privacy,
        categoryId: categoryId,
      );
}

/// 수정 대상이 되는 글자 정보 (제목, 설명, 키워드).
class VideoMeta {
  const VideoMeta({required this.title, required this.description, required this.tags});
  final String title;
  final String description;
  final List<String> tags;

  Map<String, dynamic> toJson() => {'title': title, 'description': description, 'tags': tags};

  factory VideoMeta.fromJson(Map<String, dynamic> j) => VideoMeta(
    title: (j['title'] as String?) ?? '',
    description: (j['description'] as String?) ?? '',
    tags: ((j['tags'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList(),
  );

  String encode() => jsonEncode(toJson());
  static VideoMeta decode(String s) => VideoMeta.fromJson(jsonDecode(s) as Map<String, dynamic>);

  bool sameAs(VideoMeta o) =>
      title == o.title && description == o.description && tags.join('\u0001') == o.tags.join('\u0001');
}

class VideoPage {
  VideoPage(this.videoIds, this.nextPageToken);
  final List<String> videoIds;
  final String? nextPageToken;
}

/// 업로드할 때의 정보. 공개 범위는 항상 비공개라서 필드 자체가 없다.
class UploadMeta {
  UploadMeta({
    required this.title,
    required this.description,
    required this.tags,
    this.categoryId = '22',
    this.containsSyntheticMedia = false,
  });
  final String title;
  final String description;
  final List<String> tags;
  final String categoryId;

  /// 업로드 설정의 "AI 로 만든 콘텐츠" 항목.
  final bool containsSyntheticMedia;
}

/// 유튜브 API 사용량(단위). 하루 기본 10,000.
class QuotaCost {
  static const list = 1;
  static const update = 50;
  static const upload = 1600;
  static const thumbnail = 50;
}
