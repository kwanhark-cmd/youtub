import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:metaclean/src/exif_utils.dart';
import 'package:metaclean/src/photo_edit.dart';

/// 카메라 정보·옛 날짜·옛 위치가 든 JPEG에 XMP 조각과 숨은 꼬리 데이터를 붙인다.
Uint8List _sampleJpeg() {
  final im = img.Image(width: 16, height: 16);
  for (final p in im) {
    p
      ..r = p.x * 16
      ..g = p.y * 16
      ..b = 128;
  }
  im.exif.imageIfd['Make'] = 'SAMSUNG';
  im.exif.imageIfd['Model'] = 'SM-S918N';
  im.exif.imageIfd['DateTime'] = '2024:03:05 10:11:12';
  im.exif.exifIfd['DateTimeOriginal'] = '2024:03:05 10:11:12';
  im.exif.exifIfd['DateTimeDigitized'] = '2024:03:05 10:11:12';
  writeGps(im.exif, 35.1796, 129.0756); // 부산
  im.exif.gpsIfd.data[0x001D] = img.IfdValueAscii('2024:03:05');
  final jpg = img.encodeJpg(im, quality: 90);

  // SOI 바로 뒤에 XMP APP1 조각 끼워 넣기 + 끝에 숨은 데이터
  final xmp = 'http://ns.adobe.com/xap/1.0/\u0000<x>SECRETXMP 2024-03-05</x>'.codeUnits;
  final len = xmp.length + 2;
  final out = BytesBuilder()
    ..add(jpg.sublist(0, 2))
    ..add([0xFF, 0xE1, len >> 8, len & 0xFF, ...xmp])
    ..add(jpg.sublist(2))
    ..add('HIDDENMOTIONVIDEO'.codeUnits);
  return out.toBytes();
}

int _sosIndex(Uint8List b) {
  var i = 2;
  while (i + 3 < b.length) {
    if (b[i] == 0xFF && b[i + 1] == 0xDA) return i;
    i += 2 + ((b[i + 2] << 8) | b[i + 3]);
  }
  return -1;
}

bool _has(Uint8List hay, String needle) =>
    String.fromCharCodes(hay).contains(needle);

double _deg(IfdTag t) {
  final r = t.values.toList().cast<Ratio>();
  return r[0].toDouble() + r[1].toDouble() / 60 + r[2].toDouble() / 3600;
}

void main() {
  test('날짜와 위치만 바꾸고 나머지 EXIF와 화질은 그대로 둔다', () async {
    final src = _sampleJpeg();
    final r = editPhotoMeta(
      src,
      date: DateTime(2026, 11, 10, 9, 30),
      gps: GpsAction.change,
      lat: 37.5665,
      lng: 126.978,
    )!;
    expect(r.reEncoded, isFalse);

    final tags = await readExifFromBytes(r.bytes);
    expect(tags['Image Make']!.printable, 'SAMSUNG');
    expect(tags['Image Model']!.printable, 'SM-S918N');
    expect(tags['Image DateTime']!.printable, '2026:11:10 09:30:00');
    expect(tags['EXIF DateTimeOriginal']!.printable, '2026:11:10 09:30:00');
    expect(tags['EXIF DateTimeDigitized']!.printable, '2026:11:10 09:30:00');
    expect(tags['GPS GPSLatitudeRef']!.printable, 'N');
    expect(_deg(tags['GPS GPSLatitude']!), closeTo(37.5665, 1e-4));
    expect(_deg(tags['GPS GPSLongitude']!), closeTo(126.978, 1e-4));
    expect(tags.containsKey('GPS GPSDate'), isFalse);

    // 옛 날짜·XMP·숨은 꼬리 데이터가 남지 않는다
    expect(_has(r.bytes, '2024:03:05'), isFalse);
    expect(_has(r.bytes, 'SECRETXMP'), isFalse);
    expect(_has(r.bytes, 'HIDDENMOTIONVIDEO'), isFalse);

    // 압축된 그림 데이터는 원본과 한 바이트도 다르지 않다 (무손실)
    final a = src.sublist(_sosIndex(src), src.length - 'HIDDENMOTIONVIDEO'.length);
    final b = r.bytes.sublist(_sosIndex(r.bytes));
    expect(b, a);
  });

  test('위치만 지우고 날짜는 그대로 둔다', () async {
    final r = editPhotoMeta(_sampleJpeg(), gps: GpsAction.remove)!;
    final tags = await readExifFromBytes(r.bytes);
    expect(tags.keys.where((k) => k.startsWith('GPS')), isEmpty);
    expect(tags['EXIF DateTimeOriginal']!.printable, '2024:03:05 10:11:12');
    expect(tags['Image Make']!.printable, 'SAMSUNG');
  });

  test('날짜만 바꾸면 위치는 그대로다', () async {
    final r = editPhotoMeta(_sampleJpeg(), date: DateTime(2025, 1, 2, 3, 4, 5))!;
    final tags = await readExifFromBytes(r.bytes);
    expect(tags['EXIF DateTimeOriginal']!.printable, '2025:01:02 03:04:05');
    expect(_deg(tags['GPS GPSLatitude']!), closeTo(35.1796, 1e-4));
  });

  test('EXIF가 없는 PNG는 JPEG로 바꿔서 새긴다', () async {
    final png = img.encodePng(img.Image(width: 8, height: 8));
    final r = editPhotoMeta(Uint8List.fromList(png),
        date: DateTime(2026, 1, 1), gps: GpsAction.change, lat: -33.8688, lng: 151.2093)!;
    expect(r.reEncoded, isTrue);
    final tags = await readExifFromBytes(r.bytes);
    expect(tags['EXIF DateTimeOriginal']!.printable, '2026:01:01 00:00:00');
    expect(tags['GPS GPSLatitudeRef']!.printable, 'S');
  });

  test('촬영 기기만 바꾼다: 날짜·위치는 그대로', () async {
    final r = editPhotoMeta(_sampleJpeg(),
        device: DeviceAction.change, make: 'Apple', model: 'iPhone 15')!;
    final tags = await readExifFromBytes(r.bytes);
    expect(tags['Image Make']!.printable, 'Apple');
    expect(tags['Image Model']!.printable, 'iPhone 15');
    expect(tags['EXIF DateTimeOriginal']!.printable, '2024:03:05 10:11:12');
    expect(_deg(tags['GPS GPSLatitude']!), closeTo(35.1796, 1e-4));
    expect(_has(r.bytes, 'SM-S918N'), isFalse);
    expect(_has(r.bytes, 'SAMSUNG'), isFalse);
  });

  test('촬영 기기 정보만 지운다', () async {
    final r = editPhotoMeta(_sampleJpeg(), device: DeviceAction.remove)!;
    final tags = await readExifFromBytes(r.bytes);
    expect(tags.containsKey('Image Make'), isFalse);
    expect(tags.containsKey('Image Model'), isFalse);
    expect(tags['EXIF DateTimeOriginal']!.printable, '2024:03:05 10:11:12');
    expect(_has(r.bytes, 'SM-S918N'), isFalse);
  });

  test('위치를 바꾸라면서 좌표가 없으면 오류', () {
    expect(() => editPhotoMeta(_sampleJpeg(), gps: GpsAction.change),
        throwsArgumentError);
  });
}
