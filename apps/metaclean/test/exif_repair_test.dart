import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:metaclean/src/exif_repair.dart';
import 'package:metaclean/src/photo_edit.dart';
import 'package:metaclean/src/photo_gps.dart';

/// JPEG 에서 EXIF 본문(TIFF)을 꺼낸다.
Uint8List tiffOf(Uint8List j) {
  var i = 2;
  while (true) {
    final len = (j[i + 2] << 8) | j[i + 3];
    if (j[i + 1] == 0xE1 && j[i + 4] == 0x45) {
      return Uint8List.sublistView(j, i + 10, i + 2 + len);
    }
    i += 2 + len;
  }
}

/// 모든 묶음을 따라가며 (묶음 이름 → 다음 묶음 주소) 를 모은다.
Map<String, int> nextPointers(Uint8List t) {
  final bd = ByteData.sublistView(t);
  final out = <String, int>{};
  void walk(int off, String name) {
    final n = bd.getUint16(off);
    for (var k = 0; k < n; k++) {
      final p = off + 2 + 12 * k;
      final tag = bd.getUint16(p);
      final type = bd.getUint16(p + 2);
      final count = bd.getUint32(p + 4);
      final size = const {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8}[type]! * count;
      if (size > 4) {
        final vo = bd.getUint32(p + 8);
        expect(vo.isEven, isTrue, reason: '$name ${tag.toRadixString(16)} 값 주소가 홀수');
        expect(vo + size <= t.length, isTrue);
      }
      if (tag == 0x8769) walk(bd.getUint32(p + 8), 'exif');
      if (tag == 0x8825) walk(bd.getUint32(p + 8), 'gps');
    }
    out[name] = bd.getUint32(off + 2 + 12 * n);
  }

  walk(bd.getUint32(4), 'ifd0');
  return out;
}

void main() {
  Uint8List sample() {
    final im = img.Image(width: 8, height: 8);
    return Uint8List.fromList(img.encodeJpg(im));
  }

  test('세부·위치 묶음 끝에 "다음 묶음 없음" 표시가 들어간다', () {
    final a = editPhotoMeta(sample(),
        gps: GpsAction.change, lat: 37.2756, lng: 127.1512)!;
    final b = editPhotoMeta(a.bytes,
        dateAction: DateAction.change,
        date: DateTime(2020, 11, 19, 1, 11),
        gps: GpsAction.keep)!;
    for (final bytes in [a.bytes, b.bytes]) {
      final next = nextPointers(tiffOf(bytes));
      expect(next['gps'], 0);
      expect(next['ifd0'], 0);
    }
    expect(nextPointers(tiffOf(b.bytes))['exif'], 0);
    // 값은 그대로다.
    final p = gpsLatLngOfBytes(b.bytes)!;
    expect(p.lat, closeTo(37.2756, 1e-4));
    expect(p.lng, closeTo(127.1512, 1e-4));
    final exif = img.decodeJpgExif(b.bytes)!;
    expect(exif.exifIfd['DateTimeOriginal'].toString(), '2020:11:19 01:11:00');
  });

  test('고친 것을 다시 고쳐도 같다 · EXIF 없는 사진은 그대로', () {
    final a = editPhotoMeta(sample(),
        gps: GpsAction.change, lat: -33.5, lng: -70.25)!;
    expect(repairJpegExif(a.bytes), a.bytes);
    final plain = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);
    expect(repairJpegExif(plain), plain);
    expect(rebuildTiff(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
