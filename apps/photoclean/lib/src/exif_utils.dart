import 'package:intl/intl.dart';

/// EXIF 날짜 형식 (yyyy:MM:dd HH:mm:ss).
String exifDate(DateTime t) => DateFormat('yyyy:MM:dd HH:mm:ss').format(t);

/// 십진수 좌표를 EXIF 도/분/초 분수 형식으로 바꾼다.
/// 예) 37.5665 -> "37/1,33/1,594000/10000"
String toDmsRational(double decimal) {
  final abs = decimal.abs();
  final deg = abs.floor();
  final minFull = (abs - deg) * 60;
  final min = minFull.floor();
  final secTimes1e4 = ((minFull - min) * 60 * 10000).round();
  return '$deg/1,$min/1,$secTimes1e4/10000';
}

/// 기록용 EXIF 속성 묶음을 만든다.
Map<String, Object> buildStampAttributes({
  required DateTime date,
  required String itemName,
  String memo = '',
  String place = '',
  double? lat,
  double? lng,
}) {
  final parts = <String>[
    '물건: $itemName',
    if (memo.trim().isNotEmpty) '메모: ${memo.trim()}',
    if (place.trim().isNotEmpty) '장소: ${place.trim()}',
  ];
  final desc = parts.join(' | ');
  final d = exifDate(date);
  final attrs = <String, Object>{
    'DateTimeOriginal': d,
    'DateTimeDigitized': d,
    'DateTime': d,
    'ImageDescription': desc,
    'UserComment': desc,
  };
  if (lat != null && lng != null) {
    attrs['GPSLatitude'] = toDmsRational(lat);
    attrs['GPSLatitudeRef'] = lat >= 0 ? 'N' : 'S';
    attrs['GPSLongitude'] = toDmsRational(lng);
    attrs['GPSLongitudeRef'] = lng >= 0 ? 'E' : 'W';
  }
  return attrs;
}

/// 파일 이름에 쓸 수 없는 글자를 제거한다.
String safeFileName(String s) =>
    s.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
