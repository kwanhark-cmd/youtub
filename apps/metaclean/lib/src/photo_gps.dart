import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 사진 속 위치(GPS) 정보의 상태.
enum GpsState {
  /// 위치 칸이 아예 없다 (또는 빈 칸 묶음만 있다).
  none,

  /// 쓸 수 있는 좌표가 들어 있다.
  valid,

  /// 위치 칸은 있는데 좌표가 비었거나 망가졌다.
  ///
  /// 안드로이드는 '사진 위치 정보 접근' 허락이 없는 앱에 사진을 넘길 때 위치 칸의
  /// 값만 0으로 덮어서 넘긴다. 그러면 위치 칸은 남아 있지만 방향(N/S·E/W)은 비고
  /// 좌표는 0/0 같은 값이 된다. 위도·경도 칸이 아예 없는 경우도 여기에 넣는다.
  blank,
}

/// EXIF 묶음 안의 위치 정보 상태를 알아본다. (아무것도 바꾸지 않는다)
GpsState gpsStateOfExif(img.ExifData exif) {
  // gpsIfd 를 그냥 읽으면 빈 묶음이 새로 생기므로 있는지 먼저 본다.
  if (!exif.imageIfd.sub.containsKey('gps')) return GpsState.none;
  final g = exif.gpsIfd;
  if (g.data.isEmpty) return GpsState.none;
  final lat = _coord(g.data[0x0002], g.data[0x0001], 'N', 'S', 90);
  final lng = _coord(g.data[0x0004], g.data[0x0003], 'E', 'W', 180);
  if (lat == null || lng == null) return GpsState.blank;
  // 정확히 (0, 0) 은 바다 한가운데다. 값을 0으로 덮은 자리표시로 본다.
  if (lat == 0 && lng == 0) return GpsState.blank;
  return GpsState.valid;
}

/// 사진 파일(바이트)의 위치 정보 상태. 읽을 수 없는 형식이면 [GpsState.none].
GpsState gpsStateOfBytes(Uint8List bytes) {
  try {
    final isJpeg = bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    final exif =
        isJpeg ? img.decodeJpgExif(bytes) : img.decodeImage(bytes)?.exif;
    if (exif == null) return GpsState.none;
    return gpsStateOfExif(exif);
  } catch (_) {
    return GpsState.none;
  }
}

/// 망가진(비어 있는) 위치 칸 묶음을 깨끗이 떼어 낸다. 떼어 냈으면 참.
///
/// 좌표가 제대로 든 위치 정보는 건드리지 않는다.
bool dropBrokenGps(img.ExifData exif) {
  if (!exif.imageIfd.sub.containsKey('gps')) return false;
  if (gpsStateOfExif(exif) == GpsState.valid) return false;
  exif.imageIfd.sub.directories.remove('gps');
  exif.imageIfd.data.remove(0x8825); // GPS 묶음 포인터
  return true;
}

/// 도/분/초 분수와 방향 글자로 좌표 하나를 읽는다. 망가졌으면 null.
double? _coord(
    img.IfdValue? v, img.IfdValue? ref, String plus, String minus, double max) {
  if (v == null || ref == null) return null;
  final parts = v is img.IfdValueRational
      ? v.value
      : v is img.IfdValueSRational
          ? v.value
          : null;
  if (parts == null || parts.isEmpty || parts.length > 3) return null;
  var deg = 0.0;
  var scale = 1.0;
  for (final r in parts) {
    if (r.denominator == 0) return null; // 0으로 나누기 = 덮어쓴 값
    final d = r.numerator / r.denominator;
    if (!d.isFinite || d < 0) return null;
    deg += d / scale;
    scale *= 60;
  }
  if (!deg.isFinite || deg > max) return null;
  final dir = _refLetter(ref);
  if (dir == plus) return deg;
  if (dir == minus) return -deg;
  return null; // 방향 글자가 비었다
}

String _refLetter(img.IfdValue ref) {
  final String s;
  if (ref is img.IfdValueAscii) {
    s = ref.value;
  } else {
    s = String.fromCharCodes(ref.toData());
  }
  return s.replaceAll('\u0000', '').trim().toUpperCase();
}
