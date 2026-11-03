import 'dart:convert';

import 'package:http/http.dart' as http;

/// 3번 하드 자료 검색 엔진(파이썬, 윈도우 PC)과 이야기하는 도구. 엔진은 그대로 두고 주소로만 연결한다.
/// 하드 원본은 절대 바꾸지 않는다: 이 도구는 읽기와 "기록 추가"만 한다.
class EngineClient {
  EngineClient({required this.baseUrl, this.token, http.Client? client}) : _c = client ?? http.Client();
  final String baseUrl;
  String? token;
  final http.Client _c;

  Map<String, String> get _h => {
        'content-type': 'application/json',
        'x-hd-user': 'default',
        if (token != null && token!.isNotEmpty) 'x-hd-token': token!,
      };

  Uri _u(String path, [Map<String, String>? q]) => Uri.parse(baseUrl.replaceAll(RegExp(r'/+$'), '') + path).replace(queryParameters: q);

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? q]) async {
    final r = await _c.get(_u(path, q), headers: _h).timeout(const Duration(seconds: 8));
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 400) throw EngineError('${(j is Map ? j['error'] : null) ?? '엔진 응답 ${r.statusCode}'}', needPair: j is Map && j['need_pair'] == true);
    return (j as Map).cast<String, dynamic>();
  }

  /// 엔진이 켜져 있는가
  Future<bool> health() async {
    try {
      final r = await _c.get(_u('/api/health')).timeout(const Duration(seconds: 4));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 6자리 연결 번호로 표(token)를 받는다.
  Future<String> pair(String code) async {
    final r = await _c.post(_u('/api/pair'), headers: _h, body: jsonEncode({'code': code.trim()})).timeout(const Duration(seconds: 10));
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    if (r.statusCode != 200) throw EngineError('${j['error'] ?? '연결하지 못했어요'}');
    token = '${j['token']}';
    return token!;
  }

  /// 얼굴·장면 모델 상태 ({"faces": true/false, ...})
  Future<Map<String, dynamic>> recognition() => _get('/api/recognition');

  /// 홈 "오늘 할 일" 카드 (예: 오늘의 추억)
  Future<Map<String, dynamic>> today() => _get('/api/today');

  /// 이름·내용·장면 검색. 결과는 (이름, 폴더) 목록.
  Future<List<({int? id, String name, String dir, String kind})>> search(String q, {int size = 10}) async {
    final j = await _get('/api/search', {'q': q, 'page_size': '$size'});
    final out = <({int? id, String name, String dir, String kind})>[];
    for (final k in ['files', 'content', 'scenes']) {
      final sec = j[k];
      if (sec is! Map) continue;
      for (final it in (sec['items'] as List? ?? const []).cast<Map>()) {
        out.add((id: it['id'] as int?, name: '${it['name'] ?? it['title'] ?? ''}', dir: '${it['dir'] ?? ''}', kind: k));
      }
    }
    return out;
  }

  /// 개인 기록 타임라인에 글 기록 하나 추가 (엔진의 "음성 일기" 저장 경로를 그대로 사용). 하드 원본은 건드리지 않는다.
  Future<int?> addRecord(String text) async {
    final req = http.MultipartRequest('POST', _u('/api/records/voice-diary'))
      ..headers.addAll({..._h}..remove('content-type'))
      ..fields['text'] = text;
    final r = await http.Response.fromStream(await _c.send(req).timeout(const Duration(seconds: 10)));
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 400) throw EngineError('${(j is Map ? j['error'] : null) ?? '엔진 응답 ${r.statusCode}'}');
    return (j as Map)['id'] as int?;
  }

  /// 썸네일 주소 (채널 소재로 보낼 때)
  Uri thumbUrl(int fileId) => _u('/api/files/$fileId/thumb');
  Uri rawUrl(int fileId) => _u('/api/files/$fileId/raw');
}

class EngineError implements Exception {
  EngineError(this.message, {this.needPair = false});
  final String message;
  final bool needPair;
  @override
  String toString() => message;
}
