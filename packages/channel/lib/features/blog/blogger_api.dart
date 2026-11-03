import '../../core/failure.dart';
import '../../core/http_json.dart';

class BlogInfo {
  BlogInfo(this.id, this.name, this.url);
  final String id;
  final String name;
  final String url;
}

class BlogPost {
  BlogPost({
    required this.id,
    required this.title,
    this.content = '',
    this.labels = const [],
    this.url = '',
    this.published = '',
    this.status = 'LIVE',
  });
  final String id;
  final String title;
  final String content;
  final List<String> labels;
  final String url;
  final String published;
  final String status;

  BlogPost copyWith({String? title, List<String>? labels}) => BlogPost(
    id: id,
    title: title ?? this.title,
    content: content,
    labels: labels ?? this.labels,
    url: url,
    published: published,
    status: status,
  );
}

class PostPage {
  PostPage(this.posts, this.next);
  final List<BlogPost> posts;
  final String? next;
}

/// 구글 블로그(Blogger API v3). 안전을 위해 "삭제" 와 "게시(공개)" 기능은 만들지 않았다.
/// 새 글은 항상 초안(isDraft=true)으로만 올린다.
abstract class BloggerApi {
  Future<List<BlogInfo>> myBlogs(String token);
  Future<PostPage> posts(String token, String blogId, {String? pageToken});
  Future<BlogPost> getPost(String token, String blogId, String postId);

  /// 제목과 라벨만 바꾼다 (본문·공개 상태는 건드리지 않음).
  Future<BlogPost> patchTitleLabels(String token, String blogId, String postId, String title, List<String> labels);

  /// 초안으로만 올린다. 돌려주는 값은 새 글 ID.
  Future<String> insertDraft(String token, String blogId, String title, String html, List<String> labels);
}

class RealBloggerApi implements BloggerApi {
  RealBloggerApi(this.http);
  final JsonHttp http;
  static const _base = 'https://www.googleapis.com/blogger/v3';
  Map<String, String> _h(String t) => {'authorization': 'Bearer $t'};

  static BlogPost _post(Map<String, dynamic> j) => BlogPost(
    id: '${j['id']}',
    title: (j['title'] as String?) ?? '',
    content: (j['content'] as String?) ?? '',
    labels: ((j['labels'] as List<dynamic>?) ?? const []).map((e) => '$e').toList(),
    url: (j['url'] as String?) ?? '',
    published: (j['published'] as String?) ?? '',
    status: (j['status'] as String?) ?? 'LIVE',
  );

  @override
  Future<List<BlogInfo>> myBlogs(String token) async {
    final j = await http.send('GET', Uri.parse('$_base/users/self/blogs'), headers: _h(token));
    return ((j['items'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((b) => BlogInfo('${b['id']}', (b['name'] as String?) ?? '', (b['url'] as String?) ?? ''))
        .toList();
  }

  @override
  Future<PostPage> posts(String token, String blogId, {String? pageToken}) async {
    final q = {'maxResults': '20', 'fetchBodies': 'true', 'status': 'live', 'pageToken': ?pageToken};
    final j = await http.send(
      'GET',
      Uri.parse('$_base/blogs/$blogId/posts').replace(queryParameters: q),
      headers: _h(token),
    );
    return PostPage(
      ((j['items'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>().map(_post).toList(),
      j['nextPageToken'] as String?,
    );
  }

  @override
  Future<BlogPost> getPost(String token, String blogId, String postId) async =>
      _post(await http.send('GET', Uri.parse('$_base/blogs/$blogId/posts/$postId'), headers: _h(token)));

  @override
  Future<BlogPost> patchTitleLabels(
    String token,
    String blogId,
    String postId,
    String title,
    List<String> labels,
  ) async => _post(
    await http.send(
      'PATCH',
      Uri.parse('$_base/blogs/$blogId/posts/$postId'),
      headers: _h(token),
      body: {'title': title, 'labels': labels},
    ),
  );

  @override
  Future<String> insertDraft(String token, String blogId, String title, String html, List<String> labels) async {
    final j = await http.send(
      'POST',
      Uri.parse('$_base/blogs/$blogId/posts?isDraft=true'),
      headers: _h(token),
      body: {'kind': 'blogger#post', 'title': title, 'content': html, 'labels': labels},
    );
    return '${j['id']}';
  }
}

/// 연습 모드·테스트용 가짜 블로그.
class MockBloggerApi implements BloggerApi {
  MockBloggerApi() {
    const topics = ['정리수납', '살림 꿀팁', '집밥 기록', '절약 생활', '화분 키우기'];
    for (var i = 0; i < 25; i++) {
      final t = topics[i % topics.length];
      posts_['p$i'] = BlogPost(
        id: 'p$i',
        title: '$t 이야기 $i',
        content: '<p>$t 에 대한 글입니다.</p>',
        labels: i.isEven ? [t] : const [],
        url: 'https://mock.blogspot.com/p$i.html',
        published: DateTime.utc(2026, 1, 1).add(Duration(days: i)).toIso8601String(),
      );
    }
  }

  final Map<String, BlogPost> posts_ = {};
  final List<String> failNext = [];
  int patchCalls = 0;
  int draftCalls = 0;

  void _fail() {
    if (failNext.isNotEmpty) throw AppFailure(FailureKind.values.byName(failNext.removeAt(0)));
  }

  @override
  Future<List<BlogInfo>> myBlogs(String token) async {
    _fail();
    return [BlogInfo('mockblog1', '우리집 살림 블로그', 'https://mock.blogspot.com')];
  }

  @override
  Future<PostPage> posts(String token, String blogId, {String? pageToken}) async {
    _fail();
    final live = posts_.values.where((p) => p.status == 'LIVE').toList();
    final start = int.tryParse(pageToken ?? '0') ?? 0;
    final end = (start + 20).clamp(0, live.length);
    return PostPage(live.sublist(start, end), end < live.length ? '$end' : null);
  }

  @override
  Future<BlogPost> getPost(String token, String blogId, String postId) async {
    _fail();
    final p = posts_[postId];
    if (p == null) throw AppFailure(FailureKind.notFound);
    return p;
  }

  @override
  Future<BlogPost> patchTitleLabels(
    String token,
    String blogId,
    String postId,
    String title,
    List<String> labels,
  ) async {
    _fail();
    patchCalls++;
    final p = posts_[postId]!.copyWith(title: title, labels: labels);
    posts_[postId] = p;
    return p;
  }

  @override
  Future<String> insertDraft(String token, String blogId, String title, String html, List<String> labels) async {
    _fail();
    draftCalls++;
    final id = 'draft${posts_.length}';
    posts_[id] = BlogPost(id: id, title: title, content: html, labels: labels, status: 'DRAFT');
    return id;
  }
}
