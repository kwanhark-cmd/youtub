import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import '../core/errors.dart';
import '../core/logger.dart';

/// 구글 "데스크톱 앱" 클라이언트 JSON에서 ID·비밀번호 꺼내기
(String, String)? parseGoogleClientJson(String text) {
  try {
    final j = jsonDecode(text) as Map<String, dynamic>;
    final inner = (j['installed'] ?? j['web'] ?? j) as Map<String, dynamic>;
    final id = inner['client_id'] as String?;
    final secret = inner['client_secret'] as String?;
    if (id == null || id.isEmpty) return null;
    return (id, secret ?? '');
  } catch (_) {
    return null;
  }
}

/// 파일 내용에서 AI 열쇠(sk-ant-...) 찾기. 없으면 첫 줄.
String? findApiKey(String text) {
  final m = RegExp(r'sk-ant-[A-Za-z0-9_\-]+').firstMatch(text);
  if (m != null) return m.group(0);
  final first = text.split(RegExp(r'\r?\n')).map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
  return first.isEmpty || first.contains(' ') ? null : first;
}

class GmailMail {
  final String subject;
  final DateTime? date;
  final String text;
  GmailMail(this.subject, this.date, this.text);
}

class GmailExpired implements Exception {}

/// 지메일 읽기 전용 연결. 메일을 보내거나 지우지 않습니다.
class GmailService {
  static const scope = 'https://www.googleapis.com/auth/gmail.readonly';
  static const authUrl = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const tokenUrl = 'https://oauth2.googleapis.com/token';
  final http.Client client;
  GmailService(this.client);

  static String _b64url(List<int> b) => base64Url.encode(b).replaceAll('=', '');

  /// 브라우저로 구글 로그인 → 이 기기(127.0.0.1)로 돌아온 코드를 열쇠로 바꿈. 돌려주는 값: 갱신 토큰.
  /// [openBrowser]: 주소 열기 (앱에서는 url_launcher, 테스트에서는 가짜 브라우저)
  Future<String> connect({
    required String clientId,
    required String clientSecret,
    required Future<void> Function(Uri) openBrowser,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final rnd = Random.secure();
    final verifier = _b64url(List<int>.generate(48, (_) => rnd.nextInt(256)));
    final challenge = _b64url((await Sha256().hash(utf8.encode(verifier))).bytes);
    final state = _b64url(List<int>.generate(16, (_) => rnd.nextInt(256)));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';
    try {
      final url = Uri.parse(authUrl).replace(
        queryParameters: {
          'client_id': clientId,
          'redirect_uri': redirect,
          'response_type': 'code',
          'scope': scope,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'access_type': 'offline',
          'prompt': 'consent',
          'state': state,
        },
      );
      await openBrowser(url);
      final req = await server.first.timeout(timeout, onTimeout: () => throw UserFacingException('구글 로그인을 5분 안에 마치지 못했어요. 다시 해 주세요.'));
      final q = req.uri.queryParameters;
      final ok = q['code'] != null && q['state'] == state;
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
          '<html><body style="font-family:sans-serif;font-size:22px;padding:40px">'
          '${ok ? '연결됐어요! 이 창을 닫고 앱으로 돌아가세요.' : '연결하지 못했어요. 앱에서 다시 해 주세요.'}</body></html>',
        );
      await req.response.close();
      if (!ok) throw UserFacingException(q['error'] == 'access_denied' ? '구글 연결을 허락하지 않았어요.' : '구글 연결에 실패했어요. 다시 해 주세요.');
      final res = await client.post(
        Uri.parse(tokenUrl),
        body: {
          'code': q['code']!,
          'client_id': clientId,
          'client_secret': clientSecret,
          'redirect_uri': redirect,
          'grant_type': 'authorization_code',
          'code_verifier': verifier,
        },
      );
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final refresh = j['refresh_token'] as String?;
      if (res.statusCode != 200 || refresh == null) {
        log.error('[지메일] 토큰 받기 실패 ${res.statusCode} ${j['error']}');
        throw UserFacingException('구글 연결 열쇠를 받지 못했어요. 클라이언트 ID·비밀번호를 확인해 주세요.');
      }
      return refresh;
    } finally {
      await server.close(force: true);
    }
  }

  Future<String> _accessToken(String clientId, String clientSecret, String refresh) async {
    final res = await client.post(
      Uri.parse(tokenUrl),
      body: {'client_id': clientId, 'client_secret': clientSecret, 'refresh_token': refresh, 'grant_type': 'refresh_token'},
    );
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 400 && j['error'] == 'invalid_grant') throw GmailExpired();
    final t = j['access_token'] as String?;
    if (res.statusCode != 200 || t == null) throw UserFacingException('지메일에 접속하지 못했어요. (${res.statusCode})');
    return t;
  }

  /// 제목 규칙에 맞는 최근 메일들 (제미나이 정리 메일)
  Future<List<GmailMail>> fetch({required String clientId, required String clientSecret, required String refresh, required String subject, int max = 5}) async {
    final token = await _accessToken(clientId, clientSecret, refresh);
    final h = {'authorization': 'Bearer $token'};
    final q = 'subject:"$subject" newer_than:60d';
    final list = await client.get(
      Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages').replace(queryParameters: {'q': q, 'maxResults': '$max'}),
      headers: h,
    );
    if (list.statusCode != 200) throw UserFacingException('지메일 목록을 읽지 못했어요. (${list.statusCode})');
    final ids = (((jsonDecode(list.body) as Map)['messages'] as List?) ?? const []).map((m) => (m as Map)['id'] as String).toList();
    final out = <GmailMail>[];
    for (final id in ids) {
      final r = await client.get(Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$id?format=full'), headers: h);
      if (r.statusCode != 200) continue;
      final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final payload = (m['payload'] as Map?)?.cast<String, dynamic>() ?? {};
      final headers = ((payload['headers'] as List?) ?? const []).cast<Map>();
      String header(String n) => headers.firstWhere((x) => (x['name'] as String).toLowerCase() == n, orElse: () => {'value': ''})['value'] as String;
      final ms = int.tryParse('${m['internalDate'] ?? ''}');
      out.add(GmailMail(header('subject'), ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms), _plainText(payload)));
    }
    return out;
  }

  static String _decode(String data) => utf8.decode(base64Url.decode(base64Url.normalize(data)), allowMalformed: true);

  /// 메일 본문 글자 꺼내기 (text/plain 우선, 없으면 html에서 태그 제거)
  static String _plainText(Map<String, dynamic> part) {
    final mime = part['mimeType'] as String? ?? '';
    final data = (part['body'] as Map?)?['data'] as String?;
    if (mime == 'text/plain' && data != null) return _decode(data);
    final parts = ((part['parts'] as List?) ?? const []).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    for (final p in parts) {
      if (p['mimeType'] == 'text/plain') return _plainText(p);
    }
    for (final p in parts) {
      final t = _plainText(p);
      if (t.isNotEmpty) return t;
    }
    if (mime == 'text/html' && data != null) {
      return _decode(data).replaceAll(RegExp(r'<br\s*/?>|</p>|</li>', caseSensitive: false), '\n').replaceAll(RegExp(r'<[^>]+>'), '');
    }
    return '';
  }
}
