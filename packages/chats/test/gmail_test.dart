import 'dart:convert';

import 'package:ai_chat_organizer/data/key_store.dart';
import 'package:ai_chat_organizer/services/gmail_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response jsonRes(Object o, [int code = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(o)), code, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  test('구글 JSON 불러오기: 데스크톱 앱만 받음', () {
    final (id, secret) = GmailService.parseClientJson(
      jsonEncode({
        'installed': {'client_id': '123-abc.apps.googleusercontent.com', 'client_secret': 'GOCSPX-xyz'},
      }),
    );
    expect(id, '123-abc.apps.googleusercontent.com');
    expect(secret, 'GOCSPX-xyz');
    expect(
      () => GmailService.parseClientJson(
        jsonEncode({
          'web': {'client_id': 'x.apps.googleusercontent.com'},
        }),
      ),
      throwsA(isA<GmailError>().having((e) => e.kind, 'kind', GmailErrorKind.webClient)),
    );
    expect(() => GmailService.parseClientJson('아님'), throwsA(isA<GmailError>()));
  });

  test('연결(브라우저 허용 → 코드 → 토큰) 후 안내 메일 찾기', () async {
    final keys = MemoryKeyStore();
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.url.path == '/token') {
        final form = Uri.splitQueryString(req.body);
        if (form['grant_type'] == 'authorization_code') {
          expect(form['code'], 'CODE123');
          expect(form['code_verifier'], isNotEmpty);
          return jsonRes({'access_token': 'a1', 'refresh_token': 'r1', 'expires_in': 3600});
        }
        return jsonRes({'access_token': 'a2', 'expires_in': 3600});
      }
      if (req.url.path.endsWith('/messages')) {
        expect(req.headers['Authorization'], 'Bearer a2');
        return jsonRes({
          'messages': [
            {'id': 'm1'},
          ],
        });
      }
      if (req.url.path.endsWith('/messages/m1')) {
        return jsonRes({
          'internalDate': '${DateTime(2026, 11, 2).millisecondsSinceEpoch}',
          'payload': {
            'headers': [
              {'name': 'From', 'value': 'Anthropic <no-reply@anthropic.com>'},
              {'name': 'Subject', 'value': 'Your data export is ready'},
            ],
          },
        });
      }
      return http.Response('?', 404);
    });
    final g = GmailService(
      keys: keys,
      userId: 'u1',
      client: client,
      openBrowser: (url) async {
        // 사용자가 브라우저에서 허용한 것처럼 되돌아오기 주소로 요청
        expect(url.queryParameters['code_challenge_method'], 'S256');
        expect(url.queryParameters['scope'], GmailService.scope);
        final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
        final back = redirect.replace(queryParameters: {'code': 'CODE123', 'state': url.queryParameters['state']});
        await http.get(back);
      },
    );
    await expectLater(g.connect(clientId: 'x.apps.googleusercontent.com'), throwsA(isA<GmailError>())); // 비밀번호 없음
    await g.saveSecret('secret');
    await g.connect(clientId: 'x.apps.googleusercontent.com');
    expect(await g.isConnected(), isTrue);
    final mails = await g.recentExportMails('x.apps.googleusercontent.com');
    expect(mails.single.subject, contains('export'));
    expect(mails.single.openUrl, contains('m1'));
  });

  test('7일 만료(invalid_grant)는 "다시 연결" 안내', () async {
    final keys = MemoryKeyStore();
    await keys.write('gmail-secret-u1', 's');
    await keys.write('gmail-refresh-u1', 'old');
    final g = GmailService(
      keys: keys,
      userId: 'u1',
      client: MockClient((_) async => jsonRes({'error': 'invalid_grant'}, 400)),
      openBrowser: (_) async {},
    );
    await expectLater(
      g.recentExportMails('x.apps.googleusercontent.com'),
      throwsA(isA<GmailError>().having((e) => e.kind, 'kind', GmailErrorKind.expired)),
    );
  });
}
