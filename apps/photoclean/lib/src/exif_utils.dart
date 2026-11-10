import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

/// EXIF 날짜 형식 (yyyy:MM:dd HH:mm:ss).
String exifDate(DateTime t) => DateFormat('yyyy:MM:dd HH:mm:ss').format(t);

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
      exif.gpsIfd.setGpsLocation(latitude: lat, longitude: lng);
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
