import 'dart:typed_data';

/// 메타데이터 제거 결과.
class StripResult {
  const StripResult({
    required this.bytes,
    required this.format,
    required this.removedSegments,
    required this.trailingDataRemoved,
  });

  /// 메타데이터가 제거된 사진 바이트 (픽셀은 원본 그대로, 무손실).
  final Uint8List bytes;

  /// 'jpeg' 또는 'png'.
  final String format;

  /// 제거한 메타데이터 블록 수.
  final int removedSegments;

  /// 사진 끝에 붙어 있던 숨은 데이터(갤럭시 모션 포토 동영상 등)를 잘라냈는지.
  final bool trailingDataRemoved;
}

/// JPEG/PNG 메타데이터를 무손실로 제거한다. 지원하지 않는 형식이면 null.
///
/// [keepExif]가 참이면 JPEG의 EXIF 블록만 남기고 나머지(XMP·모션포토 등)를
/// 지운다. 날짜·위치만 고쳐 쓸 때 쓴다.
StripResult? stripMetadata(Uint8List src, {bool keepExif = false}) {
  final jpeg = _stripJpeg(src, keepExif: keepExif);
  if (jpeg != null) return jpeg;
  return _stripPng(src);
}

bool _isExifSegment(Uint8List src, int i, int end) {
  // APP1 + 길이(2) 뒤에 "Exif\0\0"
  if (end - i < 10) return false;
  return src[i + 4] == 0x45 &&
      src[i + 5] == 0x78 &&
      src[i + 6] == 0x69 &&
      src[i + 7] == 0x66 &&
      src[i + 8] == 0x00 &&
      src[i + 9] == 0x00;
}

/// JPEG: APP1~APP15(EXIF·XMP·GPS 등)와 COM 주석을 제거한다.
/// 화면 표시에 필요한 APP0(JFIF)·APP14(Adobe)는 남긴다.
/// EOI(끝 표식) 뒤에 붙은 숨은 데이터(모션 포토 동영상)도 잘라낸다.
StripResult? _stripJpeg(Uint8List src, {bool keepExif = false}) {
  if (src.length < 4 || src[0] != 0xFF || src[1] != 0xD8) return null;
  final out = BytesBuilder(copy: false);
  out.add(const [0xFF, 0xD8]);
  var i = 2;
  var removed = 0;
  var trailingRemoved = false;
  while (i + 3 < src.length) {
    if (src[i] != 0xFF) return null; // 손상된 파일
    final marker = src[i + 1];
    if (marker == 0xD8) {
      i += 2;
      continue;
    }
    if (marker == 0xD9) {
      out.add(const [0xFF, 0xD9]);
      i += 2;
      if (i < src.length) trailingRemoved = true;
      break;
    }
    if (marker == 0xDA) {
      // SOS(압축 데이터 시작): EOI까지 그대로 복사.
      var eoi = -1;
      for (var k = i; k + 1 < src.length; k++) {
        if (src[k] == 0xFF && src[k + 1] == 0xD9) {
          eoi = k;
          break;
        }
      }
      if (eoi == -1) {
        out.add(Uint8List.sublistView(src, i));
      } else {
        out.add(Uint8List.sublistView(src, i, eoi + 2));
        if (eoi + 2 < src.length) trailingRemoved = true;
      }
      break;
    }
    final len = (src[i + 2] << 8) | src[i + 3];
    final end = i + 2 + len;
    if (len < 2 || end > src.length) return null;
    var isMeta =
        (marker >= 0xE1 && marker <= 0xEF && marker != 0xEE) || marker == 0xFE;
    if (isMeta && keepExif && marker == 0xE1 && _isExifSegment(src, i, end)) {
      isMeta = false;
    }
    if (isMeta) {
      removed++;
    } else {
      out.add(Uint8List.sublistView(src, i, end));
    }
    i = end;
  }
  return StripResult(
    bytes: out.toBytes(),
    format: 'jpeg',
    removedSegments: removed,
    trailingDataRemoved: trailingRemoved,
  );
}

const _pngKeep = {
  'IHDR', 'PLTE', 'IDAT', 'IEND', // 필수
  'tRNS', 'gAMA', 'sRGB', 'iCCP', 'bKGD', 'pHYs', // 표시용
  'acTL', 'fcTL', 'fdAT', // 움직이는 PNG
};

/// PNG: tEXt·iTXt·zTXt·tIME·eXIf 등 메타데이터 청크를 제거한다.
StripResult? _stripPng(Uint8List src) {
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (src.length < 8) return null;
  for (var k = 0; k < 8; k++) {
    if (src[k] != sig[k]) return null;
  }
  final out = BytesBuilder(copy: false);
  out.add(sig);
  var i = 8;
  var removed = 0;
  var trailingRemoved = false;
  while (i + 8 <= src.length) {
    final len = (src[i] << 24) | (src[i + 1] << 16) | (src[i + 2] << 8) | src[i + 3];
    final type = String.fromCharCodes(src.sublist(i + 4, i + 8));
    final end = i + 12 + len;
    if (len < 0 || end > src.length) return null;
    if (_pngKeep.contains(type)) {
      out.add(Uint8List.sublistView(src, i, end));
    } else {
      removed++;
    }
    i = end;
    if (type == 'IEND') {
      if (i < src.length) trailingRemoved = true;
      break;
    }
  }
  return StripResult(
    bytes: out.toBytes(),
    format: 'png',
    removedSegments: removed,
    trailingDataRemoved: trailingRemoved,
  );
}
