import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:metaclean/src/exif_utils.dart';
import 'package:metaclean/src/strip.dart';

Uint8List _seg(int marker, List<int> payload) {
  final len = payload.length + 2;
  return Uint8List.fromList(
      [0xFF, marker, (len >> 8) & 0xFF, len & 0xFF, ...payload]);
}

void main() {
  group('JPEG 메타데이터 제거', () {
    test('APP1(EXIF)·COM은 지우고 APP0·DQT·압축 데이터는 남긴다', () {
      final jpeg = BytesBuilder()
        ..add([0xFF, 0xD8]) // SOI
        ..add(_seg(0xE0, [0x4A, 0x46, 0x49, 0x46, 0x00])) // APP0 JFIF
        ..add(_seg(0xE1, List.filled(30, 0x11))) // APP1 EXIF
        ..add(_seg(0xFE, [0x41, 0x42])) // COM 주석
        ..add(_seg(0xDB, List.filled(10, 0x22))) // DQT
        ..add(_seg(0xDA, [0x01, 0x02])) // SOS 헤더
        ..add([0x33, 0xFF, 0x00, 0x44]) // 압축 데이터 (FF00 이스케이프 포함)
        ..add([0xFF, 0xD9]); // EOI
      final src = jpeg.toBytes();

      final r = stripMetadata(src)!;
      expect(r.format, 'jpeg');
      expect(r.removedSegments, 2);
      expect(r.trailingDataRemoved, isFalse);
      // APP1 내용(0x11 연속)이 사라졌다
      expect(_contains(r.bytes, List.filled(30, 0x11)), isFalse);
      // DQT 내용은 남아 있다
      expect(_contains(r.bytes, List.filled(10, 0x22)), isTrue);
      // 압축 데이터와 EOI가 그대로다
      expect(_contains(r.bytes, [0x33, 0xFF, 0x00, 0x44, 0xFF, 0xD9]), isTrue);
    });

    test('EOI 뒤에 붙은 숨은 데이터(모션 포토)를 잘라낸다', () {
      final jpeg = BytesBuilder()
        ..add([0xFF, 0xD8])
        ..add(_seg(0xDB, [0x01]))
        ..add(_seg(0xDA, [0x01]))
        ..add([0x10, 0x20])
        ..add([0xFF, 0xD9])
        ..add(List.filled(100, 0x77)); // 숨은 동영상 흉내
      final r = stripMetadata(jpeg.toBytes())!;
      expect(r.trailingDataRemoved, isTrue);
      expect(r.bytes.sublist(r.bytes.length - 2), [0xFF, 0xD9]);
      expect(_contains(r.bytes, List.filled(100, 0x77)), isFalse);
    });

    test('JPEG가 아니면 PNG로 시도하고, 둘 다 아니면 null', () {
      expect(stripMetadata(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
    });
  });

  group('PNG 메타데이터 제거', () {
    Uint8List chunk(String type, List<int> data) {
      final t = type.codeUnits;
      final len = data.length;
      return Uint8List.fromList([
        (len >> 24) & 0xFF, (len >> 16) & 0xFF, (len >> 8) & 0xFF, len & 0xFF,
        ...t, ...data, 0, 0, 0, 0, // CRC는 검사하지 않음
      ]);
    }

    test('tEXt·eXIf는 지우고 IHDR·IDAT·IEND는 남긴다', () {
      const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      final png = BytesBuilder()
        ..add(sig)
        ..add(chunk('IHDR', List.filled(13, 1)))
        ..add(chunk('tEXt', [0x61, 0x62, 0x63]))
        ..add(chunk('eXIf', List.filled(8, 9)))
        ..add(chunk('IDAT', [5, 6, 7]))
        ..add(chunk('IEND', []));
      final r = stripMetadata(png.toBytes())!;
      expect(r.format, 'png');
      expect(r.removedSegments, 2);
      expect(_contains(r.bytes, 'tEXt'.codeUnits), isFalse);
      expect(_contains(r.bytes, 'eXIf'.codeUnits), isFalse);
      expect(_contains(r.bytes, 'IDAT'.codeUnits), isTrue);
    });
  });

  group('EXIF 기록 도우미', () {
    test('기록 설명을 만든다', () {
      expect(
        buildDescription(itemName: '아이폰 13', memo: '당근 50만원', place: '강남역'),
        '물건: 아이폰 13 | 메모: 당근 50만원 | 장소: 강남역',
      );
    });

    test('사진에 날짜·설명·GPS를 새기면 JPEG 저장 후에도 읽힌다', () {
      final im = img.Image(width: 8, height: 8);
      final gpsOk = applyStamp(
        im,
        date: DateTime(2026, 11, 10, 14, 30),
        itemName: 'iPhone 13',
        memo: 'Danggeun 500000',
        lat: 37.5665,
        lng: 126.978,
      );
      expect(gpsOk, isTrue);
      final bytes = img.encodeJpg(im, quality: 90);
      final back = img.decodeJpg(Uint8List.fromList(bytes))!;
      expect(back.exif.imageIfd['DateTime'].toString(),
          contains('2026:11:10 14:30:00'));
      expect(back.exif.imageIfd['ImageDescription'].toString(),
          contains('iPhone 13'));
      expect(back.exif.exifIfd['DateTimeOriginal'].toString(),
          contains('2026:11:10 14:30:00'));
      expect(back.exif.gpsIfd['GPSLatitudeRef'].toString(), contains('N'));
      expect(back.exif.gpsIfd['GPSLatitude']!.length, 3);
    });

    test('파일 이름을 안전하게 만든다', () {
      expect(safeFileName('아이폰 13 / 중고?'), '아이폰_13_중고');
    });
  });
}

bool _contains(Uint8List haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
