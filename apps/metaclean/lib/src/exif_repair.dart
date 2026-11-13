import 'dart:typed_data';

/// JPEG 속 EXIF 기록의 뼈대를 표준대로 다시 짠다.
///
/// 사진 부품(image)이 EXIF 를 적을 때, 세부 묶음·위치(GPS) 묶음의 끝에 붙여야 하는
/// "다음 묶음 없음" 표시(4바이트 0)를 빠뜨린다. 그러면 삼성 갤러리 같은 앱은 그
/// 자리의 엉뚱한 숫자를 다음 묶음 주소로 읽다가 위치 정보를 버린다 (지도가 안 나옴).
/// 값은 하나도 바꾸지 않고, 묶음마다 끝 표시를 넣고 값 자리를 짝수 주소에 맞춘다.
///
/// EXIF 가 없거나 읽을 수 없으면 받은 그대로 돌려준다.
Uint8List repairJpegExif(Uint8List jpeg) {
  try {
    if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return jpeg;
    var i = 2;
    while (i + 4 <= jpeg.length) {
      if (jpeg[i] != 0xFF) return jpeg;
      final marker = jpeg[i + 1];
      if (marker == 0xDA || marker == 0xD9) return jpeg; // 그림 자료 시작
      final len = (jpeg[i + 2] << 8) | jpeg[i + 3];
      if (len < 2 || i + 2 + len > jpeg.length) return jpeg;
      if (marker == 0xE1 &&
          len >= 8 &&
          jpeg[i + 4] == 0x45 && // E
          jpeg[i + 5] == 0x78 && // x
          jpeg[i + 6] == 0x69 && // i
          jpeg[i + 7] == 0x66 && // f
          jpeg[i + 8] == 0 &&
          jpeg[i + 9] == 0) {
        final tiff = Uint8List.sublistView(jpeg, i + 10, i + 2 + len);
        final fixed = rebuildTiff(tiff);
        if (fixed == null || fixed.length + 8 > 0xFFFF) return jpeg;
        final segLen = fixed.length + 8;
        final out = BytesBuilder(copy: false)
          ..add(Uint8List.sublistView(jpeg, 0, i))
          ..add([0xFF, 0xE1, segLen >> 8, segLen & 0xFF])
          ..add(const [0x45, 0x78, 0x69, 0x66, 0, 0])
          ..add(fixed)
          ..add(Uint8List.sublistView(jpeg, i + 2 + len));
        return out.toBytes();
      }
      i += 2 + len;
    }
    return jpeg;
  } catch (_) {
    return jpeg;
  }
}

const _typeSize = {
  1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8, //
};

class _Entry {
  _Entry(this.tag, this.type, this.count, this.value);
  final int tag;
  final int type;
  final int count;

  /// 값 자료 (4바이트 이하면 칸 안에 든 4바이트 그대로).
  Uint8List value;

  /// 이 칸이 가리키는 딸린 묶음.
  _Ifd? child;
}

class _Ifd {
  final entries = <_Entry>[];
  Uint8List? thumbnail;
  int offset = 0;
  int thumbOffset = 0;
}

/// TIFF(EXIF 본문) 덩어리를 읽어 표준 뼈대로 다시 적는다. 읽을 수 없으면 null.
Uint8List? rebuildTiff(Uint8List t) {
  if (t.length < 8) return null;
  final Endian e;
  if (t[0] == 0x49 && t[1] == 0x49) {
    e = Endian.little;
  } else if (t[0] == 0x4D && t[1] == 0x4D) {
    e = Endian.big;
  } else {
    return null;
  }
  final bd = ByteData.sublistView(t);
  if (bd.getUint16(2, e) != 0x2A) return null;

  final seen = <int>{};
  // 묶음 하나를 읽는다. 다음 묶음 주소는 [chain] 일 때만 믿는다.
  (_Ifd, int)? readIfd(int off, {required bool chain, required int depth}) {
    if (off < 8 || off + 2 > t.length || !seen.add(off) || depth > 3) {
      return null;
    }
    final n = bd.getUint16(off, e);
    if (off + 2 + 12 * n > t.length) return null;
    final ifd = _Ifd();
    for (var k = 0; k < n; k++) {
      final p = off + 2 + 12 * k;
      final tag = bd.getUint16(p, e);
      final type = bd.getUint16(p + 2, e);
      final count = bd.getUint32(p + 4, e);
      final unit = _typeSize[type];
      if (unit == null) return null;
      final size = unit * count;
      final Uint8List value;
      if (size <= 4) {
        value = Uint8List.fromList(t.sublist(p + 8, p + 12));
      } else {
        final vo = bd.getUint32(p + 8, e);
        if (vo + size > t.length) return null;
        value = Uint8List.fromList(t.sublist(vo, vo + size));
      }
      final entry = _Entry(tag, type, count, value);
      if ((tag == 0x8769 || tag == 0x8825 || tag == 0xA005) &&
          type == 4 &&
          count == 1) {
        final sub = readIfd(bd.getUint32(p + 8, e),
            chain: false, depth: depth + 1);
        if (sub == null) return null;
        entry.child = sub.$1;
      }
      ifd.entries.add(entry);
    }
    var next = 0;
    if (chain && off + 6 + 12 * n <= t.length) {
      next = bd.getUint32(off + 2 + 12 * n, e);
    }
    return (ifd, next);
  }

  final first = readIfd(bd.getUint32(4, e), chain: true, depth: 0);
  if (first == null) return null;
  final chain = <_Ifd>[first.$1];
  if (first.$2 != 0) {
    final second = readIfd(first.$2, chain: true, depth: 0);
    if (second != null) {
      final ifd1 = second.$1;
      // 작은 미리보기 그림 자료를 함께 옮긴다.
      int? at, len;
      for (final en in ifd1.entries) {
        if (en.tag == 0x0201) at = _int(en, e);
        if (en.tag == 0x0202) len = _int(en, e);
      }
      if (at != null && len != null && len > 0) {
        if (at + len > t.length) return null;
        ifd1.thumbnail = Uint8List.fromList(t.sublist(at, at + len));
      }
      chain.add(ifd1);
    }
  }

  // 자리 잡기: 묶음 → 그 묶음의 큰 값 → 딸린 묶음들 → (미리보기 그림).
  var cursor = 8;
  void place(_Ifd ifd) {
    ifd.entries.sort((a, b) => a.tag.compareTo(b.tag));
    ifd.offset = cursor;
    cursor += 2 + 12 * ifd.entries.length + 4;
    for (final en in ifd.entries) {
      if (en.child == null && en.value.length > 4) {
        cursor += en.value.length + (en.value.length & 1);
      }
    }
    for (final en in ifd.entries) {
      if (en.child != null) place(en.child!);
    }
    if (ifd.thumbnail != null) {
      ifd.thumbOffset = cursor;
      cursor += ifd.thumbnail!.length + (ifd.thumbnail!.length & 1);
    }
  }

  for (final ifd in chain) {
    place(ifd);
  }

  final out = Uint8List(cursor);
  final ob = ByteData.sublistView(out);
  out.setRange(0, 4, t);
  ob.setUint32(4, 8, e);

  void write(_Ifd ifd, int next) {
    var p = ifd.offset;
    ob.setUint16(p, ifd.entries.length, e);
    p += 2;
    var data = ifd.offset + 2 + 12 * ifd.entries.length + 4;
    for (final en in ifd.entries) {
      ob.setUint16(p, en.tag, e);
      ob.setUint16(p + 2, en.type, e);
      ob.setUint32(p + 4, en.count, e);
      if (en.child != null) {
        ob.setUint32(p + 8, en.child!.offset, e);
      } else if (en.tag == 0x0201 && ifd.thumbnail != null) {
        ob.setUint32(p + 8, ifd.thumbOffset, e);
      } else if (en.value.length <= 4) {
        out.setRange(p + 8, p + 8 + en.value.length, en.value);
      } else {
        ob.setUint32(p + 8, data, e);
        out.setRange(data, data + en.value.length, en.value);
        data += en.value.length + (en.value.length & 1);
      }
      p += 12;
    }
    ob.setUint32(p, next, e);
    for (final en in ifd.entries) {
      if (en.child != null) write(en.child!, 0);
    }
    if (ifd.thumbnail != null) {
      out.setRange(ifd.thumbOffset,
          ifd.thumbOffset + ifd.thumbnail!.length, ifd.thumbnail!);
    }
  }

  for (var k = 0; k < chain.length; k++) {
    write(chain[k], k + 1 < chain.length ? chain[k + 1].offset : 0);
  }
  return out;
}

int? _int(_Entry en, Endian e) {
  final bd = ByteData.sublistView(en.value);
  if (en.count != 1) return null;
  if (en.type == 4) return bd.getUint32(0, e);
  if (en.type == 3) return bd.getUint16(0, e);
  return null;
}
