import 'dart:convert';
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'doc_types.dart';

/// PDF 메타데이터 다루기.
///
/// 1) 라이브러리로 파일을 "풀어 쓴" 사본을 만든다. (압축된 구조가 평문으로 바뀜)
/// 2) 그 사본에서 문서 정보 사전과 부가 정보(XMP)를 같은 길이의 공백으로 덮는다.
///    길이가 그대로라 파일 안의 위치 표가 어긋나지 않는다.
/// 3) 일부 수정이면 새 문서 정보를 파일 끝에 덧붙인다. (옛 값은 이미 덮였다)

const _labels = {
  'Title': '제목',
  'Author': '작성자',
  'Subject': '주제',
  'Keywords': '키워드',
  'Creator': '만든 프로그램',
  'Producer': 'PDF 변환기',
  'CreationDate': '만든 날짜',
  'ModDate': '수정한 날짜',
};

/// 문서 정보 사전에 흔히 들어가는 칸. 이 칸들로만 이루어진 사전은
/// 삽입된 그림 등이 따로 들고 있는 작성 정보로 본다.
const _infoKeys = {
  'Title', 'Author', 'Subject', 'Keywords', 'Creator', 'Producer',
  'CreationDate', 'ModDate', 'Trapped', 'Company', 'Manager', 'Category',
  'Comments', 'SourceModified', 'LastModified', //
};
const _infoCore = {'Author', 'Creator', 'Producer', 'CreationDate', 'ModDate'};

class _Span {
  const _Span(this.start, this.end);
  final int start;
  final int end;
}

// ───────────────────────────── 풀어 쓰기 ─────────────────────────────

Uint8List _normalize(Uint8List bytes) {
  final PdfDocument doc;
  try {
    doc = PdfDocument(inputBytes: bytes);
  } catch (_) {
    throw const DocUnsupported('PDF를 열 수 없어요. 암호가 걸렸거나 손상된 파일일 수 있어요.');
  }
  try {
    // 문서 정보를 한 번 읽어 두어야 다시 쓸 때 원래 값이 함께 따라온다.
    doc.documentInformation.title;
    // 덧붙여 쓰지 않고 전체를 새로 써야 옛 값이 파일에 남지 않는다.
    doc.fileStructure.incrementalUpdate = false;
    doc.fileStructure.crossReferenceType =
        PdfCrossReferenceType.crossReferenceTable;
    return Uint8List.fromList(doc.saveSync());
  } catch (e) {
    throw DocUnsupported('PDF를 다시 쓰지 못했어요: $e');
  } finally {
    doc.dispose();
  }
}

// ───────────────────────────── 글자 훑기 ─────────────────────────────

bool _isDelim(int c) =>
    c <= 0x20 ||
    c == 0x28 || c == 0x29 || c == 0x3C || c == 0x3E || //
    c == 0x5B || c == 0x5D || c == 0x7B || c == 0x7D || //
    c == 0x2F || c == 0x25;

/// `(`에서 시작해 짝이 맞는 `)` 다음 위치를 돌려준다.
int _skipLiteral(String s, int i) {
  var depth = 0;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (c == 0x5C) {
      i += 2;
      continue;
    }
    if (c == 0x28) depth++;
    if (c == 0x29) {
      depth--;
      if (depth == 0) return i + 1;
    }
    i++;
  }
  return s.length;
}

/// `<<`에서 시작해 짝이 맞는 `>>`의 위치를 돌려준다. 없으면 -1.
int _matchDict(String s, int open) {
  var depth = 0;
  var i = open;
  while (i + 1 < s.length) {
    final c = s.codeUnitAt(i);
    if (c == 0x28) {
      i = _skipLiteral(s, i);
    } else if (c == 0x3C) {
      if (s.codeUnitAt(i + 1) == 0x3C) {
        depth++;
        i += 2;
      } else {
        final e = s.indexOf('>', i);
        if (e < 0) return -1;
        i = e + 1;
      }
    } else if (c == 0x3E && s.codeUnitAt(i + 1) == 0x3E) {
      depth--;
      if (depth == 0) return i;
      i += 2;
    } else {
      i++;
    }
  }
  return -1;
}

/// 사전 안쪽(`<<`와 `>>` 사이)을 "칸 이름 → 값 글자"로 나눈다.
Map<String, String> _parseDict(String s, int a, int b) {
  final out = <String, String>{};
  String? key;
  var valStart = a;
  var depth = 0;
  var i = a;
  while (i < b) {
    final c = s.codeUnitAt(i);
    if (c == 0x28) {
      i = _skipLiteral(s, i);
    } else if (c == 0x3C) {
      if (i + 1 < b && s.codeUnitAt(i + 1) == 0x3C) {
        depth++;
        i += 2;
      } else {
        final e = s.indexOf('>', i);
        i = e < 0 ? b : e + 1;
      }
    } else if (c == 0x3E && i + 1 < b && s.codeUnitAt(i + 1) == 0x3E) {
      depth--;
      i += 2;
    } else if (c == 0x5B) {
      depth++;
      i++;
    } else if (c == 0x5D) {
      depth--;
      i++;
    } else if (c == 0x2F && depth == 0) {
      var j = i + 1;
      while (j < b && !_isDelim(s.codeUnitAt(j))) {
        j++;
      }
      if (key == null) {
        key = s.substring(i + 1, j);
        valStart = j;
        i = j;
      } else if (s.substring(valStart, i).trim().isEmpty) {
        out[key] = s.substring(i, j); // 값이 이름(/False 등)인 경우
        key = null;
        i = j;
      } else {
        out[key] = s.substring(valStart, i).trim();
        key = null; // 이 '/'를 다음 칸 이름으로 다시 본다
      }
    } else {
      i++;
    }
  }
  if (key != null) out[key] = s.substring(valStart, b).trim();
  return out;
}

/// `stream … endstream` 구간(내용 부분)을 모두 찾는다.
List<_Span> _streamSpans(String s) {
  final spans = <_Span>[];
  final re = RegExp(r'stream\r?\n');
  final lenRe = RegExp(r'/Length\s+(\d+)(?!\s+\d+\s+R)');
  final endRe = RegExp(r'\r?\n?endstream');
  var from = 0;
  while (true) {
    final it = re.allMatches(s, from).iterator;
    if (!it.moveNext()) break;
    final m = it.current;
    final dataStart = m.end;
    var end = -1;
    // 길이가 사전에 바로 적혀 있으면 그 값을 믿는다 (내용에 우연히 같은 글자가 있어도 안전).
    final objAt = s.lastIndexOf('obj', m.start);
    if (objAt >= from) {
      final lm = lenRe.firstMatch(s.substring(objAt, m.start));
      if (lm != null) {
        final e = dataStart + int.parse(lm.group(1)!);
        if (e <= s.length && endRe.matchAsPrefix(s, e) != null) end = e;
      }
    }
    if (end < 0) end = s.indexOf('endstream', dataStart);
    if (end < 0) break;
    spans.add(_Span(dataStart, end));
    final after = s.indexOf('endstream', end);
    from = (after < 0 ? end : after) + 9;
  }
  return spans;
}

// ─────────────────────────── 문서 정보 찾기 ───────────────────────────

class _Trailer {
  _Trailer(this.entries, this.startXref);
  final Map<String, String> entries;
  final int startXref;
}

_Trailer? _trailer(String s) {
  final t = s.lastIndexOf('trailer');
  final sx = s.lastIndexOf('startxref');
  if (t < 0 || sx < t) return null;
  final open = s.indexOf('<<', t);
  if (open < 0 || open > sx) return null;
  final close = _matchDict(s, open);
  if (close < 0 || close > sx) return null;
  final m = RegExp(r'startxref\s+(\d+)').matchAsPrefix(s, sx);
  if (m == null) return null;
  return _Trailer(_parseDict(s, open + 2, close), int.parse(m.group(1)!));
}

/// 위치 표에서 객체가 시작하는 자리를 찾는다. (마지막 표만 본다)
int? _xrefOffset(String s, int startXref, int n) {
  if (startXref < 0 || !s.startsWith('xref', startXref)) return null;
  final head = RegExp(r'\s*(\d+)\s+(\d+)[ \t]*\r?\n');
  var pos = startXref + 4;
  while (true) {
    final h = head.matchAsPrefix(s, pos);
    if (h == null) return null;
    final start = int.parse(h.group(1)!);
    final count = int.parse(h.group(2)!);
    pos = h.end;
    if (n >= start && n < start + count) {
      final e = pos + (n - start) * 20;
      if (e + 10 > s.length) return null;
      return int.tryParse(s.substring(e, e + 10));
    }
    pos += count * 20;
  }
}

/// 문서 정보 사전의 안쪽 구간을 찾는다.
_Span? _infoSpan(String s, _Trailer t) {
  final ref = RegExp(r'^(\d+)\s+(\d+)\s+R$').firstMatch(t.entries['Info'] ?? '');
  if (ref == null) return null;
  final n = int.parse(ref.group(1)!);
  final at = _xrefOffset(s, t.startXref, n);
  if (at == null) return null;
  final head = RegExp('\\s*$n\\s+${ref.group(2)}\\s+obj\\s*').matchAsPrefix(s, at);
  if (head == null || !s.startsWith('<<', head.end)) return null;
  final close = _matchDict(s, head.end);
  if (close < 0) return null;
  return _Span(head.end + 2, close);
}

// ─────────────────────────── 글자 값 풀기·만들기 ───────────────────────────

List<int> _tokenBytes(String raw) {
  final out = <int>[];
  if (raw.startsWith('(') && raw.endsWith(')')) {
    final b = raw.substring(1, raw.length - 1);
    var i = 0;
    while (i < b.length) {
      final c = b.codeUnitAt(i);
      if (c != 0x5C) {
        out.add(c);
        i++;
        continue;
      }
      i++;
      if (i >= b.length) break;
      final e = b[i];
      const map = {'n': 10, 'r': 13, 't': 9, 'b': 8, 'f': 12};
      if (map.containsKey(e)) {
        out.add(map[e]!);
        i++;
      } else if (RegExp(r'[0-7]').hasMatch(e)) {
        var j = i;
        while (j < b.length && j < i + 3 && RegExp(r'[0-7]').hasMatch(b[j])) {
          j++;
        }
        out.add(int.parse(b.substring(i, j), radix: 8) & 0xFF);
        i = j;
      } else if (e == '\r' || e == '\n') {
        i++;
        if (e == '\r' && i < b.length && b[i] == '\n') i++;
      } else {
        out.add(b.codeUnitAt(i));
        i++;
      }
    }
  } else if (raw.startsWith('<') && raw.endsWith('>')) {
    var hex = raw.substring(1, raw.length - 1).replaceAll(RegExp(r'\s'), '');
    if (hex.length.isOdd) hex += '0';
    for (var i = 0; i + 1 < hex.length; i += 2) {
      out.add(int.tryParse(hex.substring(i, i + 2), radix: 16) ?? 0);
    }
  }
  return out;
}

String _decode(String raw) {
  final b = _tokenBytes(raw);
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
    final units = <int>[];
    for (var i = 2; i + 1 < b.length; i += 2) {
      units.add((b[i] << 8) | b[i + 1]);
    }
    return String.fromCharCodes(units);
  }
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    return utf8.decode(b.sublist(3), allowMalformed: true);
  }
  return latin1.decode(b);
}

String _encode(String v) {
  final ascii = v.codeUnits.every((c) => c >= 0x20 && c < 0x7F);
  if (ascii) {
    return '(${v.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)')})';
  }
  final sb = StringBuffer('<FEFF');
  for (final u in v.codeUnits) {
    sb.write(u.toRadixString(16).padLeft(4, '0').toUpperCase());
  }
  sb.write('>');
  return sb.toString();
}

String _pdfDate(DateTime d) {
  final u = d.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '(D:${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}'
      '${two(u.hour)}${two(u.minute)}${two(u.second)}Z)';
}

/// 날짜 글자(`D:20240305101112+09'00'`)를 시간대까지 정확히 읽는다.
DateTime? _parseDate(String text) {
  final m = RegExp(r"^\s*(?:D:)?(\d{4})(\d{2})?(\d{2})?(\d{2})?(\d{2})?(\d{2})?"
          r"\s*([+\-Z])?(\d{2})?'?(\d{2})?")
      .firstMatch(text);
  if (m == null) return null;
  int n(int g, [int d = 0]) => int.tryParse(m.group(g) ?? '') ?? d;
  final sign = m.group(7);
  if (sign == null) {
    return DateTime(n(1), n(2, 1), n(3, 1), n(4), n(5), n(6));
  }
  var t = DateTime.utc(n(1), n(2, 1), n(3, 1), n(4), n(5), n(6));
  final off = Duration(hours: n(8), minutes: n(9));
  if (sign == '+') t = t.subtract(off);
  if (sign == '-') t = t.add(off);
  return t;
}

// ───────────────────────────── 읽기 ─────────────────────────────

Map<String, String>? _infoEntries(String s) {
  final t = _trailer(s);
  if (t == null) return null;
  if (!t.entries.containsKey('Info')) return const {};
  final span = _infoSpan(s, t);
  if (span == null) return null;
  return _parseDict(s, span.start, span.end);
}

const _encrypted = DocUnsupported('암호가 걸린 PDF는 다룰 수 없어요. 암호를 푼 사본으로 다시 해 주세요.');

/// 암호가 걸려 있으면 안의 글자가 모두 암호문이라 읽거나 고칠 수 없다.
void _rejectEncrypted(String s) {
  final t = _trailer(s);
  final enc = t != null
      ? t.entries.containsKey('Encrypt')
      : RegExp(r'/Encrypt\s+\d+\s+\d+\s+R').hasMatch(s);
  if (enc) throw _encrypted;
}

/// PDF 메타데이터를 읽는다.
Map<String, String> readPdfMeta(Uint8List bytes) {
  var s = latin1.decode(bytes);
  _rejectEncrypted(s);
  final hasXmp = _hasXmp(s);
  // 구조가 압축돼 있어 바로 읽을 수 없으면 풀어 쓴 사본에서 읽는다.
  var entries = _infoEntries(s);
  if (entries == null) {
    s = latin1.decode(_normalize(bytes));
    entries = _infoEntries(s) ?? const {};
  }
  final out = <String, String>{};
  entries.forEach((key, raw) {
    if (key == 'Trapped') return;
    final isString = raw.startsWith('(') || raw.startsWith('<');
    if (!isString || raw.startsWith('<<')) return;
    final text = _decode(raw).trim();
    if (text.isEmpty) return;
    final label = _labels[key] ?? key;
    if (key == 'CreationDate' || key == 'ModDate') {
      final d = _parseDate(text);
      out[label] = d == null ? text : showDate(d);
    } else {
      out[label] = text;
    }
  });
  if (hasXmp) out['부가 정보(XMP)'] = '있음';
  return out;
}

// ───────────────────────────── 지우기 ─────────────────────────────

/// 줄바꿈만 남기고 공백으로 덮는다.
void _fill(Uint8List b, int start, int end) {
  for (var i = start; i < end; i++) {
    if (b[i] != 0x0A && b[i] != 0x0D) b[i] = 0x20;
  }
}

/// XMP 메타데이터 스트림의 내용 구간을 찾는다.
List<_Span> _xmpStreams(String s, List<_Span> spans) {
  final found = <_Span>[];
  for (final m in RegExp(r'/Type\s*/Metadata').allMatches(s)) {
    final objEnd = s.indexOf('endobj', m.end);
    for (final sp in spans) {
      if (sp.start > m.end) {
        if (objEnd < 0 || sp.start < objEnd) found.add(sp);
        break;
      }
    }
  }
  // 사전 표기가 달라도 XMP 꾸러미 표식이 보이면 포함한다.
  for (final sp in spans) {
    final head = s.substring(sp.start, (sp.start + 64).clamp(sp.start, sp.end));
    if (head.contains('<?xpacket') || head.contains('<x:xmpmeta')) {
      if (!found.any((f) => f.start == sp.start)) found.add(sp);
    }
  }
  return found;
}

bool _hasXmp(String s) => _xmpStreams(s, _streamSpans(s))
    .any((sp) => s.substring(sp.start, sp.end).trim().isNotEmpty);

/// 문서 정보처럼 생긴 다른 사전(삽입된 그림의 작성 정보 등)을 찾아 덮는다.
int _blankInfoLike(Uint8List out, String s, List<_Span> spans, _Span? main) {
  var count = 0;
  var si = 0;
  for (final m in RegExp(r'(?:^|[\r\n])\d+\s+\d+\s+obj\s*<<').allMatches(s)) {
    while (si < spans.length && spans[si].end <= m.start) {
      si++;
    }
    if (si < spans.length && m.start >= spans[si].start) continue; // 스트림 내용 안
    final open = m.end - 2;
    if (main != null && open + 2 == main.start) continue; // 본래 문서 정보
    final close = _matchDict(s, open);
    if (close < 0) continue;
    final rest = RegExp(r'\s*').matchAsPrefix(s, close + 2)!.end;
    if (s.startsWith('stream', rest)) continue; // 스트림 객체는 건드리지 않는다
    final keys = _parseDict(s, open + 2, close).keys.toSet();
    if (keys.isEmpty) continue;
    final onlyInfo = keys.every(
        (k) => _infoKeys.contains(k) || k.startsWith('PTEX.') || k.startsWith('_'));
    if (onlyInfo && keys.any(_infoCore.contains)) {
      _fill(out, open + 2, close);
      count++;
    }
  }
  return count;
}

bool _inStream(List<_Span> spans, int i) {
  var lo = 0;
  var hi = spans.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (i < spans[mid].start) {
      hi = mid - 1;
    } else if (i >= spans[mid].end) {
      lo = mid + 1;
    } else {
      return true;
    }
  }
  return false;
}

/// 사전 여기저기에 흩어진 흔적(수정 날짜, 원본 파일 경로, 만든 프로그램)의
/// 글자 값만 공백으로 덮는다. 칸 자체는 남겨 문서 구조를 건드리지 않는다.
int _blankTraces(Uint8List out, String s, List<_Span> spans) {
  var count = 0;
  final re = RegExp(r'/(LastModified|PTEX\.FileName|Creator)\s*\(');
  for (final m in re.allMatches(s)) {
    if (_inStream(spans, m.start)) continue;
    final end = _skipLiteral(s, m.end - 1);
    if (end - 1 > m.end) {
      _fill(out, m.end, end - 1);
      count++;
    }
  }
  return count;
}

/// 편집 프로그램이 남긴 비공개 자료(`/PieceInfo`)를 끊어 내고 그 내용도 덮는다.
/// 일러스트레이터 등은 여기에 만든 사람 이름·회사·원본 파일 이름을 넣어 둔다.
int _wipePieceInfo(Uint8List out, String s, List<_Span> spans, int startXref) {
  final refRe = RegExp(r'(\d+)\s+(\d+)\s+R\b');
  final queue = <int>[];
  var count = 0;
  for (final m in RegExp(r'/PieceInfo\s*').allMatches(s)) {
    if (_inStream(spans, m.start)) continue;
    int valueEnd;
    if (s.startsWith('<<', m.end)) {
      final close = _matchDict(s, m.end);
      if (close < 0) continue;
      valueEnd = close + 2;
      for (final r in refRe.allMatches(s.substring(m.end, valueEnd))) {
        queue.add(int.parse(r.group(1)!));
      }
    } else {
      final r = refRe.matchAsPrefix(s, m.end);
      if (r == null) continue;
      valueEnd = r.end;
      queue.add(int.parse(r.group(1)!));
    }
    _fill(out, m.start, valueEnd);
    count++;
  }

  // 끊어 낸 자료가 가리키던 것들을 따라가며 덮는다. 글꼴·쪽처럼 종류가 적힌
  // 객체는 문서가 함께 쓰는 것일 수 있으므로 손대지 않는다.
  final seen = <int>{};
  while (queue.isNotEmpty && seen.length < 20000) {
    final n = queue.removeLast();
    if (!seen.add(n)) continue;
    final at = _xrefOffset(s, startXref, n);
    if (at == null) continue;
    final head = RegExp('\\s*$n\\s+\\d+\\s+obj\\s*').matchAsPrefix(s, at);
    if (head == null || !s.startsWith('<<', head.end)) continue;
    final close = _matchDict(s, head.end);
    if (close < 0) continue;
    final entries = _parseDict(s, head.end + 2, close);
    if (entries.containsKey('Type') || entries.containsKey('Subtype')) continue;
    final after = RegExp(r'\s*').matchAsPrefix(s, close + 2)!.end;
    if (s.startsWith('stream', after)) {
      for (final sp in spans) {
        if (sp.start > close) {
          if (sp.start - close < 16) _fill(out, sp.start, sp.end);
          break;
        }
      }
    } else {
      for (final r in refRe.allMatches(s.substring(head.end, close))) {
        queue.add(int.parse(r.group(1)!));
      }
      _fill(out, head.end + 2, close);
    }
  }
  return count;
}

/// 새 문서 정보를 파일 끝에 덧붙인다 (표준 "덧붙여 쓰기" 형식).
Uint8List _appendInfo(Uint8List out, _Trailer t, Map<String, String> info) {
  final size = int.tryParse(t.entries['Size'] ?? '');
  final root = t.entries['Root'];
  if (size == null || root == null) {
    throw const DocUnsupported('PDF 구조를 읽지 못해 고친 내용을 넣을 수 없어요.');
  }
  final ref = RegExp(r'^(\d+)\s+(\d+)\s+R$').firstMatch(t.entries['Info'] ?? '');
  final n = ref == null ? size : int.parse(ref.group(1)!);
  final g = ref == null ? 0 : int.parse(ref.group(2)!);
  final newSize = n >= size ? n + 1 : size;

  final sb = StringBuffer('\r\n');
  final objAt = out.length + sb.length;
  sb.write('$n $g obj\r\n<<\r\n');
  info.forEach((k, v) => sb.write('/$k $v\r\n'));
  sb.write('>>\r\nendobj\r\n');
  final xrefAt = out.length + sb.length;
  sb.write('xref\r\n$n 1\r\n');
  sb.write('${objAt.toString().padLeft(10, '0')} ${g.toString().padLeft(5, '0')} n\r\n');
  sb.write('trailer\r\n<<\r\n/Size $newSize\r\n/Root $root\r\n/Info $n $g R\r\n');
  if (t.entries['ID'] != null) sb.write('/ID ${t.entries['ID']}\r\n');
  sb.write('/Prev ${t.startXref}\r\n>>\r\nstartxref\r\n$xrefAt\r\n%%EOF\r\n');
  return (BytesBuilder()
        ..add(out)
        ..add(latin1.encode(sb.toString())))
      .toBytes();
}

/// PDF 메타데이터를 지우거나([edit]가 null) 일부만 고친다.
///
/// 제목·작성자 등이 중복으로 들어 있는 부가 정보(XMP)는 어느 경우든 지운다.
DocOutput cleanPdf(Uint8List bytes, {DocEdit? edit}) {
  _rejectEncrypted(latin1.decode(bytes));
  var out = _normalize(bytes);
  final s = latin1.decode(out);
  _rejectEncrypted(s);
  final spans = _streamSpans(s);
  final notes = <String>[];

  // 1) 부가 정보(XMP) 내용과 그것을 가리키는 참조를 덮는다.
  final xmp = _xmpStreams(s, spans);
  for (final sp in xmp) {
    _fill(out, sp.start, sp.end);
  }
  var si = 0;
  for (final m in RegExp(r'/Metadata\s+\d+\s+\d+\s+R').allMatches(s)) {
    while (si < spans.length && spans[si].end <= m.start) {
      si++;
    }
    final inStream = si < spans.length && m.start >= spans[si].start;
    if (!inStream) _fill(out, m.start, m.end);
  }
  if (xmp.isNotEmpty) notes.add('PDF 부가 정보(XMP)도 함께 지웠어요.');

  // 2) 문서 정보 사전: 옛 값을 기억해 두고 덮는다.
  final t = _trailer(s);
  if (t == null) {
    throw const DocUnsupported('PDF 구조를 읽지 못했어요.');
  }
  final span = _infoSpan(s, t);
  final old = span == null
      ? <String, String>{}
      : _parseDict(s, span.start, span.end);
  if (span != null) _fill(out, span.start, span.end);

  // 3) 문서 곳곳에 따로 남은 작성 정보(삽입된 그림의 것, 옛 사본 등)도 덮는다.
  //    고친 값 옆에 옛 이름·날짜가 숨어 남지 않게, 일부 수정일 때도 지운다.
  final extra = _blankInfoLike(out, s, spans, span) +
      _wipePieceInfo(out, s, spans, t.startXref) +
      _blankTraces(out, s, spans);
  if (extra > 0) {
    notes.add('문서 안에 따로 숨어 있던 작성 정보(삽입된 그림·편집 프로그램이 남긴 것) $extra곳도 지웠어요.');
  }

  // 4) 일부 수정: 옛 값에 고친 칸만 바꿔서 새로 적는다.
  if (edit != null) {
    final info = Map<String, String>.from(old);
    if (edit.title != null) info['Title'] = _encode(edit.title!);
    if (edit.author != null) info['Author'] = _encode(edit.author!);
    if (edit.date != null) {
      info['CreationDate'] = _pdfDate(edit.date!);
      info['ModDate'] = _pdfDate(edit.date!);
    }
    if (edit.program != null) {
      info['Creator'] = _encode(edit.program!);
      info['Producer'] = _encode(edit.program!);
    }
    out = _appendInfo(out, t, info);
  }
  return DocOutput(out, notes);
}
