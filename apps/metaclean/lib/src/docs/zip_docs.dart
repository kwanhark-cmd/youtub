import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'doc_types.dart';

const _coreNs = {
  'xmlns:cp':
      'http://schemas.openxmlformats.org/package/2006/metadata/core-properties',
  'xmlns:dc': 'http://purl.org/dc/elements/1.1/',
  'xmlns:dcterms': 'http://purl.org/dc/terms/',
  'xmlns:dcmitype': 'http://purl.org/dc/dcmitype/',
  'xmlns:xsi': 'http://www.w3.org/2001/XMLSchema-instance',
};

String get _emptyCore {
  final ns = _coreNs.entries.map((e) => '${e.key}="${e.value}"').join(' ');
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<cp:coreProperties $ns></cp:coreProperties>';
}

const _emptyApp = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"></Properties>';

const _emptyCustom = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/custom-properties" '
    'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"></Properties>';

Archive _unzip(Uint8List bytes) {
  try {
    return ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const DocUnsupported('문서 파일을 열 수 없어요. 암호가 걸렸거나 손상된 파일일 수 있어요.');
  }
}

/// 압축 문서가 워드류(ooxml)인지 한글(hwpx)인지 알아낸다.
DocKind? zipDocKind(Uint8List bytes) {
  final Archive a;
  try {
    a = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return null;
  }
  final names = a.files.map((f) => f.name).toSet();
  if (names.contains('[Content_Types].xml')) return DocKind.ooxml;
  if (names.contains('Contents/content.hpf')) return DocKind.hwpx;
  return null;
}

String _text(ArchiveFile f) => utf8.decode(f.content, allowMalformed: true);

String _esc(String v) => v
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _unesc(String v) => v
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// 파일에 적힌 날짜(세계 표준시)를 기기 시각으로 보여 준다.
String _showIso(String v) {
  final d = DateTime.tryParse(v);
  return d == null ? v : showDate(d);
}

const _dateLabels = {'만든 날짜', '수정한 날짜', '마지막 인쇄'};

String _isoUtc(DateTime d) {
  final u = d.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}

/// 파일들을 순서·압축 방식 그대로 다시 묶는다. [change]가 새 내용을 주면 바꾼다.
/// 압축 파일 안의 "수정한 시각"도 흔적이 되므로 [stamp]로 통일한다.
Uint8List _rezip(
  Archive src,
  DateTime stamp,
  Uint8List? Function(ArchiveFile f) change,
) {
  final out = Archive();
  final secs = stamp.millisecondsSinceEpoch ~/ 1000;
  for (final f in src.files) {
    if (!f.isFile) {
      out.add(ArchiveFile.directory(f.name)..lastModTime = secs);
      continue;
    }
    final data = change(f) ?? f.content;
    final nf = ArchiveFile.bytes(f.name, data)
      ..compression = f.compression == CompressionType.none
          ? CompressionType.none
          : CompressionType.deflate
      ..lastModTime = secs;
    out.add(nf);
  }
  return ZipEncoder().encodeBytes(out, modified: stamp);
}

Uint8List _u(String s) => Uint8List.fromList(utf8.encode(s));

// ───────────────────────── 워드·엑셀·파워포인트 ─────────────────────────

XmlElement? _child(XmlElement parent, String local) {
  for (final e in parent.childElements) {
    if (e.name.local == local) return e;
  }
  return null;
}

/// docx/xlsx/pptx 메타데이터를 읽는다.
Map<String, String> readOoxmlMeta(Uint8List bytes) {
  final a = _unzip(bytes);
  final out = <String, String>{};
  void fromXml(String path, Map<String, String> labels) {
    final f = a.findFile(path);
    if (f == null) return;
    try {
      final root = XmlDocument.parse(_text(f)).rootElement;
      labels.forEach((local, label) {
        final v = _child(root, local)?.innerText.trim() ?? '';
        if (v.isNotEmpty) out[label] = _dateLabels.contains(label) ? _showIso(v) : v;
      });
    } catch (_) {}
  }

  fromXml('docProps/core.xml', const {
    'title': '제목',
    'creator': '작성자',
    'lastModifiedBy': '마지막 저장한 사람',
    'subject': '주제',
    'keywords': '키워드',
    'description': '설명',
    'created': '만든 날짜',
    'modified': '수정한 날짜',
    'lastPrinted': '마지막 인쇄',
  });
  fromXml('docProps/app.xml', const {
    'Application': '프로그램',
    'Company': '회사',
    'Manager': '관리자',
    'TotalTime': '편집 시간(분)',
  });
  final custom = a.findFile('docProps/custom.xml');
  if (custom != null && _text(custom).contains('<property')) {
    out['사용자 지정 속성'] = '있음';
  }
  return out;
}

void _setChild(XmlElement root, String qualified, String value,
    {Map<String, String> attrs = const {}}) {
  final local = qualified.split(':').last;
  var e = _child(root, local);
  if (e == null) {
    e = XmlElement(
      XmlName.fromString(qualified),
      attrs.entries.map((a) => XmlAttribute(XmlName.fromString(a.key), a.value)),
    );
    root.children.add(e);
  }
  e.innerText = value;
}

String _editCore(String xml, DocEdit edit) {
  final doc = XmlDocument.parse(xml);
  final root = doc.rootElement;
  _coreNs.forEach((k, v) {
    if (root.getAttribute(k) == null) root.setAttribute(k, v);
  });
  if (edit.title != null) _setChild(root, 'dc:title', edit.title!);
  if (edit.author != null) {
    _setChild(root, 'dc:creator', edit.author!);
    _setChild(root, 'cp:lastModifiedBy', edit.author!);
  }
  if (edit.date != null) {
    const w3c = {'xsi:type': 'dcterms:W3CDTF'};
    final d = _isoUtc(edit.date!);
    _setChild(root, 'dcterms:created', d, attrs: w3c);
    _setChild(root, 'dcterms:modified', d, attrs: w3c);
    final printed = _child(root, 'lastPrinted');
    if (printed != null) printed.innerText = d;
  }
  return doc.toXmlString();
}

final _authorAttr =
    RegExp(r'\b(w:author|w15:author|w:initials|w15:userId)="[^"]*"');

/// 본문에 남는 변경 내용·메모의 작성자 이름을 지우거나 바꾼다.
String? _scrubAuthors(String xml, String? newAuthor) {
  if (!_authorAttr.hasMatch(xml)) return null;
  return xml.replaceAllMapped(_authorAttr, (m) {
    final key = m.group(1)!;
    final keepName = newAuthor != null && key.endsWith(':author');
    return '$key="${keepName ? _esc(newAuthor) : ''}"';
  });
}

/// docx/xlsx/pptx 메타데이터를 지우거나([edit]가 null) 일부만 고친다.
DocOutput cleanOoxml(Uint8List bytes, {DocEdit? edit}) {
  final a = _unzip(bytes);
  final notes = <String>[];
  var scrubbed = false;
  final stamp = edit?.date ?? DateTime(1980, 1, 1);
  final out = _rezip(a, stamp, (f) {
    final name = f.name;
    if (name == 'docProps/core.xml') {
      if (edit == null) return _u(_emptyCore);
      try {
        return _u(_editCore(_text(f), edit));
      } catch (_) {
        return _u(_editCore(_emptyCore, edit));
      }
    }
    if (edit == null && name == 'docProps/app.xml') return _u(_emptyApp);
    if (edit?.program != null && name == 'docProps/app.xml') {
      try {
        final doc = XmlDocument.parse(_text(f));
        _setChild(doc.rootElement, 'Application', edit!.program!);
        final ver = _child(doc.rootElement, 'AppVersion');
        if (ver != null) doc.rootElement.children.remove(ver);
        return _u(doc.toXmlString());
      } catch (_) {
        return null;
      }
    }
    if (edit == null && name == 'docProps/custom.xml') return _u(_emptyCustom);
    final wantScrub = edit == null || edit.author != null;
    if (wantScrub && name.startsWith('word/') && name.endsWith('.xml')) {
      final c = f.content;
      final utf16 = c.length > 1 &&
          ((c[0] == 0xFF && c[1] == 0xFE) || (c[0] == 0xFE && c[1] == 0xFF));
      if (utf16) return null;
      final changed = _scrubAuthors(_text(f), edit?.author);
      if (changed != null) {
        scrubbed = true;
        return _u(changed);
      }
    }
    return null;
  });
  if (scrubbed) {
    notes.add(edit == null
        ? '본문의 메모·변경 내용에 남아 있던 작성자 이름도 지웠어요.'
        : '본문의 메모·변경 내용에 남아 있던 작성자 이름도 바꿨어요.');
  }
  return DocOutput(out, notes);
}

// ───────────────────────────── 한글 hwpx ─────────────────────────────

final _hpfMeta = RegExp(
  r'<((?:\w+:)?)meta\b([^>]*?)(?:/>|>(.*?)</(?:\w+:)?meta>)',
  dotAll: true,
);
final _hpfTitle = RegExp(
  r'<((?:\w+:)?)title\b([^>]*?)(?:/>|>(.*?)</(?:\w+:)?title>)',
  dotAll: true,
);
final _nameAttr = RegExp(r'\bname="([^"]*)"');

const _hwpxLabels = {
  'creator': '작성자',
  'lastsaveby': '마지막 저장한 사람',
  'subject': '주제',
  'description': '설명',
  'keyword': '키워드',
  'CreatedDate': '만든 날짜',
  'ModifiedDate': '수정한 날짜',
  'date': '날짜 글자',
};

/// 메타데이터 구역(`<…metadata>` 안)만 잘라 낸다.
({int start, int end})? _metadataBlock(String xml) {
  final open = RegExp(r'<(?:\w+:)?metadata\b[^>]*>').firstMatch(xml);
  if (open == null) return null;
  final close =
      RegExp(r'</(?:\w+:)?metadata>').firstMatch(xml.substring(open.end));
  if (close == null) return null;
  return (start: open.end, end: open.end + close.start);
}

/// hwpx 메타데이터를 읽는다.
Map<String, String> readHwpxMeta(Uint8List bytes) {
  final a = _unzip(bytes);
  final f = a.findFile('Contents/content.hpf');
  final out = <String, String>{};
  if (f == null) return out;
  final xml = _text(f);
  final block = _metadataBlock(xml);
  if (block == null) return out;
  final meta = xml.substring(block.start, block.end);
  final t = _hpfTitle.firstMatch(meta)?.group(3)?.trim() ?? '';
  if (t.isNotEmpty) out['제목'] = _unesc(t);
  for (final m in _hpfMeta.allMatches(meta)) {
    final name = _nameAttr.firstMatch(m.group(2) ?? '')?.group(1) ?? '';
    final v = (m.group(3) ?? '').trim();
    if (v.isEmpty) continue;
    final label = _hwpxLabels[name] ?? name;
    out[label] = _dateLabels.contains(label) ? _showIso(v) : _unesc(v);
  }
  return out;
}

String _editHpf(String xml, DocEdit? edit) {
  final block = _metadataBlock(xml);
  if (block == null) return xml;
  var meta = xml.substring(block.start, block.end);

  String element(String prefix, String tag, String attrs, String value) =>
      '<$prefix$tag$attrs>${_esc(value)}</$prefix$tag>';

  final newByName = <String, String>{};
  if (edit != null) {
    if (edit.author != null) {
      newByName['creator'] = edit.author!;
      newByName['lastsaveby'] = edit.author!;
    }
    if (edit.date != null) {
      newByName['CreatedDate'] = _isoUtc(edit.date!);
      newByName['ModifiedDate'] = _isoUtc(edit.date!);
      newByName['date'] = koreanDateString(edit.date!);
    }
  }

  meta = meta.replaceAllMapped(_hpfMeta, (m) {
    final prefix = m.group(1)!;
    final attrs = m.group(2)!.replaceAll(RegExp(r'\s+$'), '');
    final name = _nameAttr.firstMatch(attrs)?.group(1) ?? '';
    if (edit == null) return element(prefix, 'meta', attrs, '');
    final v = newByName.remove(name);
    return v == null ? m.group(0)! : element(prefix, 'meta', attrs, v);
  });

  var prefix = 'opf:';
  var titleFound = false;
  meta = meta.replaceAllMapped(_hpfTitle, (m) {
    titleFound = true;
    prefix = m.group(1)!;
    final attrs = m.group(2)!.replaceAll(RegExp(r'\s+$'), '');
    if (edit == null) return element(prefix, 'title', attrs, '');
    if (edit.title == null) return m.group(0)!;
    return element(prefix, 'title', attrs, edit.title!);
  });
  if (!titleFound && edit?.title != null) {
    meta = element(prefix, 'title', '', edit!.title!) + meta;
  }
  // 원래 없던 칸은 새로 만든다.
  newByName.forEach((name, v) {
    meta += element(prefix, 'meta', ' name="$name" content="text"', v);
  });
  return xml.substring(0, block.start) + meta + xml.substring(block.end);
}

/// hwpx 메타데이터를 지우거나([edit]가 null) 일부만 고친다.
DocOutput cleanHwpx(Uint8List bytes, {DocEdit? edit}) {
  final a = _unzip(bytes);
  final stamp = edit?.date ?? DateTime(1980, 1, 1);
  final out = _rezip(a, stamp, (f) {
    if (f.name == 'Contents/content.hpf') return _u(_editHpf(_text(f), edit));
    return null;
  });
  return DocOutput(out, [
    if (edit?.program != null) '한글(hwpx) 문서에는 "만든 프로그램" 칸이 따로 없어 그 항목은 건너뛰었어요.',
  ]);
}
