import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../core/app_log.dart';
import '../data/key_store.dart';

/// 지메일 연결(읽기 전용): 각 AI의 "내보내기 준비됨" 안내 메일이 오면 알려 줍니다.
/// 링크는 로그인이 필요하고 금방 만료되므로 앱이 대신 내려받지는 않고 "내려받을 때가 됐어요"만 알려요.
///
/// 연결 방식: 구글 "데스크톱 앱" 클라이언트 + 내 컴퓨터 안 주소(127.0.0.1) 되돌아오기 + PKCE.
class ExportMail {
  final String id;
  final String from;
  final String subject;
  final DateTime receivedAt;
  String get openUrl => 'https://mail.google.com/mail/u/0/#all/$id';
  const ExportMail(this.id, this.from, this.subject, this.receivedAt);
}

enum GmailErrorKind { notConfigured, badClientFile, webClient, cancelled, timeout, expired, network, denied, unknown }

class GmailError implements Exception {
  final GmailErrorKind kind;
  const GmailError(this.kind);
  String get message => switch (kind) {
    GmailErrorKind.notConfigured => '먼저 구글 클라이언트 ID와 비밀번호를 넣어 주세요("구글 연결 준비하기" 참고).',
    GmailErrorKind.badClientFile => '이 파일에서 클라이언트 ID를 찾지 못했어요. 구글 콘솔에서 내려받은 JSON 파일인지 확인해 주세요.',
    GmailErrorKind.webClient => '"웹 애플리케이션" 유형의 파일이에요. 클라이언트 유형을 반드시 "데스크톱 앱"으로 다시 만들어 주세요.',
    GmailErrorKind.cancelled => '연결을 그만두었어요.',
    GmailErrorKind.timeout => '5분 안에 브라우저에서 허용하지 않아 연결을 멈췄어요. 다시 해 주세요.',
    GmailErrorKind.expired => '지메일 연결이 만료됐어요(테스트 상태 앱은 7일마다 끊겨요). "다시 연결하기"를 눌러 주세요.',
    GmailErrorKind.network => '인터넷에 연결되어 있지 않아요. 잠시 뒤 다시 해 주세요.',
    GmailErrorKind.denied => '구글에서 허용하지 않았어요. 테스트 사용자에 내 지메일 주소를 넣었는지 확인해 주세요.',
    GmailErrorKind.unknown => '지메일 연결 중 문제가 생겼어요. 문제 신고로 알려 주세요.',
  };
  @override
  String toString() => 'GmailError($kind)';
}

class GmailService {
  static const scope = 'https://www.googleapis.com/auth/gmail.readonly';
  static const authUrl = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const tokenUrl = 'https://oauth2.googleapis.com/token';
  static const apiBase = 'https://gmail.googleapis.com/gmail/v1/users/me';

  /// 내보내기 안내 메일을 찾는 검색식.
  static const query =
      'newer_than:14d ((from:anthropic.com) OR (from:openai.com) OR (from:google.com subject:(테이크아웃 OR Takeout))) '
      '(export OR 내보내기 OR takeout OR 테이크아웃 OR "data is ready" OR "다운로드")';

  final KeyStore keys;
  final String userId;
  final http.Client client;
  final Future<void> Function(Uri url) openBrowser;

  GmailService({required this.keys, required this.userId, http.Client? client, required this.openBrowser})
    : client = client ?? http.Client();

  String get _secretKey => 'gmail-secret-$userId';
  String get _refreshKey => 'gmail-refresh-$userId';

  /// 구글 콘솔에서 받은 JSON 파일에서 (ID, 비밀번호)를 꺼냄.
  static (String, String) parseClientJson(String text) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw const GmailError(GmailErrorKind.badClientFile);
    }
    if (j['web'] is Map && j['installed'] == null) throw const GmailError(GmailErrorKind.webClient);
    final m = (j['installed'] ?? j) as Map;
    final id = m['client_id']?.toString() ?? '';
    final secret = m['client_secret']?.toString() ?? '';
    if (!id.endsWith('.apps.googleusercontent.com')) throw const GmailError(GmailErrorKind.badClientFile);
    return (id, secret);
  }

  Future<void> saveSecret(String secret) => keys.write(_secretKey, secret);
  Future<bool> hasSecret() async => (await keys.read(_secretKey))?.isNotEmpty == true;
  Future<bool> isConnected() async => (await keys.read(_refreshKey))?.isNotEmpty == true;

  static String _randomString(int n) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = Random.secure();
    return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static String codeChallenge(String verifier) => base64Url.encode(crypto.sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

  /// 브라우저에서 허용 → 내 컴퓨터 주소로 돌아온 코드를 받아 연결 완료.
  Future<void> connect({required String clientId, Duration timeout = const Duration(minutes: 5)}) async {
    final secret = await keys.read(_secretKey);
    if (clientId.isEmpty || secret == null || secret.isEmpty) throw const GmailError(GmailErrorKind.notConfigured);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';
    final verifier = _randomString(64);
    final state = _randomString(24);
    final url = Uri.parse(authUrl).replace(
      queryParameters: {
        'client_id': clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': scope,
        'code_challenge': codeChallenge(verifier),
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent',
        'state': state,
      },
    );
    try {
      // 브라우저를 열기 전에 먼저 되돌아올 주소에서 기다리기 시작
      final waiting = server.first.timeout(timeout, onTimeout: () => throw const GmailError(GmailErrorKind.timeout));
      unawaited(openBrowser(url).catchError((Object e) => AppLog.warn('브라우저 열기 실패', {'error': e.runtimeType.toString()})));
      final req = await waiting;
      final qp = req.uri.queryParameters;
      final ok = qp['code'] != null && qp['state'] == state;
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
          '<html><body style="font-family:sans-serif;font-size:22px;padding:40px">'
          '${ok ? '지메일 연결이 끝났어요. 앱으로 돌아가세요.' : '연결하지 못했어요. 앱으로 돌아가 다시 해 주세요.'}</body></html>',
        );
      await req.response.close();
      if (qp['error'] == 'access_denied') throw const GmailError(GmailErrorKind.denied);
      if (!ok) throw const GmailError(GmailErrorKind.cancelled);
      final tokens = await _post({
        'code': qp['code']!,
        'client_id': clientId,
        'client_secret': secret,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      });
      final refresh = tokens['refresh_token']?.toString();
      if (refresh == null || refresh.isEmpty) throw const GmailError(GmailErrorKind.unknown);
      await keys.write(_refreshKey, refresh);
      AppLog.info('지메일 연결 완료');
    } finally {
      await server.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _post(Map<String, String> form) async {
    http.Response res;
    try {
      res = await client.post(Uri.parse(tokenUrl), body: form).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const GmailError(GmailErrorKind.network);
    } on SocketException {
      throw const GmailError(GmailErrorKind.network);
    } on http.ClientException {
      throw const GmailError(GmailErrorKind.network);
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      final err = j['error']?.toString();
      AppLog.warn('지메일 토큰 실패', {'stage': '지메일 연결', 'status': res.statusCode, 'error': err});
      if (err == 'invalid_grant') throw const GmailError(GmailErrorKind.expired);
      if (err == 'access_denied' || err == 'unauthorized_client') throw const GmailError(GmailErrorKind.denied);
      throw const GmailError(GmailErrorKind.unknown);
    }
    return j;
  }

  Future<String> _accessToken(String clientId) async {
    final refresh = await keys.read(_refreshKey);
    final secret = await keys.read(_secretKey);
    if (refresh == null || secret == null) throw const GmailError(GmailErrorKind.notConfigured);
    final j = await _post({'client_id': clientId, 'client_secret': secret, 'refresh_token': refresh, 'grant_type': 'refresh_token'});
    return j['access_token'].toString();
  }

  Future<Map<String, dynamic>> _get(String path, String token, [Map<String, dynamic>? params]) async {
    http.Response res;
    try {
      res = await client
          .get(Uri.parse('$apiBase$path').replace(queryParameters: params), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const GmailError(GmailErrorKind.network);
    } on SocketException {
      throw const GmailError(GmailErrorKind.network);
    } on http.ClientException {
      throw const GmailError(GmailErrorKind.network);
    }
    if (res.statusCode == 401) throw const GmailError(GmailErrorKind.expired);
    if (res.statusCode == 403) throw const GmailError(GmailErrorKind.denied);
    if (res.statusCode != 200) throw const GmailError(GmailErrorKind.unknown);
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  /// 최근 내보내기 안내 메일(보낸 곳, 제목, 받은 시각). 본문은 읽지 않습니다.
  Future<List<ExportMail>> recentExportMails(String clientId) async {
    final token = await _accessToken(clientId);
    final list = await _get('/messages', token, {'q': query, 'maxResults': '10'});
    final out = <ExportMail>[];
    for (final m in (list['messages'] as List? ?? const [])) {
      final id = (m as Map)['id'].toString();
      final meta = await _get('/messages/$id', token, {
        'format': 'metadata',
        'metadataHeaders': ['From', 'Subject'],
      });
      final headers = ((meta['payload'] as Map?)?['headers'] as List? ?? const []).cast<Map>();
      String h(String n) => headers.firstWhere((e) => e['name'] == n, orElse: () => const {})['value']?.toString() ?? '';
      final ms = int.tryParse('${meta['internalDate']}') ?? 0;
      out.add(ExportMail(id, h('From'), h('Subject'), DateTime.fromMillisecondsSinceEpoch(ms)));
    }
    return out;
  }

  Future<void> disconnect() async {
    final refresh = await keys.read(_refreshKey);
    if (refresh != null) {
      try {
        await client.post(Uri.parse('https://oauth2.googleapis.com/revoke'), body: {'token': refresh}).timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
    await keys.delete(_refreshKey);
  }
}
