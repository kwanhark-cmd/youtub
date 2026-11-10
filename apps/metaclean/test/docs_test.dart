import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metaclean/src/docs/doc_meta.dart';

Uint8List _fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

/// 검증 도구로 따로 열어 볼 수 있게 결과물을 남긴다.
void _dump(String name, Uint8List bytes) {
  final dir = Directory('build/test_out')..createSync(recursive: true);
  File('${dir.path}/$name').writeAsBytesSync(bytes);
}

bool _has(Uint8List hay, String needle) => latin1.decode(hay).contains(needle);

bool _hasUtf16(Uint8List hay, String needle) {
  final n = <int>[];
  for (final u in needle.codeUnits) {
    n
      ..add(u & 0xFF)
      ..add(u >> 8);
  }
  outer:
  for (var i = 0; i + n.length <= hay.length; i++) {
    for (var j = 0; j < n.length; j++) {
      if (hay[i + j] != n[j]) continue outer;
    }
    return true;
  }
  return false;
}

Uint8List _zip(Map<String, String> files, {String? storedFirst}) {
  final a = Archive();
  files.forEach((name, content) {
    final f = ArchiveFile.bytes(name, utf8.encode(content));
    if (name == storedFirst) f.compression = CompressionType.none;
    a.add(f);
  });
  return ZipEncoder().encodeBytes(a);
}

String _entry(Uint8List zip, String name) =>
    utf8.decode(ZipDecoder().decodeBytes(zip).findFile(name)!.content);

const _core = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
    'xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
    '<dc:title>비밀 사용설명서</dc:title><dc:subject>SecretSubject</dc:subject>'
    '<dc:creator>홍길동</dc:creator><cp:keywords>SecretKeyword</cp:keywords>'
    '<cp:lastModifiedBy>SecretLastUser</cp:lastModifiedBy><cp:revision>7</cp:revision>'
    '<dcterms:created xsi:type="dcterms:W3CDTF">2024-03-05T01:11:12Z</dcterms:created>'
    '<dcterms:modified xsi:type="dcterms:W3CDTF">2024-03-06T01:11:12Z</dcterms:modified>'
    '</cp:coreProperties>';

const _app = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
    '<Application>Microsoft Office Word</Application><Company>SecretCompany</Company>'
    '<TotalTime>42</TotalTime></Properties>';

const _document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'
    '<w:p><w:ins w:id="1" w:author="SecretReviewer" w:date="2024-03-05T10:00:00Z"><w:r><w:t>본문 내용</w:t></w:r></w:ins></w:p>'
    '</w:body></w:document>';

Uint8List _docx() => _zip({
      '[Content_Types].xml': '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>',
      'docProps/core.xml': _core,
      'docProps/app.xml': _app,
      'word/document.xml': _document,
    });

const _hpf = '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>'
    '<opf:package xmlns:opf="http://www.idpf.org/2007/opf/" version="" unique-identifier="" id="">'
    '<opf:metadata><opf:title>비밀 제목</opf:title><opf:language>ko</opf:language>'
    '<opf:meta name="creator" content="text">SecretCreator</opf:meta>'
    '<opf:meta name="subject" content="text"/>'
    '<opf:meta name="lastsaveby" content="text">SecretSaver</opf:meta>'
    '<opf:meta name="CreatedDate" content="text">2023-02-13T06:11:21Z</opf:meta>'
    '<opf:meta name="ModifiedDate" content="text">2023-02-13T06:11:21Z</opf:meta>'
    '<opf:meta name="date" content="text">2023년 2월 13일 월요일 오후 3:11:21</opf:meta>'
    '<opf:meta name="keyword" content="text"/></opf:metadata>'
    '<opf:manifest><opf:item id="header" href="Contents/header.xml" media-type="application/xml"/></opf:manifest>'
    '</opf:package>';

Uint8List _hwpx() => _zip({
      'mimetype': 'application/hwp+zip',
      'version.xml': '<v/>',
      'Contents/section0.xml': '<sec>본문</sec>',
      'Contents/content.hpf': _hpf,
    }, storedFirst: 'mimetype');

void main() {
  group('PDF', () {
    for (final name in ['sample.pdf', 'sample_objstm.pdf']) {
      test('$name: 전부 지우면 메타데이터가 한 글자도 남지 않는다', () {
        final src = _fixture(name);
        expect(detectDocKind(src), DocKind.pdf);
        final before = readDocMeta(src);
        expect(before['작성자'], 'SecretAuthorInfo');
        // 파일에는 한국 시각(+09:00)으로 적혀 있다 → 기기 시각으로 바꿔 보여 준다
        expect(before['만든 날짜'], showDate(DateTime.utc(2024, 3, 5, 1, 11, 12)));
        expect(before['수정한 날짜'], showDate(DateTime.utc(2024, 3, 6, 1, 11, 12)));
        expect(before['부가 정보(XMP)'], '있음');

        final out = cleanDocument(src).bytes;
        _dump('clean_$name', out);
        expect(RegExp(r'Secret\w+').allMatches(latin1.decode(out)), isEmpty);
        expect(_has(out, '2024'), isFalse);
        expect(_has(out, 'xpacket'), isFalse);
        expect(_has(out, 'Hello Manual') || name.contains('objstm'), isTrue);
        final meta = readDocMeta(out);
        expect(meta.containsKey('작성자'), isFalse);
        expect(meta, isEmpty);
      });

      test('$name: 제목·작성자·날짜만 고친다', () {
        final src = _fixture(name);
        final out = cleanDocument(
          src,
          edit: DocEdit(title: '사용설명서', author: 'Seller', date: DateTime(2026, 11, 10, 9, 30)),
        ).bytes;
        _dump('edit_$name', out);
        final meta = readDocMeta(out);
        expect(meta['제목'], '사용설명서');
        expect(meta['작성자'], 'Seller');
        expect(meta['만든 날짜'], '2026-11-10 09:30');
        expect(meta['주제'], 'SecretSubjectInfo'); // 손대지 않은 칸은 그대로
        final s = latin1.decode(out);
        expect(s.contains('SecretAuthorInfo'), isFalse);
        expect(s.contains('SecretTitleInfo'), isFalse);
        expect(s.contains('SecretAuthorXmp'), isFalse); // XMP는 항상 제거
        expect(s.contains('20240305'), isFalse);
      });
    }
  });

  group('PDF 날짜 보존', () {
    for (final name in ['sample.pdf', 'sample_objstm.pdf']) {
      test('$name: 제목만 고치면 원래 날짜와 작성자는 그대로 남는다', () {
        final out = cleanDocument(_fixture(name), edit: const DocEdit(title: 'Manual')).bytes;
        final meta = readDocMeta(out);
        expect(meta['제목'], 'Manual');
        expect(meta['작성자'], 'SecretAuthorInfo');
        expect(meta['만든 날짜'], showDate(DateTime.utc(2024, 3, 5, 1, 11, 12)));
        expect(_has(out, 'SecretAuthorXmp'), isFalse);
      });
    }
  });

  group('워드(docx)', () {
    test('전부 지우기', () {
      final src = _docx();
      expect(detectDocKind(src), DocKind.ooxml);
      final before = readDocMeta(src);
      expect(before['작성자'], '홍길동');
      expect(before['회사'], 'SecretCompany');

      final r = cleanDocument(src);
      _dump('clean.docx', r.bytes);
      expect(readDocMeta(r.bytes), isEmpty);
      expect(_entry(r.bytes, 'word/document.xml'), contains('본문 내용'));
      expect(_entry(r.bytes, 'word/document.xml'), isNot(contains('SecretReviewer')));
      expect(_entry(r.bytes, 'docProps/core.xml'), isNot(contains('2024')));
      expect(r.notes.join(), contains('작성자 이름'));
    });

    test('일부 수정: 고친 칸만 바뀌고 나머지는 그대로', () {
      final r = cleanDocument(
        _docx(),
        edit: DocEdit(author: '판매자 & <김>', date: DateTime.utc(2026, 11, 10, 0, 30)),
      );
      _dump('edit.docx', r.bytes);
      final meta = readDocMeta(r.bytes);
      expect(meta['작성자'], '판매자 & <김>');
      expect(meta['마지막 저장한 사람'], '판매자 & <김>');
      expect(meta['제목'], '비밀 사용설명서');
      expect(meta['만든 날짜'], showDate(DateTime.utc(2026, 11, 10, 0, 30)));
      expect(meta['수정한 날짜'], showDate(DateTime.utc(2026, 11, 10, 0, 30)));
      expect(_entry(r.bytes, 'docProps/core.xml'), contains('2026-11-10T00:30:00Z'));
      expect(meta['회사'], 'SecretCompany');
      expect(_entry(r.bytes, 'word/document.xml'),
          contains('w:author="판매자 &amp; &lt;김&gt;"'));
    });
  });

  group('한글(hwpx)', () {
    test('전부 지우기: 구조와 순서는 그대로', () {
      final src = _hwpx();
      expect(detectDocKind(src), DocKind.hwpx);
      expect(readDocMeta(src)['작성자'], 'SecretCreator');

      final out = cleanDocument(src).bytes;
      _dump('clean.hwpx', out);
      expect(readDocMeta(out), isEmpty);
      final a = ZipDecoder().decodeBytes(out);
      expect(a.files.first.name, 'mimetype');
      expect(a.files.first.compression, CompressionType.none);
      final hpf = _entry(out, 'Contents/content.hpf');
      expect(hpf, contains('<opf:language>ko</opf:language>'));
      expect(hpf, contains('<opf:manifest>'));
      expect(hpf, isNot(contains('Secret')));
      expect(hpf, isNot(contains('2023')));
      expect(_entry(out, 'Contents/section0.xml'), '<sec>본문</sec>');
    });

    test('일부 수정', () {
      final out = cleanDocument(
        _hwpx(),
        edit: DocEdit(title: '새 제목', author: '판매자', date: DateTime(2026, 11, 10, 9, 30)),
      ).bytes;
      _dump('edit.hwpx', out);
      final meta = readDocMeta(out);
      expect(meta['제목'], '새 제목');
      expect(meta['작성자'], '판매자');
      expect(meta['마지막 저장한 사람'], '판매자');
      expect(meta['날짜 글자'], '2026년 11월 10일 화요일 오전 9:30:00');
      expect(meta['만든 날짜'], '2026-11-10 09:30');
      expect(meta['수정한 날짜'], '2026-11-10 09:30');
    });
  });

  group('한글(hwp)', () {
    test('전부 지우기: 크기와 본문은 그대로', () {
      final src = _fixture('sample.hwp');
      expect(detectDocKind(src), DocKind.cfb);
      final before = readDocMeta(src);
      expect(before['제목'], '비밀제목입니다');
      expect(before['작성자'], '비밀작성자');
      expect(before['마지막 저장한 사람'], 'secretuser');

      final out = cleanDocument(src).bytes;
      _dump('clean.hwp', out);
      expect(out.length, src.length);
      expect(readDocMeta(out), isEmpty);
      for (final s in ['비밀', 'secretuser', '2024', 'WIN32']) {
        expect(_hasUtf16(out, s), isFalse, reason: s);
      }
      expect(_has(out, 'HWP Document File'), isTrue);
    });

    test('일부 수정', () {
      final out = cleanDocument(
        _fixture('sample.hwp'),
        edit: DocEdit(title: '사용설명서', author: '판매자', date: DateTime(2026, 11, 10, 9, 30)),
      ).bytes;
      _dump('edit.hwp', out);
      final meta = readDocMeta(out);
      expect(meta['제목'], '사용설명서');
      expect(meta['작성자'], '판매자');
      expect(meta['마지막 저장한 사람'], '판매자');
      expect(meta['만든 날짜'], '2026-11-10 09:30');
      expect(meta['수정한 날짜'], '2026-11-10 09:30');
      expect(meta['날짜 글자'], '2026년 11월 10일 화요일 오전 9:30:00');
      expect(meta['주제'], '비밀주제'); // 손대지 않은 칸은 그대로
      expect(_hasUtf16(out, '비밀작성자'), isFalse);
      expect(_hasUtf16(out, 'secretuser'), isFalse);
    });

    test('자리가 모자라면 글자를 줄여서 넣고 알려 준다', () {
      final r = cleanDocument(
        _fixture('sample.hwp'),
        edit: DocEdit(title: '가' * 200),
      );
      final title = readDocMeta(r.bytes)['제목']!;
      expect(title.length, lessThan(200));
      expect(title, startsWith('가가가'));
      expect(r.notes.join(), contains('줄였어요'));
      expect(readDocMeta(r.bytes)['작성자'], '비밀작성자');
    });
  });

  group('만든 프로그램만 고치기', () {
    const edit = DocEdit(program: 'My Office');
    test('PDF', () {
      final meta = readDocMeta(cleanDocument(_fixture('sample.pdf'), edit: edit).bytes);
      expect(meta['만든 프로그램'], 'My Office');
      expect(meta['PDF 변환기'], 'My Office');
      expect(meta['작성자'], 'SecretAuthorInfo');
    });
    test('워드', () {
      final out = cleanDocument(_docx(), edit: edit).bytes;
      final meta = readDocMeta(out);
      expect(meta['프로그램'], 'My Office');
      expect(meta['회사'], 'SecretCompany');
      expect(meta['작성자'], '홍길동');
    });
    test('한글(hwp)', () {
      final out = cleanDocument(_fixture('sample.hwp'), edit: edit).bytes;
      final meta = readDocMeta(out);
      expect(meta['버전 정보'], 'My Office');
      expect(meta['작성자'], '비밀작성자');
      expect(_hasUtf16(out, 'WIN32'), isFalse);
    });
    test('한글(hwpx)은 건너뛰고 알려 준다', () {
      final r = cleanDocument(_hwpx(), edit: edit);
      expect(r.notes.join(), contains('건너뛰었어요'));
      expect(readDocMeta(r.bytes)['작성자'], 'SecretCreator');
    });
  });

  test('암호 걸린 PDF는 친절한 오류', () {
    final src = _fixture('sample_encrypted.pdf');
    expect(() => readDocMeta(src), throwsA(isA<DocUnsupported>()));
    expect(() => cleanDocument(src), throwsA(isA<DocUnsupported>()));
  });

  test('삽입된 그림이 따로 가진 작성 정보도 지운다', () {
    final src = _fixture('sample_embedded_info.pdf');
    expect(_has(src, 'SecretFigureTool'), isTrue);
    for (final edit in [null, const DocEdit(author: 'Seller')]) {
      final r = cleanDocument(src, edit: edit);
      expect(_has(r.bytes, 'SecretFigureTool'), isFalse);
      expect(_has(r.bytes, 'SecretFigureTitle'), isFalse);
      expect(r.notes.join(), contains('숨어 있던 작성 정보'));
      expect(readDocMeta(r.bytes)['작성자'], edit == null ? isNull : 'Seller');
    }
  });

  test('모르는 파일은 친절한 오류', () {
    expect(detectDocKind(Uint8List.fromList(utf8.encode('just text'))), isNull);
    expect(() => cleanDocument(Uint8List.fromList(utf8.encode('just text'))),
        throwsA(isA<DocUnsupported>()));
  });
}
