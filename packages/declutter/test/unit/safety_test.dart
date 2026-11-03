import 'dart:io';

import 'package:binugi/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 안전 점검 (자동): 당근·번개 자동 게시·채팅 코드 없음, 정해진 주소만 사용, 분류 세 가지
void main() {
  final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList();
  final all = {for (final f in files) f.path: f.readAsStringSync()};

  test('코드에 나오는 인터넷 주소는 허락된 곳뿐', () {
    const allowed = {
      'api.anthropic.com', // AI (사용자가 켰을 때만)
      'api.github.com', // 업데이트 확인
      'accounts.google.com', 'oauth2.googleapis.com', 'gmail.googleapis.com', 'console.cloud.google.com', // 지메일(읽기 전용)
      'www.daangn.com', 'm.bunjang.co.kr', // 열기만
      '127.0.0.1',
      'www.googleapis.com', // 지메일 읽기 권한 이름(scope) — 호출 주소 아님
    };
    final hosts = <String>{};
    for (final s in all.values) {
      for (final m in RegExp(r'https?://([a-zA-Z0-9.\-]+)').allMatches(s)) {
        hosts.add(m.group(1)!);
      }
    }
    expect(hosts.difference(allowed), isEmpty, reason: '허락되지 않은 주소: ${hosts.difference(allowed)}');
  });

  test('당근마켓·번개장터는 페이지 열기만 (글 올리기·채팅 읽기 없음)', () {
    for (final e in all.entries) {
      final s = e.value;
      if (s.contains('daangn.com') || s.contains('bunjang.co.kr')) {
        expect(e.key, endsWith('market_links.dart'), reason: '마켓 주소는 한 파일에만');
        expect(s, isNot(contains('http.post')));
        expect(s, isNot(contains('client.post')));
        expect(s, isNot(contains('WebView')));
      }
      expect(s.toLowerCase(), isNot(contains('chat_api')));
    }
  });

  test('열쇠·사진 데이터를 기록(log)에 넘기지 않음', () {
    for (final e in all.entries) {
      for (final line in e.value.split('\n').where((l) => l.contains('log.'))) {
        expect(line, isNot(contains('apiKey')), reason: '${e.key}: $line');
        expect(line, isNot(contains('base64')), reason: '${e.key}: $line');
        expect(line, isNot(contains('RefreshToken')), reason: '${e.key}: $line');
      }
    }
  });

  test('분류는 세 가지뿐 (보관·보류 없음)', () {
    expect(Decision.values.map((d) => d.label), ['지금 쓰는 것', '판매', '폐기']);
    for (final s in all.values) {
      expect(s, isNot(contains("'보류'")));
      expect(s, isNot(contains("'보관함'")));
    }
  });
}
