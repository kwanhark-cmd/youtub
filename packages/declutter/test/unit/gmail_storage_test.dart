import 'dart:convert';
import 'dart:io';

import 'package:binugi/data/models.dart';
import 'package:binugi/services/gmail_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers.dart';

String b64(String s) => base64Url.encode(utf8.encode(s));

void main() {
  test('구글 JSON에서 ID·비밀번호, 파일에서 AI 열쇠 찾기', () {
    final r = parseGoogleClientJson(
      '{"installed":{"client_id":"abc.apps.googleusercontent.com","client_secret":"GOCSPX-xyz","redirect_uris":["http://localhost"]}}',
    );
    expect(r, ('abc.apps.googleusercontent.com', 'GOCSPX-xyz'));
    expect(parseGoogleClientJson('아무 글'), isNull);
    expect(findApiKey('ANTHROPIC_API_KEY=sk-ant-api03-AbC_d-1\n'), 'sk-ant-api03-AbC_d-1');
    expect(findApiKey('  \n'), isNull);
  });

  test('지메일 연결: 브라우저 로그인 → 이 기기로 돌아온 코드 → 열쇠 (실제 구글 호출 없음)', () async {
    late Map<String, String> tokenBody;
    final client = MockClient((req) async {
      expect(req.url.toString(), GmailService.tokenUrl);
      tokenBody = Uri.splitQueryString(req.body);
      return http.Response(jsonEncode({'access_token': 'a', 'refresh_token': 'r-123'}), 200);
    });
    final g = GmailService(client);
    final refresh = await g.connect(
      clientId: 'cid',
      clientSecret: 'sec',
      openBrowser: (u) async {
        expect(u.host, 'accounts.google.com');
        expect(u.queryParameters['scope'], contains('gmail.readonly'), reason: '읽기 전용');
        expect(u.queryParameters['code_challenge_method'], 'S256');
        // 가짜 브라우저: 구글이 이 기기로 돌려보내는 것처럼 요청
        final back = Uri.parse(u.queryParameters['redirect_uri']!).replace(queryParameters: {'code': 'CODE1', 'state': u.queryParameters['state']!});
        Future(() async {
          final c = HttpClient();
          final res = await (await c.getUrl(back)).close();
          expect(await res.transform(utf8.decoder).join(), contains('연결됐어요'));
          c.close();
        });
      },
    );
    expect(refresh, 'r-123');
    expect(tokenBody['code'], 'CODE1');
    expect(tokenBody['grant_type'], 'authorization_code');
    expect(tokenBody['code_verifier'], isNotEmpty);
  });

  test('제미나이 정리 메일 가져오기 (제목 규칙) / 7일 만료 구분', () async {
    final client = MockClient((req) async {
      if (req.url.host == 'oauth2.googleapis.com') return http.Response(jsonEncode({'access_token': 'tok'}), 200);
      expect(req.headers['authorization'], 'Bearer tok');
      if (req.url.path.endsWith('/messages')) {
        expect(req.url.queryParameters['q'], contains('subject:"[비우기 정리]"'));
        return http.Response(
          jsonEncode({
            'messages': [
              {'id': 'm1'},
            ],
          }),
          200,
        );
      }
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'internalDate': '1767225600000',
            'payload': {
              'mimeType': 'multipart/alternative',
              'headers': [
                {'name': 'Subject', 'value': '[비우기 정리] 거실'},
              ],
              'parts': [
                {
                  'mimeType': 'text/html',
                  'body': {'data': b64('<p>무시</p>')},
                },
                {
                  'mimeType': 'text/plain',
                  'body': {'data': b64('- 커피 머신: 판매\n- 낡은 의자: 폐기')},
                },
              ],
            },
          }),
        ),
        200,
      );
    });
    final mails = await GmailService(client).fetch(clientId: 'c', clientSecret: 's', refresh: 'r', subject: '[비우기 정리]');
    expect(mails.single.subject, '[비우기 정리] 거실');
    expect(mails.single.text, contains('커피 머신: 판매'));

    final expired = MockClient((_) async => http.Response(jsonEncode({'error': 'invalid_grant'}), 400));
    expect(() => GmailService(expired).fetch(clientId: 'c', clientSecret: 's', refresh: 'r', subject: 'x'), throwsA(isA<GmailExpired>()));
  });

  test('사진 정리: 판매·폐기 완료 물건의 큰 사진만 지우고 사연 있는 물건은 유지', () async {
    final (s, _) = await makeState();
    Future<Item> add(String name, {String story = ''}) async {
      final ph = await s.savePhoto(fakeJpeg(w: 1600, h: 1200, seed: name.length));
      final it = await s.addItem(name: name, photo: ph);
      if (story.isNotEmpty) await s.saveStory(it, story);
      return it;
    }

    final sold = await add('판 물건');
    await s.sales.startSelling(sold, price: 1000);
    await s.sales.setStatus(sold, SaleStatus.sold);
    final gone = await add('버린 물건');
    await s.decide(gone, Decision.discard);
    await s.markDiscardDone(gone);
    final memory = await add('추억 물건', story: '할머니 선물');
    await s.decide(memory, Decision.discard);
    await s.markDiscardDone(memory);
    final keep = await add('쓰는 물건');
    await s.decide(keep, Decision.use);

    final before = s.storage.usage();
    expect((await s.storage.cleanupTargets(s.uid)).map((i) => i.name).toSet(), {'판 물건', '버린 물건'});
    final freed = await s.storage.cleanupDonePhotos(s.uid);
    expect(freed, greaterThan(0));
    expect(s.storage.usage().$2, lessThan(before.$2));
    final soldAfter = (await s.repo.item(s.uid, sold.id!))!;
    expect(soldAfter.photoPath, soldAfter.thumbPath, reason: '작은 사진은 남김');
    expect(File(s.paths.abs(soldAfter.photoPath!)).existsSync(), isTrue);
    final memAfter = (await s.repo.item(s.uid, memory.id!))!;
    expect(memAfter.photoPath, isNot(memAfter.thumbPath), reason: '사연 있는 물건은 그대로');
  });
}
