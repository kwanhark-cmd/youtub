import 'dart:convert';
import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// 가짜 GitHub: releases/latest 에 [status]와 [body]로 답한다.
UpdateChecker checker(int status, {Object? body, String current = '1.0.0', List<Uri>? seen}) => UpdateChecker(
      repo: 'kwanhark-cmd/youtub',
      currentVersion: current,
      client: MockClient((r) async {
        seen?.add(r.url);
        return http.Response(body == null ? '' : jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );

Map<String, Object?> release(String tag) => {
      'tag_name': tag,
      'body': '## 안드로이드\n먼저 백업\n\n```\n${'a' * 64}  gaein-biseo-android.apk\n```',
      'assets': [
        {'name': 'gaein-biseo-android.apk', 'browser_download_url': 'https://github.com/kwanhark-cmd/youtub/releases/download/$tag/gaein-biseo-android.apk'},
        {'name': 'gaein-biseo-windows.zip', 'browser_download_url': 'https://github.com/kwanhark-cmd/youtub/releases/download/$tag/gaein-biseo-windows.zip'},
      ],
    };

void main() {
  test('새 버전이 있으면 정보와 설치 파일 주소를 돌려준다', () async {
    final seen = <Uri>[];
    final info = await checker(200, body: release('v1.1.0'), seen: seen).check();
    expect(seen.single.toString(), 'https://api.github.com/repos/kwanhark-cmd/youtub/releases/latest');
    expect(info, isNotNull);
    expect(info!.version, '1.1.0');
    expect(info.assets['gaein-biseo-android.apk'], endsWith('/v1.1.0/gaein-biseo-android.apk'));
    expect(info.assets, hasLength(2));
    expect(info.sha256['gaein-biseo-android.apk'], 'a' * 64);
    expect(info.notes, startsWith('## 안드로이드'));
  });

  test('같은 버전이거나 더 낮으면 null (최신)', () async {
    expect(await checker(200, body: release('v1.0.0')).check(), isNull);
    expect(await checker(200, body: release('v0.9.0')).check(), isNull);
  });

  test('아직 Releases 가 없으면(404) null', () async {
    expect(await checker(404, body: {'message': 'Not Found'}).check(), isNull);
  });

  test('서버 오류(500)면 예외 (화면이 "다시 해 보세요"를 보여 준다)', () async {
    expect(checker(500).check(), throwsA(isA<HttpException>()));
  });
}
