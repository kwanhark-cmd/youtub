import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'failure.dart';
import 'http_json.dart';
import 'secret_store.dart';

class OAuthConfig {
  const OAuthConfig({
    required this.authorizeUrl,
    required this.tokenUrl,
    required this.clientId,
    this.clientSecret = '',
    required this.scopes,
    this.extraParams = const {},
    this.fixedPort,
    this.revokeUrl,
  });

  final String authorizeUrl;
  final String tokenUrl;
  final String clientId;
  final String clientSecret;
  final List<String> scopes;
  final Map<String, String> extraParams;

  /// 일부 서비스(피그마)는 미리 등록한 주소만 허용하므로 포트를 고정한다.
  final int? fixedPort;
  final String? revokeUrl;

  static OAuthConfig google(String clientId, String clientSecret, List<String> scopes) => OAuthConfig(
    authorizeUrl: 'https://accounts.google.com/o/oauth2/v2/auth',
    tokenUrl: 'https://oauth2.googleapis.com/token',
    revokeUrl: 'https://oauth2.googleapis.com/revoke',
    clientId: clientId,
    clientSecret: clientSecret,
    scopes: scopes,
    extraParams: const {'access_type': 'offline', 'prompt': 'consent select_account'},
  );

  static OAuthConfig figma(String clientId, String clientSecret) => OAuthConfig(
    authorizeUrl: 'https://www.figma.com/oauth',
    tokenUrl: 'https://api.figma.com/v1/oauth/token',
    clientId: clientId,
    clientSecret: clientSecret,
    scopes: const ['file_content:read'],
    fixedPort: 53682,
  );
}

class OAuthTokens {
  OAuthTokens({required this.accessToken, this.refreshToken, required this.expiresAt});
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;

  bool isExpired(DateTime now) => now.isAfter(expiresAt.subtract(const Duration(minutes: 2)));

  String encode() => jsonEncode({'a': accessToken, 'r': refreshToken, 'e': expiresAt.toIso8601String()});

  static OAuthTokens? decode(String? s) {
    if (s == null) return null;
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return OAuthTokens(
        accessToken: j['a'] as String,
        refreshToken: j['r'] as String?,
        expiresAt: DateTime.parse(j['e'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

typedef UrlLauncher = Future<bool> Function(Uri url);

String _randomUrlSafe(int bytes) {
  final r = Random.secure();
  return base64UrlEncode(List<int>.generate(bytes, (_) => r.nextInt(256))).replaceAll('=', '');
}

/// PKCE 값 만들기 (테스트에서도 사용).
({String verifier, String challenge}) makePkce() {
  final verifier = _randomUrlSafe(48);
  final challenge = base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
  return (verifier: verifier, challenge: challenge);
}

/// 브라우저로 로그인 창을 열고, 내 컴퓨터(127.0.0.1)로 돌아오는 코드를 받아 토큰으로 바꾼다.
/// 사용자의 비밀번호는 구글/피그마 창에만 입력되고 이 앱은 볼 수 없다.
class OAuthFlow {
  OAuthFlow(this.http, this.launch, {this.now = DateTime.now});

  final JsonHttp http;
  final UrlLauncher launch;
  final DateTime Function() now;

  Future<OAuthTokens> authorize(OAuthConfig cfg, {Duration wait = const Duration(minutes: 5)}) async {
    if (cfg.clientId.isEmpty) throw AppFailure(FailureKind.notConnected, 'no client id');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, cfg.fixedPort ?? 0);
    try {
      final redirect = 'http://127.0.0.1:${server.port}/callback';
      final pkce = makePkce();
      final state = _randomUrlSafe(16);
      final url = Uri.parse(cfg.authorizeUrl).replace(
        queryParameters: {
          'client_id': cfg.clientId,
          'redirect_uri': redirect,
          'response_type': 'code',
          'scope': cfg.scopes.join(' '),
          'state': state,
          'code_challenge': pkce.challenge,
          'code_challenge_method': 'S256',
          ...cfg.extraParams,
        },
      );
      final opened = await launch(url);
      if (!opened) throw AppFailure(FailureKind.unknown, 'cannot open browser');

      final code = await _waitForCode(
        server,
        state,
      ).timeout(wait, onTimeout: () => throw AppFailure(FailureKind.timeout, 'oauth wait'));
      final j = await http.send(
        'POST',
        Uri.parse(cfg.tokenUrl),
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: Uri(
          queryParameters: {
            'grant_type': 'authorization_code',
            'code': code,
            'redirect_uri': redirect,
            'client_id': cfg.clientId,
            if (cfg.clientSecret.isNotEmpty) 'client_secret': cfg.clientSecret,
            'code_verifier': pkce.verifier,
          },
        ).query,
      );
      return _tokensFrom(j, null);
    } finally {
      await server.close(force: true);
    }
  }

  Future<String> _waitForCode(HttpServer server, String state) async {
    await for (final req in server) {
      if (req.uri.path != '/callback') {
        req.response.statusCode = 404;
        await req.response.close();
        continue;
      }
      final q = req.uri.queryParameters;
      req.response.headers.contentType = ContentType.html;
      final ok = q['state'] == state && q['code'] != null;
      req.response.write(
        '<html><body style="font-family:sans-serif;font-size:22px;padding:40px">'
        '${ok ? '연결되었어요. 이 창을 닫고 앱으로 돌아가 주세요.' : '연결하지 못했어요. 앱으로 돌아가 다시 시도해 주세요.'}'
        '</body></html>',
      );
      await req.response.close();
      if (q['error'] != null) {
        throw AppFailure(FailureKind.permissionRevoked, 'oauth denied');
      }
      if (ok) return q['code']!;
    }
    throw AppFailure(FailureKind.cancelled, 'server closed');
  }

  Future<OAuthTokens> refresh(OAuthConfig cfg, OAuthTokens old) async {
    final rt = old.refreshToken;
    if (rt == null) throw AppFailure(FailureKind.tokenExpired, 'no refresh token');
    final j = await http.send(
      'POST',
      Uri.parse(cfg.tokenUrl),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: Uri(
        queryParameters: {
          'grant_type': 'refresh_token',
          'refresh_token': rt,
          'client_id': cfg.clientId,
          if (cfg.clientSecret.isNotEmpty) 'client_secret': cfg.clientSecret,
        },
      ).query,
    );
    return _tokensFrom(j, rt);
  }

  Future<void> revoke(OAuthConfig cfg, OAuthTokens t) async {
    final url = cfg.revokeUrl;
    if (url == null) return;
    try {
      await http.send(
        'POST',
        Uri.parse(url),
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: Uri(queryParameters: {'token': t.refreshToken ?? t.accessToken}).query,
        maxAttempts: 1,
      );
    } catch (_) {
      // 취소 실패해도 앱 안의 토큰은 지운다.
    }
  }

  OAuthTokens _tokensFrom(Map<String, dynamic> j, String? oldRefresh) {
    final at = j['access_token'] as String?;
    if (at == null) throw AppFailure(FailureKind.permissionRevoked, 'no access token');
    final exp = (j['expires_in'] as num?)?.toInt() ?? 3600;
    return OAuthTokens(
      accessToken: at,
      refreshToken: (j['refresh_token'] as String?) ?? oldRefresh,
      expiresAt: now().add(Duration(seconds: exp)),
    );
  }
}

/// 계정별 토큰 보관 + 자동 갱신.
class TokenManager {
  TokenManager(this.secrets, this.flow, {this.now = DateTime.now});
  final UserSecrets secrets;
  final OAuthFlow? flow;
  final DateTime Function() now;

  String _key(int accountId) => 'acct/$accountId/tokens';

  Future<void> save(int accountId, OAuthTokens t) => secrets.write(_key(accountId), t.encode());
  Future<OAuthTokens?> load(int accountId) async => OAuthTokens.decode(await secrets.read(_key(accountId)));
  Future<void> remove(int accountId) => secrets.deletePrefix('acct/$accountId/');

  /// 유효한 액세스 토큰. 만료됐으면 갱신. 갱신이 거절되면 permissionRevoked.
  Future<String> accessToken(int accountId, OAuthConfig cfg) async {
    final t = await load(accountId);
    if (t == null) throw AppFailure(FailureKind.notConnected, 'no tokens');
    if (!t.isExpired(now())) return t.accessToken;
    final f = flow;
    if (f == null) throw AppFailure(FailureKind.tokenExpired, 'no flow');
    try {
      final nt = await f.refresh(cfg, t);
      await save(accountId, nt);
      return nt.accessToken;
    } on AppFailure catch (e) {
      if (e.kind == FailureKind.permissionRevoked || e.kind == FailureKind.invalidInput) {
        throw AppFailure(FailureKind.permissionRevoked, 'refresh rejected');
      }
      rethrow;
    }
  }
}
