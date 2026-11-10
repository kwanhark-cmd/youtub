import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'exif_utils.dart';
import 'strip.dart';

/// 위치 정보를 어떻게 할지.
enum GpsAction { keep, remove, change }

/// 촬영 기기(제조사·기종) 정보를 어떻게 할지.
enum DeviceAction { keep, remove, change }

/// 기기를 알아볼 수 있는 칸들 (0번 묶음 / 세부 묶음).
const _deviceTagsIfd0 = [0x010F, 0x0110, 0x0131, 0xC614]; // 제조사, 기종, 소프트웨어, 고유 기종명
const _deviceTagsExif = [
  0x927C, // 제조사 전용 기록(MakerNote)
  0xA420, // 사진 고유 번호
  0xA430, // 카메라 주인 이름
  0xA431, // 본체 일련번호
  0xA433, 0xA434, 0xA435, // 렌즈 제조사·기종·일련번호
];

/// 일부 수정 결과.
class PhotoEditResult {
  const PhotoEditResult({required this.bytes, required this.reEncoded});

  final Uint8List bytes;

  /// JPEG가 아니어서 JPEG로 다시 저장했는지 (JPEG는 화질 그대로).
  final bool reEncoded;
}

/// 사진의 날짜·위치·촬영 기기 중 고른 것만 고친다. 나머지 EXIF는 그대로 둔다.
///
/// 원래 날짜·위치가 새어 나가지 않도록 EXIF 밖의 부가 정보(XMP, 모션포토에
/// 숨은 동영상)는 함께 지운다. JPEG는 화질 손실 없이 처리한다.
/// 지원하지 않는 형식이면 null.
PhotoEditResult? editPhotoMeta(
  Uint8List src, {
  DateTime? date,
  GpsAction gps = GpsAction.keep,
  double? lat,
  double? lng,
  DeviceAction device = DeviceAction.keep,
  String? make,
  String? model,
}) {
  if (gps == GpsAction.change && (lat == null || lng == null)) {
    throw ArgumentError('위치를 바꾸려면 위도와 경도가 모두 필요합니다');
  }
  if (device == DeviceAction.change &&
      (make ?? '').trim().isEmpty &&
      (model ?? '').trim().isEmpty) {
    throw ArgumentError('기기를 바꾸려면 제조사나 기종을 적어야 합니다');
  }

  void apply(img.ExifData exif) {
    if (date != null) {
      final d = exifDate(date);
      exif.imageIfd['DateTime'] = d;
      exif.exifIfd['DateTimeOriginal'] = d;
      exif.exifIfd['DateTimeDigitized'] = d;
      // 원래 촬영 시각이 남는 GPS 시각 칸은 지운다.
      if (exif.imageIfd.sub.containsKey('gps')) {
        exif.gpsIfd.data.remove(0x0007); // GPSTimeStamp
        exif.gpsIfd.data.remove(0x001D); // GPSDateStamp
      }
    }
    switch (gps) {
      case GpsAction.keep:
        break;
      case GpsAction.remove:
        removeGps(exif);
      case GpsAction.change:
        writeGps(exif, lat!, lng!);
    }
    if (device != DeviceAction.keep) {
      // 옛 기기를 알아볼 수 있는 칸은 지우고, 바꾸기면 새 값만 적는다.
      for (final t in _deviceTagsIfd0) {
        exif.imageIfd.data.remove(t);
      }
      if (exif.imageIfd.sub.containsKey('exif')) {
        for (final t in _deviceTagsExif) {
          exif.exifIfd.data.remove(t);
        }
      }
      if (device == DeviceAction.change) {
        final mk = (make ?? '').trim();
        final md = (model ?? '').trim();
        if (mk.isNotEmpty) exif.imageIfd.data[0x010F] = img.IfdValueAscii(mk);
        if (md.isNotEmpty) exif.imageIfd.data[0x0110] = img.IfdValueAscii(md);
      }
    }
  }

  final isJpeg = src.length > 2 && src[0] == 0xFF && src[1] == 0xD8;
  if (isJpeg) {
    final base = stripMetadata(src, keepExif: true);
    if (base == null) return null;
    final exif = img.decodeJpgExif(base.bytes) ?? img.ExifData();
    apply(exif);
    final out = img.injectJpgExif(base.bytes, exif);
    if (out == null) return null;
    return PhotoEditResult(bytes: out, reEncoded: false);
  }

  final decoded = img.decodeImage(src);
  if (decoded == null) return null;
  apply(decoded.exif);
  return PhotoEditResult(
    bytes: Uint8List.fromList(img.encodeJpg(decoded, quality: 95)),
    reEncoded: true,
  );
}
