/// 위치 입력 해석: 소수점 좌표 또는 구글 지도 "플러스 코드"를 받는다.
///
/// 구글 지도는 좌표 대신 "75W2+4PV 용인시 경기도" 같은 플러스 코드를 자주 준다.
/// 이 파일은 그런 코드를 위도·경도로 바꾼다. (Open Location Code, Apache-2.0 사양)
library;

const _alphabet = '23456789CFGHJMPQRVWX';
const _sep = '+';
const _pad = '0';
const _pairLen = 10;
const _gridCols = 4;
const _gridRows = 5;

/// 위치 해석 결과. [ok]가 참이면 [lat]/[lng]가 채워진다.
class LocationResult {
  const LocationResult.ok(this.lat, this.lng) : error = null;
  const LocationResult.fail(this.error)
      : lat = null,
        lng = null;

  final double? lat;
  final double? lng;
  final String? error;

  bool get ok => lat != null && lng != null;
}

/// 전체 플러스 코드(예: 8Q9975W2+4PV)를 위도·경도 중심점으로 바꾼다.
({double lat, double lng}) decodeOlc(String code) {
  final c =
      code.toUpperCase().replaceAll(_sep, '').replaceAll(_pad, '');
  var lat = -90.0;
  var lng = -180.0;
  var latPlace = 400.0;
  var lngPlace = 400.0;
  var i = 0;
  while (i < _pairLen && i + 1 < c.length) {
    latPlace /= 20;
    lngPlace /= 20;
    lat += _alphabet.indexOf(c[i]) * latPlace;
    lng += _alphabet.indexOf(c[i + 1]) * lngPlace;
    i += 2;
  }
  var latHi = lat + latPlace;
  var lngHi = lng + lngPlace;
  if (c.length > _pairLen) {
    var rLat = latPlace;
    var rLng = lngPlace;
    var lat2 = lat;
    var lng2 = lng;
    var j = _pairLen;
    while (j < 15 && j < c.length) {
      rLat /= _gridRows;
      rLng /= _gridCols;
      final d = _alphabet.indexOf(c[j]);
      lat2 += (d ~/ _gridCols) * rLat;
      lng2 += (d % _gridCols) * rLng;
      j++;
    }
    lat = lat2;
    lng = lng2;
    latHi = lat + rLat;
    lngHi = lng + rLng;
  }
  return (lat: (lat + latHi) / 2, lng: (lng + lngHi) / 2);
}

double _clipLat(double x) => x < -90 ? -90 : (x > 90 ? 90 : x);
double _normLng(double x) {
  var v = x;
  while (v < -180) {
    v += 360;
  }
  while (v >= 180) {
    v -= 360;
  }
  return v;
}

/// 기준 좌표를 전체 코드로 인코딩한다(앞 글자만 쓰므로 10자리면 충분).
String _encodeOlc(double latIn, double lngIn, {int length = 10}) {
  var lat = _clipLat(latIn) + 90;
  var lng = _normLng(lngIn) + 180;
  if (lat >= 180) lat = 179.999999999;
  final sb = StringBuffer();
  var latPlace = 400.0;
  var lngPlace = 400.0;
  for (var k = 0; k < length ~/ 2; k++) {
    latPlace /= 20;
    lngPlace /= 20;
    final d = (lat / latPlace).floor().clamp(0, 19);
    lat -= d * latPlace;
    sb.write(_alphabet[d]);
    final d2 = (lng / lngPlace).floor().clamp(0, 19);
    lng -= d2 * lngPlace;
    sb.write(_alphabet[d2]);
  }
  return sb.toString();
}

/// 짧은 코드(예: 75W2+4PV)를 기준 좌표 근처로 복원해 위도·경도를 돌려준다.
({double lat, double lng}) recoverNearest(
    String short, double refLat, double refLng) {
  final up = short.toUpperCase();
  final sepAt = up.indexOf(_sep);
  final padLen = 8 - sepAt;
  final res = _pow20(2 - padLen ~/ 2);
  final half = res / 2;
  final refCode = _encodeOlc(refLat, refLng).replaceAll(_sep, '');
  final body = up.replaceAll(_sep, '');
  final merged = refCode.substring(0, padLen) + body;
  final full = '${merged.substring(0, 8)}+${merged.substring(8)}';
  var r = decodeOlc(full);
  var lat = r.lat;
  var lng = r.lng;
  if (refLat + half < lat && lat - res > -90) {
    lat -= res;
  } else if (refLat - half > lat && lat + res < 90) {
    lat += res;
  }
  if (refLng + half < lng && lng - res > -180) {
    lng -= res;
  } else if (refLng - half > lng && lng + res < 180) {
    lng += res;
  }
  return (lat: lat, lng: lng);
}

double _pow20(int n) {
  var v = 1.0;
  for (var k = 0; k < n; k++) {
    v *= 20;
  }
  return v;
}

/// 짧은 플러스 코드를 풀 때 쓰는 한국 도시·지역 기준 좌표(시청/중심 근처).
/// 지역명이 이 안에 있으면 좌표 없이도 복원할 수 있다.
const Map<String, (double, double)> _koreaPlaces = {
  // 특별·광역시, 특별자치
  '서울': (37.5665, 126.9780),
  '부산': (35.1796, 129.0756),
  '대구': (35.8714, 128.6014),
  '인천': (37.4563, 126.7052),
  '광주광역': (35.1595, 126.8526),
  '대전': (36.3504, 127.3845),
  '울산': (35.5384, 129.3114),
  '세종': (36.4800, 127.2890),
  // 경기도 시·군
  '수원': (37.2636, 127.0286),
  '용인': (37.2411, 127.1776),
  '성남': (37.4200, 127.1267),
  '고양': (37.6584, 126.8320),
  '화성': (37.1996, 126.8314),
  '부천': (37.5035, 126.7660),
  '안산': (37.3219, 126.8309),
  '안양': (37.3943, 126.9568),
  '남양주': (37.6360, 127.2165),
  '평택': (36.9921, 127.1127),
  '의정부': (37.7380, 127.0337),
  '파주': (37.7599, 126.7799),
  '시흥': (37.3800, 126.8030),
  '김포': (37.6150, 126.7158),
  '광명': (37.4786, 126.8646),
  '군포': (37.3617, 126.9350),
  '하남': (37.5392, 127.2148),
  '오산': (37.1499, 127.0775),
  '양주': (37.7852, 127.0458),
  '이천': (37.2721, 127.4349),
  '구리': (37.5943, 127.1296),
  '안성': (37.0080, 127.2797),
  '포천': (37.8949, 127.2003),
  '의왕': (37.3446, 126.9683),
  '양평': (37.4917, 127.4875),
  '여주': (37.2983, 127.6370),
  '동두천': (37.9036, 127.0606),
  '과천': (37.4292, 126.9876),
  '가평': (37.8315, 127.5096),
  '연천': (38.0966, 127.0749),
  // 도 주요 도시
  '춘천': (37.8813, 127.7298),
  '원주': (37.3422, 127.9202),
  '강릉': (37.7519, 128.8761),
  '청주': (36.6424, 127.4890),
  '천안': (36.8151, 127.1139),
  '충주': (36.9910, 127.9259),
  '전주': (35.8242, 127.1480),
  '목포': (34.8118, 126.3922),
  '여수': (34.7604, 127.6622),
  '순천': (34.9506, 127.4872),
  '포항': (36.0190, 129.3435),
  '안동': (36.5684, 128.7294),
  '구미': (36.1196, 128.3446),
  '경주': (35.8562, 129.2247),
  '창원': (35.2279, 128.6811),
  '김해': (35.2285, 128.8894),
  '진주': (35.1800, 128.1076),
  '양산': (35.3350, 129.0378),
  '제주': (33.4996, 126.5312),
  '서귀포': (33.2542, 126.5600),
};

/// 지역명 글자에서 기준 좌표를 찾는다. '경기'가 있으면 경기 광주를 우선한다.
({double lat, double lng})? referenceFor(String locality) {
  final text = locality.replaceAll(' ', '');
  if (text.contains('광주') &&
      (text.contains('경기') || text.contains('광주시'))) {
    return (lat: 37.4292, lng: 127.2550); // 경기도 광주시
  }
  // 긴 이름부터 맞춰 '남양주' 같은 걸 '양주'보다 먼저 잡는다.
  final keys = _koreaPlaces.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    if (text.contains(k)) {
      final v = _koreaPlaces[k]!;
      return (lat: v.$1, lng: v.$2);
    }
  }
  return null;
}

final _plusToken = RegExp('[$_alphabet$_pad]{2,8}\\+[$_alphabet]*', caseSensitive: false);

/// 위치 입력을 해석한다. 소수점 좌표 또는 플러스 코드(전체/짧은) 모두 받는다.
LocationResult parseLocation(String input) {
  final s = input.trim();
  if (s.isEmpty) {
    return const LocationResult.fail('위치를 입력해 주세요');
  }

  // 1) 플러스 코드가 들어 있으면 먼저 처리
  final m = _plusToken.firstMatch(s);
  if (s.contains('+') && m != null) {
    final code = m.group(0)!.toUpperCase();
    final before = code.indexOf('+');
    final locality = (s.substring(0, m.start) + s.substring(m.end)).trim();
    if (before == 8) {
      // 전체 코드
      final r = decodeOlc(code);
      return LocationResult.ok(r.lat, r.lng);
    }
    // 짧은 코드 → 지역명으로 기준 찾기
    final ref = referenceFor(locality);
    if (ref == null) {
      return const LocationResult.fail(
          '짧은 플러스코드는 지역 이름이 필요해요. 예: "75W2+4PV 용인"처럼 도시 이름을 함께 적거나, '
          '구글 지도에서 소수점 좌표(예: 37.2954, 127.1518)를 복사해 넣어 주세요.');
    }
    final r = recoverNearest(code, ref.lat, ref.lng);
    return LocationResult.ok(r.lat, r.lng);
  }

  // 2) 소수점 좌표 (쉼표·공백·슬래시 구분)
  final nums = RegExp(r'[-+]?\d+(?:\.\d+)?')
      .allMatches(s)
      .map((e) => double.parse(e.group(0)!))
      .toList();
  if (nums.length >= 2) {
    final lat = nums[0];
    final lng = nums[1];
    if (lat.abs() <= 90 && lng.abs() <= 180) {
      return LocationResult.ok(lat, lng);
    }
    return const LocationResult.fail('위도는 -90~90, 경도는 -180~180 범위여야 해요');
  }

  return const LocationResult.fail(
      '위치를 알아볼 수 없어요. 소수점 좌표(예: 37.2954, 127.1518) 또는 '
      '플러스코드(예: 75W2+4PV 용인)를 입력해 주세요.');
}
