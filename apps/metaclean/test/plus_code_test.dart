import 'package:flutter_test/flutter_test.dart';
import 'package:metaclean/src/plus_code.dart';

void main() {
  test('전체 플러스코드를 좌표로 (검증 벡터)', () {
    final r = decodeOlc('8FVC9G8F+6X'); // 취리히
    expect(r.lat, closeTo(47.3656, 0.001));
    expect(r.lng, closeTo(8.5249, 0.001));
  });

  test('사용자 케이스: 짧은 코드 + 지역명', () {
    final r = parseLocation('75W2+4PV 용인시 경기도');
    expect(r.ok, isTrue);
    expect(r.lat, closeTo(37.2954, 0.002));
    expect(r.lng, closeTo(127.1518, 0.002));
  });

  test('전체 플러스코드만 입력', () {
    final r = parseLocation('8Q9975W2+4PV');
    expect(r.ok, isTrue);
    expect(r.lat, closeTo(37.2954, 0.002));
    expect(r.lng, closeTo(127.1518, 0.002));
  });

  test('소수점 좌표 (쉼표)', () {
    final r = parseLocation('37.2954, 127.1518');
    expect(r.ok, isTrue);
    expect(r.lat, closeTo(37.2954, 1e-6));
    expect(r.lng, closeTo(127.1518, 1e-6));
  });

  test('소수점 좌표 (공백/음수)', () {
    final r = parseLocation('-33.8688  151.2093');
    expect(r.ok, isTrue);
    expect(r.lat, closeTo(-33.8688, 1e-6));
    expect(r.lng, closeTo(151.2093, 1e-6));
  });

  test('범위 밖 좌표는 오류', () {
    expect(parseLocation('200, 10').ok, isFalse);
  });

  test('짧은 코드인데 지역명 없으면 안내 오류', () {
    final r = parseLocation('75W2+4PV');
    expect(r.ok, isFalse);
    expect(r.error, contains('지역'));
  });

  test('알아볼 수 없는 입력은 안내 오류', () {
    final r = parseLocation('여기 어딘가');
    expect(r.ok, isFalse);
    expect(r.error, contains('플러스코드'));
  });

  test('남양주를 양주보다 먼저 맞춘다', () {
    final r = referenceFor('남양주시')!;
    expect(r.lat, closeTo(37.6360, 1e-4));
  });

  test('경기 광주와 광주광역시를 구분한다', () {
    final gyeonggi = referenceFor('광주시 경기도')!;
    expect(gyeonggi.lat, closeTo(37.4292, 1e-4));
    final metro = referenceFor('광주광역시')!;
    expect(metro.lat, closeTo(35.1595, 1e-4));
  });
}
