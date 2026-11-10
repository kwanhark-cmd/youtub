import 'dart:convert';
import 'dart:typed_data';

/// 사진에 정리·검색용 서술 메타데이터(제목·설명·키워드)를 XMP로 넣는다.
///
/// XMP는 UTF-8이라 한글이 안전하게 저장되고, 구글 포토·윈도·라이트룸 등이
/// 제목·설명·키워드(태그)로 읽는다. 이것은 사용자가 직접 적는 설명용 필드이지,
/// 카메라가 자동으로 남기는 촬영 기록(노출·조리개 등)이 아니다.

const _xmpSig = 'http://ns.adobe.com/xap/1.0/\u0000';

String _esc(String v) => v
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _altText(String ns, String tag, String value) =>
    '<$ns:$tag><rdf:Alt><rdf:li xml:lang="x-default">${_esc(value)}'
    '</rdf:li></rdf:Alt></$ns:$tag>';

/// 서술 필드가 하나라도 있으면 XMP 패킷 문자열을 만든다. 없으면 null.
String? buildPhotoXmp({
  String? title,
  String? description,
  List<String> keywords = const [],
}) {
  final t = title?.trim() ?? '';
  final d = description?.trim() ?? '';
  final kw = keywords.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  if (t.isEmpty && d.isEmpty && kw.isEmpty) return null;

  final body = StringBuffer();
  if (t.isNotEmpty) body.write(_altText('dc', 'title', t));
  if (d.isNotEmpty) body.write(_altText('dc', 'description', d));
  if (kw.isNotEmpty) {
    body.write('<dc:subject><rdf:Bag>');
    for (final k in kw) {
      body.write('<rdf:li>${_esc(k)}</rdf:li>');
    }
    body.write('</rdf:Bag></dc:subject>');
  }
  return '<?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>'
      '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
      '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
      '<rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '$body'
      '</rdf:Description></rdf:RDF></x:xmpmeta>'
      '<?xpacket end="w"?>';
}

/// JPEG에 XMP APP1 세그먼트를 넣는다. 앞쪽 APP0/APP1(EXIF) 뒤, 압축 데이터 앞에
/// 끼워 넣어 EXIF와 공존한다. JPEG가 아니면 원본을 그대로 돌려준다.
Uint8List injectPhotoXmp(Uint8List jpeg, String xmp) {
  if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return jpeg;
  final payload = <int>[...ascii.encode(_xmpSig), ...utf8.encode(xmp)];
  if (payload.length + 2 > 0xFFFF) return jpeg; // 너무 길면 넣지 않음
  final seg = <int>[
    0xFF,
    0xE1,
    ((payload.length + 2) >> 8) & 0xFF,
    (payload.length + 2) & 0xFF,
    ...payload,
  ];

  // 앞쪽 APP/COM 세그먼트들을 지나 삽입 위치를 찾는다.
  var i = 2;
  while (i + 4 <= jpeg.length && jpeg[i] == 0xFF) {
    final marker = jpeg[i + 1];
    final isAppOrCom = (marker >= 0xE0 && marker <= 0xEF) || marker == 0xFE;
    if (!isAppOrCom) break;
    final len = (jpeg[i + 2] << 8) | jpeg[i + 3];
    if (len < 2 || i + 2 + len > jpeg.length) break;
    i += 2 + len;
  }

  return Uint8List.fromList([
    ...jpeg.sublist(0, i),
    ...seg,
    ...jpeg.sublist(i),
  ]);
}

/// XMP 패킷에서 제목/설명/키워드를 읽는다(주로 확인·테스트용).
({String? title, String? description, List<String> keywords})? readPhotoXmp(
    Uint8List jpeg) {
  if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return null;
  var i = 2;
  while (i + 4 <= jpeg.length && jpeg[i] == 0xFF) {
    final marker = jpeg[i + 1];
    if (marker == 0xDA) break;
    final isMeta = (marker >= 0xE0 && marker <= 0xEF) || marker == 0xFE;
    if (!isMeta && !(marker >= 0xC0 && marker <= 0xFE)) break;
    if (i + 4 > jpeg.length) break;
    final len = (jpeg[i + 2] << 8) | jpeg[i + 3];
    if (len < 2 || i + 2 + len > jpeg.length) break;
    if (marker == 0xE1) {
      final seg = jpeg.sublist(i + 4, i + 2 + len);
      final sig = ascii.encode(_xmpSig);
      if (seg.length > sig.length &&
          _startsWith(seg, sig)) {
        final xml = utf8.decode(seg.sublist(sig.length), allowMalformed: true);
        return (
          title: _firstAlt(xml, 'title'),
          description: _firstAlt(xml, 'description'),
          keywords: _bag(xml),
        );
      }
    }
    i += 2 + len;
  }
  return null;
}

bool _startsWith(List<int> a, List<int> b) {
  if (a.length < b.length) return false;
  for (var k = 0; k < b.length; k++) {
    if (a[k] != b[k]) return false;
  }
  return true;
}

String? _firstAlt(String xml, String tag) {
  final m = RegExp('<dc:$tag>.*?<rdf:li[^>]*>(.*?)</rdf:li>', dotAll: true)
      .firstMatch(xml);
  return m == null ? null : _unesc(m.group(1)!);
}

List<String> _bag(String xml) {
  final m = RegExp(r'<dc:subject>(.*?)</dc:subject>', dotAll: true).firstMatch(xml);
  if (m == null) return const [];
  return RegExp(r'<rdf:li[^>]*>(.*?)</rdf:li>', dotAll: true)
      .allMatches(m.group(1)!)
      .map((e) => _unesc(e.group(1)!))
      .toList();
}

String _unesc(String v) => v
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&amp;', '&');
