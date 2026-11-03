import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

/// 지메일 읽기 전용 연결. 사용자가 설정에서 연결했을 때만 쓰인다.
/// 메일 본문은 분석에 필요한 동안 메모리에만 두고 저장하지 않는다.
class GmailMessage {
  const GmailMessage(this.id, this.subject, this.from, this.body, this.date);
  final String id;
  final String subject;
  final String from;
  final String body;
  final DateTime? date;
}

class GmailException implements Exception {
  const GmailException(this.message);
  final String message;
}

class GoogleOAuth {
  GoogleOAuth({
    required this.clientId,
    this.clientSecret = '',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String clientId;

  /// 구글 "데스크톱 앱" 클라이언트는 비밀값이 공개 정보로 취급되지만, 있으면 함께 보낸다.
  final String clientSecret;
  final http.Client _client;

  static const scope = 'https://www.googleapis.com/auth/gmail.readonly';
  static const authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const tokenEndpoint = 'https://oauth2.googleapis.com/token';

  static String _b64url(List<int> b) => base64Url.encode(b).replaceAll('=', '');

  static String newVerifier([Random? r]) {
    final rnd = r ?? Random.secure();
    return _b64url(List.generate(48, (_) => rnd.nextInt(256)));
  }

  static Future<String> challengeFor(String verifier) async {
    final h = await Sha256().hash(ascii.encode(verifier));
    return _b64url(h.bytes);
  }

  Uri authUrl({
    required String redirectUri,
    required String challenge,
    required String state,
  }) => Uri.parse(authEndpoint).replace(
    queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': scope,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'access_type': 'offline',
      'prompt': 'consent',
      'state': state,
    },
  );

  /// 브라우저 로그인 → 이 기기의 임시 주소(127.0.0.1)로 돌아온 코드를 받아 토큰으로 바꾼다.
  /// [openBrowser] 는 url_launcher 등으로 주소를 연다. 반환: refresh token.
  Future<String> signIn(Future<bool> Function(Uri) openBrowser) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirect = 'http://127.0.0.1:${server.port}';
      final verifier = newVerifier();
      final state = newVerifier().substring(0, 16);
      final url = authUrl(
        redirectUri: redirect,
        challenge: await challengeFor(verifier),
        state: state,
      );
      if (!await openBrowser(url)) throw const GmailException('브라우저를 열 수 없어요.');
      final req = await server.first.timeout(const Duration(minutes: 5));
      final q = req.uri.queryParameters;
      req.response
        ..headers.contentType = ContentType.html
        ..write(
          '<html><body style="font-size:24px;font-family:sans-serif">'
          '연결이 끝났어요. 이 창을 닫고 앱으로 돌아가세요.</body></html>',
        );
      await req.response.close();
      if (q['state'] != state || q['code'] == null) {
        throw const GmailException('연결이 취소되었어요.');
      }
      final res = await _client.post(
        Uri.parse(tokenEndpoint),
        body: {
          'client_id': clientId,
          if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
          'code': q['code']!,
          'code_verifier': verifier,
          'grant_type': 'authorization_code',
          'redirect_uri': redirect,
        },
      );
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final rt = j['refresh_token'] as String?;
      if (res.statusCode != 200 || rt == null) {
        throw const GmailException('지메일 연결에 실패했어요.');
      }
      return rt;
    } finally {
      await server.close(force: true);
    }
  }

  Future<String> accessToken(String refreshToken) async {
    final http.Response res;
    try {
      res = await _client.post(
        Uri.parse(tokenEndpoint),
        body: {
          'client_id': clientId,
          if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        },
      );
    } catch (_) {
      throw const GmailException('인터넷 연결을 확인해 주세요.');
    }
    if (res.statusCode != 200) {
      throw const GmailException('지메일 연결이 끊겼어요. 설정에서 다시 연결해 주세요.');
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['access_token']
        as String;
  }
}

class GmailClient {
  GmailClient(this.accessToken, {http.Client? client})
    : _client = client ?? http.Client();
  final String accessToken;
  final http.Client _client;

  static const defaultQuery =
      '(영수증 OR 결제 OR 청구 OR 크레딧 OR 체험 OR receipt OR invoice OR "payment" OR credits OR trial) newer_than:60d';

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? q,
  ]) async {
    final uri = Uri.https(
      'gmail.googleapis.com',
      '/gmail/v1/users/me/$path',
      q,
    );
    final http.Response res;
    try {
      res = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
    } catch (_) {
      throw const GmailException('인터넷 연결을 확인해 주세요.');
    }
    if (res.statusCode == 401) {
      throw const GmailException('지메일 연결이 끊겼어요. 다시 연결해 주세요.');
    }
    if (res.statusCode != 200) throw const GmailException('메일을 가져오지 못했어요.');
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<List<GmailMessage>> searchReceipts({
    int max = 15,
    String query = defaultQuery,
  }) async {
    final list = await _get('messages', {'q': query, 'maxResults': '$max'});
    final ids = (list['messages'] as List? ?? []).map(
      (m) => (m as Map)['id'] as String,
    );
    final out = <GmailMessage>[];
    for (final id in ids) {
      try {
        out.add(parseMessage(await _get('messages/$id', {'format': 'full'})));
      } catch (_) {
        // 한 통이 이상해도 나머지는 계속.
      }
    }
    return out;
  }

  static GmailMessage parseMessage(Map<String, dynamic> m) {
    final payload = (m['payload'] as Map?)?.cast<String, dynamic>() ?? {};
    final headers = (payload['headers'] as List? ?? []).cast<Map>();
    String h(String name) => headers
        .firstWhere(
          (e) => (e['name'] as String).toLowerCase() == name,
          orElse: () => {'value': ''},
        )['value']
        .toString();
    final body = _extractText(payload);
    final ms = int.tryParse('${m['internalDate'] ?? ''}');
    return GmailMessage(
      m['id'] as String,
      h('subject'),
      h('from'),
      body.isEmpty ? (m['snippet'] as String? ?? '') : body,
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  static String _extractText(Map<String, dynamic> part) {
    final mime = part['mimeType'] as String? ?? '';
    final data = (part['body'] as Map?)?['data'] as String?;
    if (data != null && (mime == 'text/plain' || mime == 'text/html')) {
      final text = utf8.decode(
        base64Url.decode(base64Url.normalize(data)),
        allowMalformed: true,
      );
      return mime == 'text/html' ? stripHtml(text) : text;
    }
    final parts = (part['parts'] as List? ?? [])
        .cast<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final plain = parts.where((p) => p['mimeType'] == 'text/plain').toList();
    for (final p in [...plain, ...parts]) {
      final t = _extractText(p);
      if (t.isNotEmpty) return t;
    }
    return '';
  }
}

String stripHtml(String html) => html
    .replaceAll(
      RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false),
      ' ',
    )
    .replaceAll(
      RegExp(r'<br\s*/?>|</p>|</div>|</tr>', caseSensitive: false),
      '\n',
    )
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&#8361;', '₩')
    .replaceAll(RegExp(r'[ \t]+'), ' ');
