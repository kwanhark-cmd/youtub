import 'dart:convert';
import 'dart:io';

import '../../core/db.dart';
import '../../core/failure.dart';
import '../../core/logger.dart';
import '../../core/oauth.dart';
import '../../core/retry.dart';
import '../../core/secret_store.dart';
import '../settings/user_settings.dart';
import 'models.dart';
import 'mock_youtube_api.dart';
import 'quota.dart';
import 'youtube_api.dart';

class ConnectedAccount {
  ConnectedAccount(this.id, this.provider, this.label, this.connectedAt, this.status, this.mock);
  final int id;
  final String provider;
  final String label;
  final DateTime connectedAt;
  final String status;
  final bool mock;
}

class ChannelRow {
  ChannelRow({
    required this.id,
    required this.accountId,
    required this.channelId,
    required this.title,
    required this.url,
    required this.subscriberCount,
    required this.videoCount,
    required this.viewCount,
    required this.uploadsPlaylist,
    required this.styleJson,
    required this.lastSynced,
  });
  final int id;
  final int accountId;
  final String channelId;
  final String title;
  final String url;
  final int subscriberCount;
  final int videoCount;
  final int viewCount;
  final String uploadsPlaylist;
  final String? styleJson;
  final String? lastSynced;
}

typedef Progress = void Function(double fraction, String message);

const youtubeScopes = ['https://www.googleapis.com/auth/youtube.force-ssl'];
const bloggerScopes = ['https://www.googleapis.com/auth/blogger'];

/// 유튜브 채널 관리의 중심. 화면은 이 서비스만 부른다.
class YouTubeService {
  YouTubeService({
    required this.db,
    required this.settings,
    required this.secrets,
    required this.realApi,
    required this.mockApi,
    required this.tokens,
    required this.oauth,
    required this.quota,
    required this.now,
    this.logger,
  });

  final AppDatabase db;
  final UserSettings settings;
  final UserSecrets secrets;
  final YouTubeApi realApi;
  final MockYouTubeApi mockApi;
  final TokenManager tokens;
  final OAuthFlow? oauth;
  final QuotaTracker quota;
  final DateTime Function() now;
  final AppLogger? logger;

  static const googleSecretKey = 'google/clientSecret';

  /// 구글 클라이언트 ID 가 없으면 연습 모드.
  bool get isPracticeMode => settings.googleClientId.isEmpty;

  Future<OAuthConfig> googleConfig() async => OAuthConfig.google(
    settings.googleClientId,
    (await secrets.read(googleSecretKey)) ?? '',
    [...youtubeScopes, ...bloggerScopes],
  );

  // ---------------- 계정 ----------------
  List<ConnectedAccount> accounts() => db
      .select('SELECT * FROM accounts ORDER BY id')
      .map(
        (r) => ConnectedAccount(
          r['id'] as int,
          r['provider'] as String,
          r['label'] as String,
          DateTime.parse(r['connected_at'] as String),
          r['status'] as String,
          (r['mock'] as int) == 1,
        ),
      )
      .toList();

  ConnectedAccount? account(int id) {
    final list = accounts().where((a) => a.id == id);
    return list.isEmpty ? null : list.first;
  }

  YouTubeApi _apiFor(ConnectedAccount a) => a.mock ? mockApi : realApi;

  Future<String> _token(ConnectedAccount a) async {
    if (a.mock) return 'mock';
    try {
      return await tokens.accessToken(a.id, await googleConfig());
    } on AppFailure catch (e) {
      if (e.kind == FailureKind.permissionRevoked || e.kind == FailureKind.tokenExpired) {
        db.execute('UPDATE accounts SET status = ? WHERE id = ?', ['revoked', a.id]);
      }
      rethrow;
    }
  }

  /// 구글로 연결 (실제) 또는 연습 계정 연결. 연결된 계정의 채널을 모두 등록한다.
  /// [channelUrl] 을 넣으면 그 채널이 계정에 있는지 확인해 주소를 저장한다.
  /// 단계 이름을 붙여 실패를 기록하고 다시 던진다 (로그인 / 연결 정보(토큰) / 채널 목록 / 영상 목록).
  Future<T> step<T>(String stage, Future<T> Function() f) async {
    try {
      return await f();
    } catch (e, st) {
      final fail = toFailure(e);
      logger?.error('구글 연결 실패 [$stage]: ${fail.kind.name} ${fail.detail}', e, st);
      throw AppFailure(fail.kind, '[$stage] ${fail.detail}');
    }
  }

  Future<List<ChannelRow>> connectGoogle({String channelUrl = '', bool mock = false}) async {
    final useMock = mock || isPracticeMode;
    int accountId;
    if (useMock) {
      accountId = db.insert('INSERT INTO accounts(provider, label, connected_at, status, mock) VALUES(?,?,?,?,1)', [
        'google',
        '연습용 구글 계정',
        now().toIso8601String(),
        'ok',
      ]);
    } else {
      final flow = oauth;
      if (flow == null) throw AppFailure(FailureKind.notConnected, 'no oauth');
      final t = await step('로그인', () async => flow.authorize(await googleConfig()));
      accountId = db.insert('INSERT INTO accounts(provider, label, connected_at, status, mock) VALUES(?,?,?,?,0)', [
        'google',
        '구글 계정',
        now().toIso8601String(),
        'ok',
      ]);
      await tokens.save(accountId, t);
    }
    final acct = account(accountId)!;
    try {
      quota.reserve(QuotaCost.list);
      final token = await step('연결 정보(토큰)', () => _token(acct));
      final chans = await step('채널 목록', () => withRetry(() => _apiFor(acct).myChannels(token)));
      if (chans.isEmpty) {
        logger?.error('구글 연결 [채널 목록]: 이 계정에는 채널이 없음');
        throw NoChannelsFailure();
      }
      final rows = <ChannelRow>[];
      for (final c in chans) {
        if (channelUrl.isNotEmpty && _sameChannel(channelUrl, c)) c.url = channelUrl.trim();
        rows.add(_upsertChannel(accountId, c));
      }
      final label = chans.length == 1 ? chans.first.title : '${chans.first.title} 외 ${chans.length - 1}개';
      db.execute('UPDATE accounts SET label = ? WHERE id = ?', [label, accountId]);
      // 다시 연결한 경우: 채널이 하나도 안 남은 예전 계정 정리
      final orphans = db
          .select(
            'SELECT id FROM accounts WHERE id != ? AND id NOT IN (SELECT DISTINCT account_id FROM channels) '
            ' $_notUsedByBlogs',
            [accountId],
          )
          .map((r) => r['id'] as int)
          .toList();
      for (final o in orphans) {
        await tokens.remove(o);
        db.execute('DELETE FROM accounts WHERE id = ?', [o]);
      }
      logger?.info('채널 연결: ${rows.length}개 (mock=$useMock)');
      return rows;
    } catch (e) {
      // 채널을 못 가져오면 계정 연결도 되돌린다.
      await tokens.remove(accountId);
      db.execute('DELETE FROM accounts WHERE id = ?', [accountId]);
      rethrow;
    }
  }

  bool get _hasBlogTable =>
      db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='blog_sites'").isNotEmpty;

  /// 블로그(3단계)에서 쓰는 계정은 정리하지 않는다.
  String get _notUsedByBlogs => _hasBlogTable ? 'AND id NOT IN (SELECT DISTINCT account_id FROM blog_sites)' : '';

  static bool _sameChannel(String url, YtChannel c) {
    final u = url.trim().toLowerCase();
    return u.contains(c.channelId.toLowerCase()) || (c.handle.isNotEmpty && u.contains(c.handle.toLowerCase()));
  }

  ChannelRow _upsertChannel(int accountId, YtChannel c) {
    db.execute(
      '''INSERT INTO channels(account_id, channel_id, title, url, thumbnail, subscriber_count, video_count, view_count, uploads_playlist, added_at)
         VALUES(?,?,?,?,?,?,?,?,?,?)
         ON CONFLICT(channel_id) DO UPDATE SET account_id=excluded.account_id, title=excluded.title,
           thumbnail=excluded.thumbnail, subscriber_count=excluded.subscriber_count, video_count=excluded.video_count,
           view_count=excluded.view_count, uploads_playlist=excluded.uploads_playlist,
           url=CASE WHEN excluded.url != '' THEN excluded.url ELSE channels.url END''',
      [
        accountId,
        c.channelId,
        c.title,
        c.url,
        c.thumbnail,
        c.subscriberCount,
        c.videoCount,
        c.viewCount,
        c.uploadsPlaylist,
        now().toIso8601String(),
      ],
    );
    _recordStats(c.channelId, c.viewCount, c.subscriberCount);
    return channel(c.channelId)!;
  }

  /// 영상별 오늘 조회수 기록 (주목할 영상 찾기에 사용).
  void _recordVideoStat(YtVideo v) => db.execute(
    'INSERT INTO video_stats(video_id, day, view_count) VALUES(?,?,?) '
    'ON CONFLICT(video_id, day) DO UPDATE SET view_count=excluded.view_count',
    [v.videoId, dayKey(now()), v.viewCount],
  );

  void _recordStats(String channelId, int views, int subs) {
    db.execute(
      'INSERT INTO channel_stats(channel_id, day, view_count, subscriber_count) VALUES(?,?,?,?) '
      'ON CONFLICT(channel_id, day) DO UPDATE SET view_count=excluded.view_count, subscriber_count=excluded.subscriber_count',
      [channelId, dayKey(now()), views, subs],
    );
  }

  /// 채널 연결 해제: 앱 안의 자료만 지운다. 유튜브의 영상은 그대로.
  Future<void> disconnectChannel(String channelId) async {
    final c = channel(channelId);
    if (c == null) return;
    db.transaction(() {
      db.execute('DELETE FROM videos WHERE channel_id = ?', [channelId]);
      db.execute('DELETE FROM channel_stats WHERE channel_id = ?', [channelId]);
      db.execute('DELETE FROM channels WHERE channel_id = ?', [channelId]);
    });
    final left = db.select('SELECT COUNT(*) AS n FROM channels WHERE account_id = ?', [c.accountId]).first['n'] as int;
    final blogs = _hasBlogTable
        ? db.select('SELECT COUNT(*) AS n FROM blog_sites WHERE account_id = ?', [c.accountId]).first['n'] as int
        : 0;
    if (left == 0 && blogs == 0) {
      final a = account(c.accountId);
      if (a != null && !a.mock) {
        final t = await tokens.load(a.id);
        if (t != null && oauth != null) await oauth!.revoke(await googleConfig(), t);
      }
      await tokens.remove(c.accountId);
      db.execute('DELETE FROM accounts WHERE id = ?', [c.accountId]);
    }
    logger?.info('채널 연결 해제');
  }

  // ---------------- 채널·영상 읽기 (앱 안 저장 자료) ----------------
  ChannelRow _row(Map<String, dynamic> r) => ChannelRow(
    id: r['id'] as int,
    accountId: (r['account_id'] as int?) ?? 0,
    channelId: r['channel_id'] as String,
    title: r['title'] as String,
    url: r['url'] as String,
    subscriberCount: r['subscriber_count'] as int,
    videoCount: r['video_count'] as int,
    viewCount: r['view_count'] as int,
    uploadsPlaylist: r['uploads_playlist'] as String,
    styleJson: r['style_json'] as String?,
    lastSynced: r['last_synced'] as String?,
  );

  /// 실제(가짜가 아닌) 구글 계정에 연결된 채널이 하나라도 있는가.
  bool get hasRealChannel =>
      db.select('SELECT 1 FROM channels c JOIN accounts a ON a.id = c.account_id WHERE a.mock = 0 LIMIT 1').isNotEmpty;

  /// 실제 구글 계정이 정상 연결되어 있는가.
  bool get googleConnected => accounts().any((a) => !a.mock && a.status == 'ok');

  /// 채널 목록. 실제 채널이 하나라도 있으면 연습용 가짜 채널은 숨긴다 (설정 → "연습 자료 보기" 로 다시 보기).
  List<ChannelRow> channels() {
    final hideMock = hasRealChannel && !settings.showPracticeData;
    final sql = hideMock
        ? 'SELECT c.* FROM channels c LEFT JOIN accounts a ON a.id = c.account_id '
              'WHERE a.mock IS NULL OR a.mock = 0 ORDER BY c.title'
        : 'SELECT * FROM channels ORDER BY title';
    return db.select(sql).map((r) => _row(Map<String, dynamic>.from(r))).toList();
  }

  ChannelRow? channel(String channelId) {
    final r = db.select('SELECT * FROM channels WHERE channel_id = ?', [channelId]);
    return r.isEmpty ? null : _row(Map<String, dynamic>.from(r.first));
  }

  /// 나눠서 불러오기 (영상이 수천 개여도 느려지지 않게).
  List<YtVideo> videos(String channelId, {int offset = 0, int limit = 50, String search = ''}) {
    final rows = search.isEmpty
        ? db.select('SELECT * FROM videos WHERE channel_id = ? ORDER BY published_at DESC LIMIT ? OFFSET ?', [
            channelId,
            limit,
            offset,
          ])
        : db.select(
            'SELECT * FROM videos WHERE channel_id = ? AND title LIKE ? ORDER BY published_at DESC LIMIT ? OFFSET ?',
            [channelId, '%$search%', limit, offset],
          );
    return rows.map(videoFromRow).toList();
  }

  static YtVideo videoFromRow(Map<String, dynamic> r) => YtVideo(
    videoId: r['video_id'] as String,
    channelId: r['channel_id'] as String,
    title: r['title'] as String,
    description: r['description'] as String,
    tags: (jsonDecode(r['tags_json'] as String) as List<dynamic>).map((e) => '$e').toList(),
    thumbnailUrl: r['thumbnail_url'] as String,
    viewCount: r['view_count'] as int,
    publishedAt: r['published_at'] as String,
    privacy: r['privacy'] as String,
    categoryId: r['category_id'] as String,
  );

  YtVideo? video(String videoId) {
    final r = db.select('SELECT * FROM videos WHERE video_id = ?', [videoId]);
    return r.isEmpty ? null : videoFromRow(Map<String, dynamic>.from(r.first));
  }

  int videoTotal(String channelId) =>
      db.select('SELECT COUNT(*) AS n FROM videos WHERE channel_id = ?', [channelId]).first['n'] as int;

  void saveVideo(YtVideo v) {
    db.execute(
      '''INSERT INTO videos(channel_id, video_id, title, description, tags_json, thumbnail_url, view_count, published_at, privacy, category_id, updated_at)
         VALUES(?,?,?,?,?,?,?,?,?,?,?)
         ON CONFLICT(video_id) DO UPDATE SET title=excluded.title, description=excluded.description, tags_json=excluded.tags_json,
           thumbnail_url=excluded.thumbnail_url, view_count=excluded.view_count, privacy=excluded.privacy,
           category_id=excluded.category_id, updated_at=excluded.updated_at''',
      [
        v.channelId,
        v.videoId,
        v.title,
        v.description,
        jsonEncode(v.tags),
        v.thumbnailUrl,
        v.viewCount,
        v.publishedAt,
        v.privacy,
        v.categoryId,
        now().toIso8601String(),
      ],
    );
  }

  // ---------------- 유튜브에서 새로 불러오기 ----------------
  /// 백그라운드 작업. 진행률을 알려 주고 취소할 수 있다. 한도가 모자라면 멈추고 다음 날 이어서.
  Future<int> syncChannel(String channelId, {CancelToken? cancel, Progress? progress}) async {
    try {
      return await _syncChannel(channelId, cancel: cancel, progress: progress);
    } catch (e, st) {
      final fail = toFailure(e);
      if (fail.kind != FailureKind.cancelled) {
        logger?.error('영상 불러오기 실패 [영상 목록]: ${fail.kind.name} ${fail.detail}', e, st);
      }
      rethrow;
    }
  }

  Future<int> _syncChannel(String channelId, {CancelToken? cancel, Progress? progress}) async {
    final c = channel(channelId);
    if (c == null) throw AppFailure(FailureKind.notFound, 'channel');
    final acct = account(c.accountId);
    if (acct == null) throw AppFailure(FailureKind.notConnected, 'account');
    final api = _apiFor(acct);
    var count = 0;
    String? page;
    var pages = 0;
    final expectedPages = (c.videoCount / 50).ceil().clamp(1, 1000);
    do {
      cancel?.throwIfCancelled();
      quota.reserve(QuotaCost.list * 2);
      try {
        final token = await _token(acct);
        final p = await withRetry(() => api.listUploads(token, c.uploadsPlaylist, pageToken: page), cancel: cancel);
        final vids = await withRetry(() => api.videosByIds(token, p.videoIds), cancel: cancel);
        db.transaction(() {
          for (final v in vids) {
            saveVideo(v);
            _recordVideoStat(v);
          }
        });
        count += vids.length;
        page = p.nextPageToken;
        pages++;
        progress?.call((pages / expectedPages).clamp(0, 1).toDouble(), '영상 $count개 불러옴');
      } on AppFailure catch (e) {
        if (e.kind == FailureKind.quotaExceeded) quota.markExhausted();
        rethrow;
      }
    } while (page != null);
    // 채널 전체 숫자도 갱신
    final totalViews =
        db.select('SELECT COALESCE(SUM(view_count),0) AS s FROM videos WHERE channel_id = ?', [channelId]).first['s']
            as int;
    db.execute(
      'UPDATE channels SET last_synced = ?, video_count = ?, view_count = MAX(view_count, ?) WHERE channel_id = ?',
      [now().toIso8601String(), videoTotal(channelId), totalViews, channelId],
    );
    final updated = channel(channelId)!;
    _recordStats(channelId, updated.viewCount, updated.subscriberCount);
    return count;
  }

  /// 영상 한 개의 제목·설명·키워드를 유튜브에 반영 (한도 50).
  Future<YtVideo> updateMeta(String videoId, VideoMeta meta) async {
    final v = video(videoId);
    if (v == null) throw AppFailure(FailureKind.notFound, 'video');
    final c = channel(v.channelId);
    final acct = c == null ? null : account(c.accountId);
    if (acct == null) throw AppFailure(FailureKind.notConnected, 'account');
    quota.reserve(QuotaCost.update);
    try {
      final token = await _token(acct);
      final nv = await withRetry(() => _apiFor(acct).updateMeta(token, v, meta));
      saveVideo(nv);
      return nv;
    } on AppFailure catch (e) {
      if (e.kind == FailureKind.quotaExceeded) {
        quota.markExhausted();
      } else if (e.kind == FailureKind.network || e.kind == FailureKind.timeout) {
        quota.refund(QuotaCost.update);
      }
      rethrow;
    }
  }

  /// 유튜브에 있는 현재 내용 (되돌리기 전 확인용, 한도 1).
  Future<YtVideo?> fetchRemote(String videoId) async {
    final v = video(videoId);
    if (v == null) return null;
    final c = channel(v.channelId);
    final acct = c == null ? null : account(c.accountId);
    if (acct == null) throw AppFailure(FailureKind.notConnected, 'account');
    quota.reserve(QuotaCost.list);
    final token = await _token(acct);
    final list = await withRetry(() => _apiFor(acct).videosByIds(token, [videoId]));
    return list.isEmpty ? null : list.first;
  }

  /// 비공개 업로드 (한도 1600). 사용자가 확인 버튼을 눌렀을 때만 화면에서 부른다.
  Future<String> uploadPrivate(String channelId, File file, UploadMeta meta) async {
    final c = channel(channelId);
    final acct = c == null ? null : account(c.accountId);
    if (acct == null) throw AppFailure(FailureKind.notConnected, 'account');
    quota.reserve(QuotaCost.upload);
    try {
      final token = await _token(acct);
      final id = await _apiFor(acct).uploadPrivate(token, channelId, file, meta);
      logger?.info('비공개 업로드 완료');
      return id;
    } on AppFailure catch (e) {
      if (e.kind == FailureKind.quotaExceeded) {
        quota.markExhausted();
      } else if (e.kind == FailureKind.network || e.kind == FailureKind.timeout) {
        quota.refund(QuotaCost.upload);
      }
      rethrow;
    }
  }

  /// 썸네일 그림 올리기 (한도 50). 실패해도 업로드 자체는 성공으로 둔다(호출하는 쪽에서 처리).
  Future<void> setThumbnail(String channelId, String videoId, File png) async {
    final c = channel(channelId);
    final acct = c == null ? null : account(c.accountId);
    if (acct == null) throw AppFailure(FailureKind.notConnected, 'account');
    quota.reserve(QuotaCost.thumbnail);
    final token = await _token(acct);
    await withRetry(() => _apiFor(acct).setThumbnail(token, videoId, png));
  }

  // ---------------- 통계 ----------------
  int totalViews() => channels().fold<int>(0, (s, c) => s + c.viewCount);

  /// [days] 일 전 대비 늘어난 조회수 (기록이 없으면 0).
  int viewsDelta(int days) {
    final today = dayKey(now());
    final since = dayKey(now().subtract(Duration(days: days)));
    var delta = 0;
    for (final c in channels()) {
      final rows = db.select(
        'SELECT view_count FROM channel_stats WHERE channel_id = ? AND day >= ? AND day <= ? ORDER BY day',
        [c.channelId, since, today],
      );
      if (rows.length >= 2) delta += (rows.last['view_count'] as int) - (rows.first['view_count'] as int);
    }
    return delta;
  }

  /// 어제와 그제 비교 (채널별).
  List<({String title, int delta})> yesterdayChanges() {
    final y = dayKey(now().subtract(const Duration(days: 1)));
    final y2 = dayKey(now().subtract(const Duration(days: 2)));
    final t = dayKey(now());
    final out = <({String title, int delta})>[];
    for (final c in channels()) {
      int? at(String d) {
        final r = db.select('SELECT view_count FROM channel_stats WHERE channel_id = ? AND day = ?', [c.channelId, d]);
        return r.isEmpty ? null : r.first['view_count'] as int;
      }

      final a = at(y2) ?? at(y);
      final b = at(y) ?? at(t);
      if (a != null && b != null) out.add((title: c.title, delta: b - a));
    }
    return out;
  }

  /// 구글 테스트 모드에서는 연결이 7일 뒤 만료된다 → 만료 임박 계정.
  List<ConnectedAccount> expiringAccounts() {
    if (!settings.googleAppInTesting) return [];
    return accounts().where((a) => !a.mock && now().difference(a.connectedAt).inDays >= 5).toList();
  }

  List<ConnectedAccount> brokenAccounts() => accounts().where((a) => a.status != 'ok').toList();
}

/// 연결한 구글 계정에 유튜브 채널이 하나도 없을 때.
class NoChannelsFailure extends AppFailure {
  NoChannelsFailure() : super(FailureKind.notFound, 'no channels');
}
