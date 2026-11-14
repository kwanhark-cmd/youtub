import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:metaclean/src/exif_utils.dart';
import 'package:metaclean/src/photo_edit.dart';
import 'package:metaclean/src/photo_gps.dart';

img.Image _base() {
  final im = img.Image(width: 8, height: 8);
  for (final p in im) {
    p
      ..r = p.x * 30
      ..g = p.y * 30
      ..b = 100;
  }
  im.exif.imageIfd['Make'] = 'samsung';
  im.exif.imageIfd['Model'] = 'SM-S918N';
  im.exif.imageIfd['DateTime'] = '2026:10:01 12:00:00';
  im.exif.exifIfd['DateTimeOriginal'] = '2026:10:01 12:00:00';
  return im;
}

img.IfdValueRational _dms(List<List<int>> parts) {
  final v = img.IfdValueRational(parts[0][0], parts[0][1]);
  for (final p in parts.skip(1)) {
    v.value.addAll(img.IfdValueRational(p[0], p[1]).value);
  }
  return v;
}

/// 안드로이드가 위치를 가려서 넘겨준 모양: 위치 칸은 그대로인데 값이 0으로 덮였다.
/// (방향 글자는 빈 글자, 도/분/초는 0/0)
void _redact(img.ExifData exif, {img.IfdValue? ref}) {
  final g = exif.gpsIfd;
  g.data.clear();
  g.data[0x0000] = img.IfdByteValue.list(Uint8List.fromList(const [0, 0, 0, 0]));
  g.data[0x0001] = ref ?? img.IfdValueAscii.list(const [0]);
  g.data[0x0002] = _dms(const [[0, 0], [0, 0], [0, 0]]);
  g.data[0x0003] = ref ?? img.IfdValueAscii.list(const [0]);
  g.data[0x0004] = _dms(const [[0, 0], [0, 0], [0, 0]]);
  g.data[0x0007] = _dms(const [[0, 0], [0, 0], [0, 0]]); // GPSTimeStamp
  g.data[0x001D] = img.IfdValueAscii.list(List.filled(10, 0)); // GPSDateStamp
}

Uint8List _jpg(void Function(img.ExifData exif) edit) {
  final im = _base();
  edit(im.exif);
  return img.encodeJpg(im, quality: 90);
}

Uint8List get _redactedJpeg => _jpg(_redact);
Uint8List get _validJpeg => _jpg((e) => writeGps(e, 37.2411, 127.1776)); // 용인

bool _hasGpsIfd(Uint8List b) =>
    img.decodeJpgExif(b)!.imageIfd.sub.containsKey('gps');

void main() {
  group('gpsStateOfBytes: 받은 사진의 위치 상태를 가려낸다', () {
    test('제대로 된 좌표는 valid', () {
      expect(gpsStateOfBytes(_validJpeg), GpsState.valid);
    });

    test('위치 칸이 없으면 none', () {
      expect(gpsStateOfBytes(_jpg((_) {})), GpsState.none);
    });

    test('안드로이드가 가린 모양(빈 방향 글자 + 0/0 분수)은 blank', () {
      expect(gpsStateOfBytes(_redactedJpeg), GpsState.blank);
    });

    test('방향 글자가 길이 0인 빈 글자여도 blank', () {
      expect(gpsStateOfBytes(_jpg((e) => _redact(e, ref: img.IfdValueAscii('')))),
          GpsState.blank);
    });

    test('좌표는 멀쩡해도 방향 글자가 비어 있으면 blank', () {
      final b = _jpg((e) {
        writeGps(e, 37.2411, 127.1776);
        e.gpsIfd.data[0x0001] = img.IfdValueAscii.list(const [0]);
      });
      expect(gpsStateOfBytes(b), GpsState.blank);
    });

    test('분모가 0인 칸이 하나라도 있으면 blank', () {
      final b = _jpg((e) {
        writeGps(e, 37.2411, 127.1776);
        e.gpsIfd.data[0x0004] = _dms(const [[127, 1], [10, 0], [39, 1]]);
      });
      expect(gpsStateOfBytes(b), GpsState.blank);
    });

    test('위치 칸은 있는데 위도·경도가 아예 없으면 blank', () {
      final b = _jpg((e) {
        e.gpsIfd.data[0x0000] =
            img.IfdByteValue.list(Uint8List.fromList(const [2, 3, 0, 0]));
        e.gpsIfd.data[0x001D] = img.IfdValueAscii('2026:10:01');
      });
      expect(gpsStateOfBytes(b), GpsState.blank);
    });

    test('범위를 벗어난 위도(95도)와 정확히 (0, 0)은 blank', () {
      expect(
          gpsStateOfBytes(_jpg((e) {
            writeGps(e, 37.2, 127.1);
            e.gpsIfd.data[0x0002] = _dms(const [[95, 1], [0, 1], [0, 1]]);
          })),
          GpsState.blank);
      expect(gpsStateOfBytes(_jpg((e) => writeGps(e, 0, 0))), GpsState.blank);
    });

    test('남반구·서반구 좌표도 valid', () {
      expect(gpsStateOfBytes(_jpg((e) => writeGps(e, -33.86, -70.65))),
          GpsState.valid);
    });

    test('사진이 아닌 바이트는 none (오류 없이)', () {
      expect(gpsStateOfBytes(Uint8List.fromList([1, 2, 3])), GpsState.none);
    });
  });

  group('dropBrokenGps', () {
    test('가려진 위치 칸만 떼고, 좋은 위치는 그대로 둔다', () {
      final bad = img.decodeJpgExif(_redactedJpeg)!;
      expect(dropBrokenGps(bad), isTrue);
      expect(bad.imageIfd.sub.containsKey('gps'), isFalse);
      expect(bad.imageIfd.data.containsKey(0x8825), isFalse);

      final good = img.decodeJpgExif(_validJpeg)!;
      expect(dropBrokenGps(good), isFalse);
      expect(gpsStateOfExif(good), GpsState.valid);
    });
  });

  group('사진 수정: 위치 "그대로"', () {
    test('가려진 위치는 결과에 망가진 채 넣지 않고 깨끗이 뺀다', () async {
      final r = editPhotoMeta(
        _redactedJpeg,
        dateAction: DateAction.change,
        date: DateTime(2020, 5, 1, 8, 0),
      )!;
      expect(r.sourceGps, GpsState.blank);
      expect(_hasGpsIfd(r.bytes), isFalse);
      expect(gpsStateOfBytes(r.bytes), GpsState.none);
      final tags = await readExifFromBytes(r.bytes);
      expect(tags.keys.where((k) => k.startsWith('GPS')), isEmpty);
      // 나머지 정보와 바꾼 날짜는 그대로
      expect(tags['Image Model']!.printable, 'SM-S918N');
      expect(tags['EXIF DateTimeOriginal']!.printable, '2020:05:01 08:00:00');
    });

    test('제대로 된 위치는 "그대로" 남는다', () {
      final r = editPhotoMeta(
        _validJpeg,
        dateAction: DateAction.change,
        date: DateTime(2020, 5, 1, 8, 0),
      )!;
      expect(r.sourceGps, GpsState.valid);
      expect(gpsStateOfBytes(r.bytes), GpsState.valid);
    });

    test('가려진 사진이라도 "바꾸기"면 새 좌표가 제대로 들어간다', () {
      final r = editPhotoMeta(
        _redactedJpeg,
        gps: GpsAction.change,
        lat: 37.2411,
        lng: 127.1776,
      )!;
      expect(gpsStateOfBytes(r.bytes), GpsState.valid);
    });
  });

  test('구매 기록: 새 좌표 없이 새기면 가려진 위치 칸을 떼어 낸다', () {
    final im = img.decodeJpg(_redactedJpeg)!;
    final ok = applyStamp(im, date: DateTime(2026, 11, 1), itemName: '자전거');
    expect(ok, isFalse);
    final out = img.encodeJpg(im);
    expect(_hasGpsIfd(out), isFalse);

    final im2 = img.decodeJpg(_validJpeg)!;
    applyStamp(im2, date: DateTime(2026, 11, 1), itemName: '자전거');
    expect(gpsStateOfBytes(img.encodeJpg(im2)), GpsState.valid);
  });

  test('exif 읽기 꾸러미에서도 가려진 원본은 위도 분모가 0으로 보인다 (재현 확인)', () async {
    final tags = await readExifFromBytes(_redactedJpeg);
    final lat = tags['GPS GPSLatitude']!.values.toList().cast<Ratio>();
    expect(lat.every((r) => r.denominator == 0), isTrue);
  });

  group('gpsLatLngOfBytes: 결과 목록에 보여 줄 실제 좌표', () {
    test('제대로 된 좌표를 읽고 짧게 적는다', () {
      final p = gpsLatLngOfBytes(_validJpeg)!;
      expect(p.lat, closeTo(37.2411, 1e-4));
      expect(p.lng, closeTo(127.1776, 1e-4));
      expect(shortLatLng(p), '37.24, 127.18');
    });

    test('남반구·서반구는 음수', () {
      final p = gpsLatLngOfBytes(_jpg((e) => writeGps(e, -33.8688, -70.6693)))!;
      expect(shortLatLng(p), '-33.87, -70.67');
    });

    test('가려진 좌표·위치 없음·사진이 아닌 것은 null', () {
      expect(gpsLatLngOfBytes(_redactedJpeg), isNull);
      expect(gpsLatLngOfBytes(_jpg((_) {})), isNull);
      expect(gpsLatLngOfBytes(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });
}
