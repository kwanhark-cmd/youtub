import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/db.dart';
import '../../core/failure.dart';
import '../../core/http_json.dart';
import '../../core/logger.dart';
import '../../core/oauth.dart';
import '../../core/secret_store.dart';

enum ToolId { googleVids, higgsfield, figma, vrew }

enum ToolState { connected, notConnected, expired, preparing }

class ToolInfo {
  ToolInfo(this.id, this.name, this.role, this.state, {this.detail = ''});
  final ToolId id;
  final String name;
  final String role;
  final ToolState state;
  final String detail;
}

/// 영상 생성 도구 틀. 힉스필드(실제) / 연습용(가짜) 이 이 틀을 따른다.
abstract class VideoGenerator {
  Future<int> credits();
  int estimateCredits(String prompt, {int seconds = 10});
  Future<String> start(String prompt, {int seconds = 10});

  /// 끝났으면 영상 주소, 아직이면 null.
  Future<String?> poll(String jobId);
  Future<void> download(String url, File target);
}

/// 힉스필드 API. 공식 문서의 주소·형식이 바뀌면 설정의 "API 주소" 만 바꾸면 되도록 주소를 한곳에 둔다.
/// 크레딧이 드는 작업은 사용자가 화면에서 직접 승인했을 때만 불린다(ProductionService 참고).
class HiggsfieldGenerator implements VideoGenerator {
  HiggsfieldGenerator(this.json, this.raw, this.apiKey, {this.baseUrl = 'https://platform.higgsfield.ai'});
  final JsonHttp json;
  final http.Client raw;
  final String apiKey;
  final String baseUrl;

  Map<String, String> get _h => {'authorization': 'Key $apiKey', 'accept': 'application/json'};

  @override
  Future<int> credits() async {
    final j = await json.send('GET', Uri.parse('$baseUrl/v1/account/credits'), headers: _h);
    return (j['credits'] as num?)?.toInt() ?? (j['balance'] as num?)?.toInt() ?? 0;
  }

  @override
  int estimateCredits(String prompt, {int seconds = 10}) => (seconds / 5).ceil() * 10;

  @override
  Future<String> start(String prompt, {int seconds = 10}) async {
    final j = await json.send(
      'POST',
      Uri.parse('$baseUrl/v1/generations/video'),
      headers: _h,
      body: {'prompt': prompt, 'duration': seconds, 'aspect_ratio': '9:16'},
      maxAttempts: 1,
    );
    final id = (j['id'] ?? j['job_id'] ?? j['request_id'])?.toString();
    if (id == null) throw AppFailure(FailureKind.unknown, 'no job id');
    return id;
  }

  @override
  Future<String?> poll(String jobId) async {
    final j = await json.send('GET', Uri.parse('$baseUrl/v1/generations/$jobId'), headers: _h);
    final status = '${j['status'] ?? ''}'.toLowerCase();
    if (status == 'failed' || status == 'error') throw AppFailure(FailureKind.unknown, 'generation failed');
    final url = j['video_url'] ?? j['url'] ?? ((j['output'] as Map?)?['url']);
    return (status == 'completed' || status == 'succeeded' || status == 'done') && url != null ? '$url' : null;
  }

  @override
  Future<void> download(String url, File target) async {
    final res = await raw.get(Uri.parse(url)).timeout(const Duration(minutes: 10));
    if (res.statusCode >= 300) throw classifyHttpError(res.statusCode, '');
    target.parent.createSync(recursive: true);
    await target.writeAsBytes(res.bodyBytes);
  }
}

/// 연습 모드용 가짜 영상 생성기 (크레딧 0, 작은 가짜 파일).
class MockVideoGenerator implements VideoGenerator {
  int left = 500;
  int started = 0;
  @override
  Future<int> credits() async => left;
  @override
  int estimateCredits(String prompt, {int seconds = 10}) => (seconds / 5).ceil() * 10;
  @override
  Future<String> start(String prompt, {int seconds = 10}) async {
    started++;
    left -= estimateCredits(prompt, seconds: seconds);
    return 'mockjob$started';
  }

  @override
  Future<String?> poll(String jobId) async => 'mock://$jobId.mp4';
  @override
  Future<void> download(String url, File target) async {
    target.parent.createSync(recursive: true);
    await target.writeAsBytes(utf8.encode('연습용 가짜 영상 $url'));
  }
}

/// 앱 금고(5번 앱) 연동 틀. 첫 버전은 연결하지 않는다. 도구 비밀번호는 저장하지 않는다.
abstract class AppVault {
  bool get available;
  Future<String?> credentialFor(ToolId tool);
}

class NoVault implements AppVault {
  @override
  bool get available => false;
  @override
  Future<String?> credentialFor(ToolId tool) async => null;
}

/// 제작 도구 연결 관리 (연결 상태·테스트·해제·만료).
class ToolsService {
  ToolsService({
    required this.db,
    required this.secrets,
    required this.json,
    required this.raw,
    required this.oauth,
    required this.now,
    this.logger,
    VideoGenerator? mockGenerator,
  }) : mockGenerator = mockGenerator ?? MockVideoGenerator();

  final AppDatabase db;
  final UserSecrets secrets;
  final JsonHttp json;
  final http.Client raw;
  final OAuthFlow oauth;
  final DateTime Function() now;
  final AppLogger? logger;
  final VideoGenerator mockGenerator;
  final AppVault vault = NoVault();

  static const higgsKey = 'tools/higgsfield/key';
  static const figmaTokens = 'tools/figma/tokens';
  static const figmaSecret = 'tools/figma/clientSecret';

  String get higgsBaseUrl => db.getSetting<String>('higgsBaseUrl') ?? 'https://platform.higgsfield.ai';
  set higgsBaseUrl(String v) => db.setSetting('higgsBaseUrl', v.trim());
  String get figmaClientId => db.getSetting<String>('figmaClientId') ?? '';
  set figmaClientId(String v) => db.setSetting('figmaClientId', v.trim());

  void _setStatus(ToolId t, String status, {DateTime? expires}) => db.execute(
    'INSERT INTO tool_status(tool, connected_at, expires_at, status) VALUES(?,?,?,?) '
    'ON CONFLICT(tool) DO UPDATE SET connected_at=excluded.connected_at, expires_at=excluded.expires_at, status=excluded.status',
    [t.name, now().toIso8601String(), expires?.toIso8601String(), status],
  );

  ({String status, DateTime? expires})? _status(ToolId t) {
    final r = db.select('SELECT status, expires_at FROM tool_status WHERE tool = ?', [t.name]);
    if (r.isEmpty) return null;
    final e = r.first['expires_at'] as String?;
    return (status: r.first['status'] as String, expires: e == null ? null : DateTime.parse(e));
  }

  Future<List<ToolInfo>> all() async {
    ToolState st(ToolId t) {
      final s = _status(t);
      if (s == null || s.status == 'none') return ToolState.notConnected;
      if (s.status == 'expired' || (s.expires != null && now().isAfter(s.expires!))) return ToolState.expired;
      return ToolState.connected;
    }

    return [
      ToolInfo(
        ToolId.googleVids,
        '구글 비즈 (Google Vids)',
        '영상 생성 1순위',
        ToolState.preparing,
        detail: '공식 API 가 없어 다음 버전에서 지원 예정이에요.',
      ),
      ToolInfo(
        ToolId.higgsfield,
        '힉스필드 (Higgsfield)',
        '영상 생성 · 음성 나레이션',
        (await secrets.read(higgsKey)) == null ? ToolState.notConnected : st(ToolId.higgsfield),
      ),
      ToolInfo(
        ToolId.figma,
        '피그마 (Figma)',
        '모션 그래픽',
        (await secrets.read(figmaTokens)) == null ? ToolState.notConnected : st(ToolId.figma),
      ),
      ToolInfo(ToolId.vrew, '브루 (Vrew)', '음성 나레이션', ToolState.preparing, detail: '공식 API 가 없어 다음 버전에서 지원 예정이에요.'),
    ];
  }

  // ---- 힉스필드 ----
  Future<void> connectHiggsfield(String key) async {
    if (key.trim().isEmpty) throw AppFailure(FailureKind.invalidInput, 'empty key');
    await secrets.write(higgsKey, key.trim());
    _setStatus(ToolId.higgsfield, 'ok');
  }

  Future<bool> get higgsConnected async => (await secrets.read(higgsKey)) != null;

  /// 키가 있으면 실제, 없으면 연습용.
  Future<VideoGenerator> videoGenerator() async {
    final k = await secrets.read(higgsKey);
    if (k == null) return mockGenerator;
    return HiggsfieldGenerator(json, raw, k, baseUrl: higgsBaseUrl);
  }

  // ---- 피그마 ----
  Future<void> connectFigma() async {
    final cfg = OAuthConfig.figma(figmaClientId, (await secrets.read(figmaSecret)) ?? '');
    final t = await oauth.authorize(cfg);
    await secrets.write(figmaTokens, t.encode());
    _setStatus(ToolId.figma, 'ok', expires: t.refreshToken == null ? t.expiresAt : null);
  }

  /// 연결 테스트. 실패 원인에 따라 상태를 "만료" 로 바꾼다.
  Future<bool> test(ToolId t) async {
    try {
      switch (t) {
        case ToolId.higgsfield:
          await (await videoGenerator()).credits();
        case ToolId.figma:
          final tok = OAuthTokens.decode(await secrets.read(figmaTokens));
          if (tok == null) throw AppFailure(FailureKind.notConnected);
          await json.send(
            'GET',
            Uri.parse('https://api.figma.com/v1/me'),
            headers: {'authorization': 'Bearer ${tok.accessToken}'},
          );
        case ToolId.googleVids:
        case ToolId.vrew:
          return false;
      }
      _setStatus(t, 'ok', expires: _status(t)?.expires);
      return true;
    } on AppFailure catch (e) {
      if (e.kind == FailureKind.tokenExpired || e.kind == FailureKind.permissionRevoked) _setStatus(t, 'expired');
      rethrow;
    }
  }

  Future<void> disconnect(ToolId t) async {
    switch (t) {
      case ToolId.higgsfield:
        await secrets.delete(higgsKey);
      case ToolId.figma:
        await secrets.delete(figmaTokens);
      case ToolId.googleVids:
      case ToolId.vrew:
        break;
    }
    db.execute('DELETE FROM tool_status WHERE tool = ?', [t.name]);
  }

  /// 만료되었거나 3일 안에 만료되는 도구 (브리핑·알림용).
  Future<List<String>> expiringNotices() async {
    final out = <String>[];
    for (final t in await all()) {
      if (t.state == ToolState.expired) out.add('${t.name} 연결이 만료되었어요. 설정 → 제작 도구 연결에서 다시 연결해 주세요');
      final s = _status(t.id);
      if (t.state == ToolState.connected && s?.expires != null && s!.expires!.difference(now()).inDays < 3) {
        out.add('${t.name} 연결이 곧 만료돼요');
      }
    }
    return out;
  }
}
