import 'dart:convert';
import 'dart:typed_data';
import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:metaclean/src/photo_edit.dart';
import 'package:metaclean/src/photo_xmp.dart';

bool hasUtf8(Uint8List hay, String needle) {
  final n = utf8.encode(needle);
  outer:
  for (var i = 0; i + n.length <= hay.length; i++) {
    for (var j = 0; j < n.length; j++) {
      if (hay[i + j] != n[j]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  test('한글 제목·설명·키워드가 XMP로 안전하게 들어간다', () async {
    final plain = Uint8List.fromList(img.encodeJpg(img.Image(width: 12, height: 12)));
    final r = editPhotoMeta(
      plain,
      dateAction: DateAction.change,
      date: DateTime(1980, 1, 1, 12, 0),
      title: '할머니 칠순 기념',
      description: '1980년 부산에서 인화한 가족사진을 스캔함',
      keywords: ['가족', '1980', '부산', '필름사진'],
    )!;

    // XMP에서 한글이 그대로 읽힌다
    final xmp = readPhotoXmp(r.bytes)!;
    expect(xmp.title, '할머니 칠순 기념');
    expect(xmp.description, '1980년 부산에서 인화한 가족사진을 스캔함');
    expect(xmp.keywords, ['가족', '1980', '부산', '필름사진']);
    expect(hasUtf8(r.bytes, '할머니 칠순 기념'), isTrue);

    // XMP를 넣어도 EXIF 날짜는 그대로 읽힌다
    final tags = await readExifFromBytes(r.bytes);
    expect(tags['EXIF DateTimeOriginal']!.printable, '1980:01:01 12:00:00');
    // 여전히 유효한 JPEG (다시 디코드됨)
    expect(img.decodeJpg(r.bytes), isNotNull);
  });

  test('특수문자는 XML 이스케이프된다', () {
    final xmp = buildPhotoXmp(title: 'A & B < C > "D"')!;
    expect(xmp.contains('A &amp; B &lt; C &gt;'), isTrue);
    expect(xmp.contains('&quot;D&quot;'), isTrue);
  });

  test('서술 필드가 없으면 XMP를 넣지 않는다', () {
    final plain = Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8)));
    final r = editPhotoMeta(plain, dateAction: DateAction.change, date: DateTime(2000, 5, 5))!;
    expect(readPhotoXmp(r.bytes), isNull);
  });
}
