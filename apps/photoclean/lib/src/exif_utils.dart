import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

/// EXIF 날짜 형식 (yyyy:MM:dd HH:mm:ss).
String exifDate(DateTime t) => DateFormat('yyyy:MM:dd HH:mm:ss').format(t);

/// 십진수 좌표를 EXIF 도/분/초 분수 목록으로 바꾼다.
List<img.Rational> dmsRationals(double decimal) {
  final abs = decimal.abs();
  final deg = abs.floor();
  final minFull = (abs - deg) * 60;
  final min = minFull.floor();
  final secTimes1e4 = ((minFull - min) * 60 * 10000).round();
  return [
    img.Rational(deg, 1),
    img.Rational(min, 1),
    img.Rational(secTimes1e4, 10000),
  ];
}

/// 기록 설명 한 줄을 만든다.
String buildDescription({
  required String itemName,
  String memo = '',
  String place = '',
}) {
  final parts = <String>[
    '물건: ${itemName.trim()}',
    if (memo.trim().isNotEmpty) '메모: ${memo.trim()}',
    if (place.trim().isNotEmpty) '장소: ${place.trim()}',
  ];
  return parts.join(' | ');
}

/// 사진에 날짜·설명·좌표 메타데이터를 새긴다. GPS 기록 성공 여부를 돌려준다.
bool applyStamp(
  img.Image image, {
  required DateTime date,
  required String itemName,
  String memo = '',
  String place = '',
  double? lat,
  double? lng,
}) {
  final d = exifDate(date);
  final desc = buildDescription(itemName: itemName, memo: memo, place: place);
  final exif = image.exif;
  exif.imageIfd['DateTime'] = d;
  exif.imageIfd['ImageDescription'] = desc;
  exif.exifIfd['DateTimeOriginal'] = d;
  exif.exifIfd['DateTimeDigitized'] = d;
  var gpsOk = false;
  if (lat != null && lng != null) {
    try {
      final gps = exif.gpsIfd;
      gps['GPSLatitudeRef'] = lat >= 0 ? 'N' : 'S';
      gps['GPSLatitude'] = img.IfdValueRational.list(dmsRationals(lat));
      gps['GPSLongitudeRef'] = lng >= 0 ? 'E' : 'W';
      gps['GPSLongitude'] = img.IfdValueRational.list(dmsRationals(lng));
      gpsOk = true;
    } catch (_) {
      gpsOk = false;
    }
  }
  return gpsOk;
}

/// 파일 이름에 쓸 수 없는 글자를 제거한다.
String safeFileName(String s) =>
    s.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
