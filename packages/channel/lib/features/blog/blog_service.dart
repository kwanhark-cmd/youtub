import 'dart:convert';

import '../../core/db.dart';
import '../../core/failure.dart';
import '../../core/logger.dart';
import '../../core/oauth.dart';
import '../../core/retry.dart';
import '../../core/strings.dart';
import '../ai/brain.dart';
import '../production/production_service.dart' show ProductionBlocked;
import '../edits/edit_service.dart';
import '../settings/user_settings.dart';
import '../youtube/models.dart';
import '../youtube/youtube_service.dart';
import 'blogger_api.dart';

class BlogSite {
  BlogSite(this.row);
  final Map<String, dynamic> row;
  int get id => row['id'] as int;
  String get platform => row['platform'] as String; // 'blogger' | 'tistory'
  String get blogId => row['blog_id'] as String;
  String get title => row['title'] as String;
  String get url => row['url'] as String;
  int get accountId => row['account_id'] as int;
  StyleCard? get style => StyleCard.decode(row['style_json'] as String?);
  bool get isTistory => platform == 'tistory';
}

class BlogDraftRow {
  BlogDraftRow(this.row);
  final Map<String, dynamic> row;
  int get id => row['id'] as int;
  int get siteId => row['site_id'] as int;
  String get title => row['title'] as String;
  String get html => row['html'] as String;
  List<String> get tags => (jsonDecode(row['tags_json'] as String) as List<dynamic>).map((e) => '$e').toList();

  /// 'copyReady'(티스토리: 복사해서 올리기) | 'postedByUser' | 'draftOnBlogger'(구글 블로그 초안) | 'publishedByUser'
  String get status => row['status'] as String;
  String get remotePostId => row['remote_post_id'] as String;
}

/// 3단계: 구글 블로그(자동 분석·수정·초안 업로드), 티스토리(글 완성 + 복사 버튼, 자동 게시 없음).
class BlogService {
  BlogService({
    required this.db,
    required this.youtube,
    required this.realApi,
    required this.mockApi,
    required this.tokens,
    required this.oauth,
    required this.brain,
    required this.editLog,
    required this.settings,
    required this.now,
    this.logger,
  });

  final AppDatabase db;
  final YouTubeService youtube;
  final BloggerApi realApi;
  final MockBloggerApi mockApi;
  final TokenManager tokens;
  final OAuthFlow? oauth;
  final Brain brain;
  final EditLog editLog;
  final UserSettings settings;
  final DateTime Function() now;
  final AppLogger? logger;

  // ---------------- 블로그 등록 ----------------
  List<BlogSite> sites() =>
      db.select('SELECT * FROM blog_sites ORDER BY id').map((r) => BlogSite(Map<String, dynamic>.from(r))).toList();

  BlogSite? site(int id) {
    final r = db.select('SELECT * FROM blog_sites WHERE id = ?', [id]);
    return r.isEmpty ? null : BlogSite(Map<String, dynamic>.from(r.first));
  }

  bool _isMock(BlogSite s) => youtube.account(s.accountId)?.mock ?? true;
  BloggerApi _api(BlogSite s) => _isMock(s) ? mockApi : realApi;

  Future<String> _token(BlogSite s) async {
    final a = youtube.account(s.accountId);
    if (a == null) throw AppFailure(FailureKind.notConnected, 'account');
    if (a.mock) return 'mock';
    try {
      return await tokens.accessToken(a.id, await youtube.googleConfig());
    } on AppFailure catch (e) {
      if (e.kind == FailureKind.permissionRevoked) {
        db.execute("UPDATE accounts SET status = 'revoked' WHERE id = ?", [a.id]);
      }
      rethrow;
    }
  }

  /// 구글로 연결해 그 계정의 블로그를 모두 등록. 연습 모드면 가짜 블로그.
  Future<List<BlogSite>> connectBlogger() async {
    final mock = youtube.isPracticeMode;
    final accountId = db.insert('INSERT INTO accounts(provider, label, connected_at, status, mock) VALUES(?,?,?,?,?)', [
      'google',
      mock ? '연습용 블로그 계정' : '구글 블로그 계정',
      now().toIso8601String(),
      'ok',
      mock ? 1 : 0,
    ]);
    try {
      if (!mock) {
        final flow = oauth;
        if (flow == null) throw AppFailure(FailureKind.notConnected);
        await tokens.save(accountId, await flow.authorize(await youtube.googleConfig()));
      }
      final token = mock ? 'mock' : await tokens.accessToken(accountId, await youtube.googleConfig());
      final blogs = await withRetry(() => (mock ? mockApi : realApi).myBlogs(token));
      if (blogs.isEmpty) throw AppFailure(FailureKind.notFound, 'no blogs');
      for (final b in blogs) {
        final exists = db.select("SELECT id FROM blog_sites WHERE platform='blogger' AND blog_id = ?", [b.id]);
        if (exists.isEmpty) {
          db.insert(
            "INSERT INTO blog_sites(platform, blog_id, title, url, account_id, added_at) VALUES('blogger',?,?,?,?,?)",
            [b.id, b.name, b.url, accountId, now().toIso8601String()],
          );
        } else {
          db.execute('UPDATE blog_sites SET account_id = ?, title = ? WHERE id = ?', [
            accountId,
            b.name,
            exists.first['id'],
          ]);
        }
      }
      return sites().where((s) => s.accountId == accountId).toList();
    } catch (_) {
      await tokens.remove(accountId);
      db.execute('DELETE FROM accounts WHERE id = ?', [accountId]);
      rethrow;
    }
  }

  /// 티스토리는 공식 API 가 끝나 이름·주소만 등록한다 (자동 게시 없음).
  BlogSite addTistory(String name, String url) {
    if (name.trim().isEmpty) throw AppFailure(FailureKind.invalidInput, 'name');
    final id = db.insert("INSERT INTO blog_sites(platform, title, url, added_at) VALUES('tistory', ?, ?, ?)", [
      name.trim(),
      url.trim(),
      now().toIso8601String(),
    ]);
    return site(id)!;
  }

  Future<void> removeSite(int id) async {
    final s = site(id);
    if (s == null) return;
    db.transaction(() {
      db.execute('DELETE FROM posts WHERE site_id = ?', [id]);
      db.execute('DELETE FROM blog_drafts WHERE site_id = ?', [id]);
      db.execute('DELETE FROM blog_sites WHERE id = ?', [id]);
    });
    if (!s.isTistory) {
      final inUse = db.select(
        'SELECT 1 FROM blog_sites WHERE account_id = ? UNION SELECT 1 FROM channels WHERE account_id = ?',
        [s.accountId, s.accountId],
      );
      if (inUse.isEmpty) {
        await tokens.remove(s.accountId);
        db.execute('DELETE FROM accounts WHERE id = ?', [s.accountId]);
      }
    }
  }

  // ---------------- 글 불러오기·분석 ----------------
  Future<int> syncPosts(int siteId, {CancelToken? cancel, void Function(double, String)? progress}) async {
    final s = site(siteId)!;
    if (s.isTistory) return 0;
    final token = await _token(s);
    var count = 0;
    String? page;
    do {
      cancel?.throwIfCancelled();
      final p = await withRetry(() => _api(s).posts(token, s.blogId, pageToken: page), cancel: cancel);
      db.transaction(() {
        for (final post in p.posts) {
          _savePost(siteId, post);
        }
      });
      count += p.posts.length;
      page = p.next;
      progress?.call(0, '글 $count개 불러옴');
    } while (page != null);
    return count;
  }

  void _savePost(int siteId, BlogPost p) => db.execute(
    '''INSERT INTO posts(site_id, post_id, title, content, labels_json, url, published_at, updated_at) VALUES(?,?,?,?,?,?,?,?)
           ON CONFLICT(site_id, post_id) DO UPDATE SET title=excluded.title, content=excluded.content,
             labels_json=excluded.labels_json, url=excluded.url, updated_at=excluded.updated_at''',
    [siteId, p.id, p.title, p.content, jsonEncode(p.labels), p.url, p.published, now().toIso8601String()],
  );

  List<BlogPost> posts(int siteId, {int offset = 0, int limit = 30}) => db
      .select('SELECT * FROM posts WHERE site_id = ? ORDER BY published_at DESC LIMIT ? OFFSET ?', [
        siteId,
        limit,
        offset,
      ])
      .map(_postRow)
      .toList();

  int postTotal(int siteId) =>
      db.select('SELECT COUNT(*) AS n FROM posts WHERE site_id = ?', [siteId]).first['n'] as int;

  BlogPost? post(int siteId, String postId) {
    final r = db.select('SELECT * FROM posts WHERE site_id = ? AND post_id = ?', [siteId, postId]);
    return r.isEmpty ? null : _postRow(r.first);
  }

  static BlogPost _postRow(Map<String, dynamic> r) => BlogPost(
    id: r['post_id'] as String,
    title: r['title'] as String,
    content: r['content'] as String,
    labels: (jsonDecode(r['labels_json'] as String) as List<dynamic>).map((e) => '$e').toList(),
    url: r['url'] as String,
    published: r['published_at'] as String,
  );

  Future<StyleCard> analyze(int siteId) async {
    final s = site(siteId)!;
    final list = posts(siteId, limit: 30);
    final card = s.isTistory && list.isEmpty
        ? Brain.mockStyle(s.title, const [])
        : await brain.analyzeStyle(
            s.title,
            list
                .map(
                  (p) => YtVideo(
                    videoId: p.id,
                    channelId: '',
                    title: p.title,
                    description: p.content.replaceAll(RegExp(r'<[^>]+>'), ' '),
                    tags: p.labels,
                  ),
                )
                .toList(),
          );
    saveStyle(siteId, card);
    return card;
  }

  void saveStyle(int siteId, StyleCard c) =>
      db.execute('UPDATE blog_sites SET style_json = ? WHERE id = ?', [c.encode(), siteId]);

  StyleCard _style(BlogSite s) =>
      s.style ?? Brain.mockStyle(s.title, posts(s.id, limit: 30).map((p) => p.title).toList());

  // ---------------- 기존 글 자동 수정 (제목·라벨) + 되돌리기 ----------------
  int remainingEditsToday(int siteId) {
    final limit = settings.effectiveEditsPerDay(now());
    return (limit - editLog.countOn(dayKey(now()), parentId: 'blog$siteId', targetType: 'post')).clamp(0, limit);
  }

  static VideoMeta _meta(BlogPost p) => VideoMeta(title: p.title, description: '', tags: p.labels);

  /// 하루 수정 개수 안에서 제목·라벨을 다듬는다. 바꾸기 전 원본을 먼저 기록한다.
  Future<int> runEdits(int siteId, {CancelToken? cancel}) async {
    final s = site(siteId)!;
    if (s.isTistory) return 0;
    var n = remainingEditsToday(siteId);
    if (n <= 0) return 0;
    final recent = editLog.recentlyEdited('post', 30);
    final style = _style(s);
    var done = 0;
    for (final p in posts(siteId, limit: 500).reversed) {
      if (n <= 0) break;
      cancel?.throwIfCancelled();
      if (recent.contains('$siteId/${p.id}')) continue;
      final sug = await brain.suggestPostMeta(p.title, p.labels, style);
      if (sug == null) continue;
      final after = VideoMeta(title: sug.title, description: '', tags: sug.labels);
      final id = editLog.record(
        targetType: 'post',
        targetId: '$siteId/${p.id}',
        parentId: 'blog$siteId',
        before: _meta(p),
        after: after,
        viewsBefore: 0,
        status: EditStatus.failed,
        reason: '진행 중',
      );
      try {
        final np = await withRetry(
          () async => _api(s).patchTitleLabels(await _token(s), s.blogId, p.id, after.title, after.tags),
        );
        _savePost(siteId, np);
        editLog.setStatus(id, EditStatus.applied);
        done++;
        n--;
      } on AppFailure catch (e) {
        editLog.setStatus(id, EditStatus.failed, reason: e.userMessage);
        if (e.kind == FailureKind.quotaExceeded) break;
      }
    }
    return done;
  }

  Future<RevertResult> revert(int editId, {bool force = false}) async {
    final e = editLog.byId(editId);
    if (e == null || e.targetType != 'post') {
      return RevertResult(RevertOutcome.failed, AppFailure(FailureKind.notFound));
    }
    if (e.status == EditStatus.reverted) return RevertResult(RevertOutcome.alreadyReverted);
    if (e.status == EditStatus.failed) {
      editLog.setStatus(e.id, EditStatus.reverted, reason: '반영되지 않았던 수정');
      return RevertResult(RevertOutcome.alreadyReverted);
    }
    if (editLog.hasNewerApplied(e)) return RevertResult(RevertOutcome.newerEditExists);
    final parts = e.targetId.split('/');
    final s = site(int.parse(parts[0]));
    if (s == null) return RevertResult(RevertOutcome.failed, AppFailure(FailureKind.notFound));
    try {
      final token = await _token(s);
      if (!force) {
        final remote = await withRetry(() => _api(s).getPost(token, s.blogId, parts[1]));
        if (!_meta(remote).sameAs(e.after)) return RevertResult(RevertOutcome.conflict);
      }
      final np = await withRetry(
        () => _api(s).patchTitleLabels(token, s.blogId, parts[1], e.before.title, e.before.tags),
      );
      _savePost(s.id, np);
      editLog.setStatus(e.id, EditStatus.reverted);
      return RevertResult(RevertOutcome.reverted);
    } on AppFailure catch (f) {
      return RevertResult(RevertOutcome.failed, f);
    }
  }

  // ---------------- 새 글 (구글 블로그: 초안 / 티스토리: 복사) ----------------
  int draftsToday(int siteId) =>
      db.select('SELECT COUNT(*) AS n FROM blog_drafts WHERE site_id = ? AND day = ?', [
            siteId,
            dayKey(now()),
          ]).first['n']
          as int;

  /// 하루 1~2개까지만 만든다. 구글 블로그는 초안(비공개)으로 올리고, 티스토리는 복사 준비만.
  Future<BlogDraftRow> newPost(int siteId, {String topic = ''}) async {
    final s = site(siteId)!;
    if (draftsToday(siteId) >= settings.blogPostsPerDay) {
      throw ProductionBlocked('오늘 이 블로그에 만들 수 있는 새 글 개수를 다 썼어요. ${S.blogPerDay}');
    }
    final d = await brain.writeBlogPost(_style(s), topic);
    var status = 'copyReady';
    var remote = '';
    if (!s.isTistory) {
      remote = await withRetry(() async => _api(s).insertDraft(await _token(s), s.blogId, d.title, d.html, d.tags));
      status = 'draftOnBlogger';
    }
    final id = db.insert(
      'INSERT INTO blog_drafts(site_id, title, html, tags_json, status, remote_post_id, day, created_at) VALUES(?,?,?,?,?,?,?,?)',
      [siteId, d.title, d.html, jsonEncode(d.tags), status, remote, dayKey(now()), now().toIso8601String()],
    );
    return draft(id)!;
  }

  BlogDraftRow? draft(int id) {
    final r = db.select('SELECT * FROM blog_drafts WHERE id = ?', [id]);
    return r.isEmpty ? null : BlogDraftRow(Map<String, dynamic>.from(r.first));
  }

  List<BlogDraftRow> drafts(int siteId) => db
      .select('SELECT * FROM blog_drafts WHERE site_id = ? ORDER BY id DESC LIMIT 100', [siteId])
      .map((r) => BlogDraftRow(Map<String, dynamic>.from(r)))
      .toList();

  void markDraftDone(int id) {
    final d = draft(id)!;
    db.execute('UPDATE blog_drafts SET status = ? WHERE id = ?', [
      d.status == 'copyReady' ? 'postedByUser' : 'publishedByUser',
      id,
    ]);
  }

  String bloggerEditUrl(BlogSite s, String postId) => 'https://www.blogger.com/blog/post/edit/${s.blogId}/$postId';

  /// 티스토리에 붙여 넣기 좋은 본문 (HTML 그대로).
  static String tistoryBody(BlogDraftRow d) => d.html;
  static String tistoryTags(BlogDraftRow d) => d.tags.join(', ');

  // ---------------- 자동 작업 ----------------
  Future<String> dailyTask(CancelToken cancel) async {
    var edited = 0;
    for (final s in sites().where((s) => !s.isTistory)) {
      if (cancel.isCancelled) break;
      try {
        await syncPosts(s.id, cancel: cancel);
        edited += await runEdits(s.id, cancel: cancel);
      } on AppFailure catch (e) {
        if (e.kind == FailureKind.cancelled) break;
        logger?.warn('블로그 작업 실패: ${e.kind.name}');
      }
    }
    return '블로그 글 $edited개를 다듬었어요';
  }

  List<String> briefingItems() {
    final out = <String>[];
    final waiting =
        db.select("SELECT COUNT(*) AS n FROM blog_drafts WHERE status IN ('copyReady','draftOnBlogger')").first['n']
            as int;
    if (waiting > 0) out.add('확인을 기다리는 블로그 새 글이 $waiting개 있어요');
    return out;
  }
}
