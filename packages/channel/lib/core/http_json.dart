import 'dart:convert';

import 'package:http/http.dart' as http;

import 'failure.dart';
import 'logger.dart';
import 'retry.dart';

/// JSON 을 주고받는 HTTP 도우미. 모든 외부 호출은 시간 제한 + 재시도 + 오류 구분을 거친다.
class JsonHttp {
  JsonHttp(this.client, {this.logger, this.sleep, this.timeout = const Duration(seconds: 30)});

  final http.Client client;
  final AppLogger? logger;
  final Sleeper? sleep;
  final Duration timeout;

  Future<Map<String, dynamic>> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    Object? body,
    CancelToken? cancel,
    int maxAttempts = 3,
  }) {
    return withRetry<Map<String, dynamic>>(
      () async {
        final req = http.Request(method, url);
        req.headers.addAll(headers);
        if (body != null) {
          if (body is String) {
            req.body = body;
          } else if (body is List<int>) {
            req.bodyBytes = body;
          } else {
            req.headers['content-type'] = 'application/json; charset=utf-8';
            req.body = jsonEncode(body);
          }
        }
        final streamed = await client.send(req);
        final res = await http.Response.fromStream(streamed);
        return decodeResponse(res, label: '$method ${url.host}${url.path}');
      },
      timeout: timeout,
      maxAttempts: maxAttempts,
      cancel: cancel,
      sleep: sleep ?? (d) => Future<void>.delayed(d),
    );
  }

  Map<String, dynamic> decodeResponse(http.Response res, {String label = ''}) {
    final code = res.statusCode;
    if (code >= 200 && code < 300) {
      if (res.body.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{'data': decoded};
    }
    final failure = classifyHttpError(code, res.body);
    logger?.warn('HTTP $code $label → ${failure.kind.name}');
    throw failure;
  }
}

/// HTTP 상태 코드와 응답 본문으로 실패 종류를 나눈다.
AppFailure classifyHttpError(int code, String body) {
  final lower = body.toLowerCase();
  if (code == 401) {
    return AppFailure(FailureKind.tokenExpired, 'HTTP 401');
  }
  if (code == 400 && lower.contains('invalid_grant')) {
    // 리프레시 토큰이 취소되었거나 만료됨 → 다시 연결 필요
    return AppFailure(FailureKind.permissionRevoked, 'invalid_grant');
  }
  if (code == 403) {
    if (lower.contains('quotaexceeded') || lower.contains('dailylimitexceeded') || lower.contains('quota')) {
      return AppFailure(FailureKind.quotaExceeded, 'HTTP 403 quota');
    }
    if (lower.contains('ratelimitexceeded') || lower.contains('userratelimit')) {
      return AppFailure(FailureKind.rateLimited, 'HTTP 403 rate');
    }
    return AppFailure(FailureKind.permissionRevoked, 'HTTP 403');
  }
  if (code == 404) return AppFailure(FailureKind.notFound, 'HTTP 404');
  if (code == 409) return AppFailure(FailureKind.conflict, 'HTTP 409');
  if (code == 429) return AppFailure(FailureKind.rateLimited, 'HTTP 429');
  if (code >= 500) return AppFailure(FailureKind.network, 'HTTP $code');
  return AppFailure(FailureKind.invalidInput, 'HTTP $code');
}
