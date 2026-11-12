import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

/// EXIF 날짜 형식 (yyyy:MM:dd HH:mm:ss).
String exifDate(DateTime t) => DateFormat('yyyy:MM:dd HH:mm:ss').format(t);

/// 십진수 좌표를 EXIF 표준인 도/분/초 분수 3개로 바꾼다.
img.IfdValueRational dmsValue(double decimal) {
  final abs = decimal.abs();
  final deg = abs.floor();
  final minFull = (abs - deg) * 60;
  final min = minFull.floor();
  final secTimes1e4 = ((minFull - min) * 60 * 10000).round();
  final v = img.IfdValueRational(deg, 1);
  v.value.addAll(img.IfdValueRational(min, 1).value);
  v.value.addAll(img.IfdValueRational(secTimes1e4, 10000).value);
  return v;
}

/// GPS 칸을 비우고 새 좌표만 적는다.
void writeGps(img.ExifData exif, double lat, double lng) {
  final gps = exif.gpsIfd;
  gps.data.clear();
  gps.data[0x0000] = img.IfdByteValue.list(Uint8List.fromList(const [2, 3, 0, 0])); // GPSVersionID
  gps.data[0x0001] = img.IfdValueAscii(lat >= 0 ? 'N' : 'S');
  gps.data[0x0002] = dmsValue(lat);
  gps.data[0x0003] = img.IfdValueAscii(lng >= 0 ? 'E' : 'W');
  gps.data[0x0004] = dmsValue(lng);
}

/// GPS 정보를 통째로 없앤다.
void removeGps(img.ExifData exif) {
  final ifd0 = exif.imageIfd;
  ifd0.sub.directories.remove('gps');
  ifd0.data.remove(0x8825); // GPS IFD 포인터
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

/// 날짜를 새로 적을 때, 옛 촬영 시각이 따로 남는 칸을 지운다.
///
/// 초 아래 자리(SubSecTime)와 GPS 시각·날짜는 원래 촬영 순간의 값이라,
/// 날짜만 새로 적으면 새 날짜 옆에 옛 시각이 그대로 남는다.
void clearOldTimeTraces(img.ExifData exif) {
  if (exif.imageIfd.sub.containsKey('exif')) {
    for (final t in const [0x9290, 0x9291, 0x9292]) {
      exif.exifIfd.data.remove(t); // SubSecTime 3종
    }
  }
  if (exif.imageIfd.sub.containsKey('gps')) {
    exif.gpsIfd.data.remove(0x0007); // GPSTimeStamp
    exif.gpsIfd.data.remove(0x001D); // GPSDateStamp
  }
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
  clearOldTimeTraces(exif);
  var gpsOk = false;
  if (lat != null && lng != null) {
    try {
      writeGps(exif, lat, lng);
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
