import 'dart:convert';
import 'dart:typed_data';

import 'doc_types.dart';

/// 한글(hwp)과 옛 오피스(doc/xls/ppt)가 쓰는 "복합 파일" 다루기.
///
/// 문서 요약 정보(제목·작성자·날짜)는 파일 안의 작은 구역에 따로 들어 있다.
/// 그 구역만 같은 자리에 다시 써서 본문은 한 바이트도 건드리지 않는다.

const _endOfChain = 0xFFFFFFFE;
const _freeSect = 0xFFFFFFFF;
const _signature = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];

const _vtLpstr = 0x1E;
const _vtLpwstr = 0x1F;
const _vtFiletime = 0x40;

bool isCfb(Uint8List b) {
  if (b.length < 512) return false;
  for (var i = 0; i < 8; i++) {
    if (b[i] != _signature[i]) return false;
  }
  return true;
}

class _Entry {
  _Entry(this.name, this.type, this.start, this.size, this.offset);
  final String name;
  final int type; // 1 저장소, 2 스트림, 5 뿌리
  final int start;
  final int size;
  final int offset; // 디렉터리 항목의 파일 내 위치
}

class _Seg {
  const _Seg(this.offset, this.length);
  final int offset;
  final int length;
}

class _Cfb {
  _Cfb(this.data) : _bd = ByteData.sublistView(data) {
    _parse();
  }

  final Uint8List data;
  final ByteData _bd;
  late final int sectorSize;
  late final int miniSize;
  late final int cutoff;
  final List<int> _fat = [];
  final List<int> _miniFat = [];
  final List<_Entry> entries = [];
  List<int> _miniStreamSectors = const [];

  int _u32(int o) => _bd.getUint32(o, Endian.little);
  int _u16(int o) => _bd.getUint16(o, Endian.little);
  int _sectorOffset(int n) => (n + 1) * sectorSize;

  Never _bad() => throw const DocUnsupported('문서 파일 구조를 읽을 수 없어요 (손상된 파일일 수 있어요).');

  List<int> _chain(int start, List<int> table) {
    final out = <int>[];
    var s = start;
    while (s != _endOfChain && s != _freeSect) {
      if (s >= table.length || out.length > table.length) _bad();
      out.add(s);
      s = table[s];
    }
    return out;
  }

  void _parse() {
    sectorSize = 1 << _u16(0x1E);
    miniSize = 1 << _u16(0x20);
    cutoff = _u32(0x38);
    if (sectorSize != 512 && sectorSize != 4096) _bad();
    final perSector = sectorSize ~/ 4;

    // FAT 구역 목록(DIFAT)
    final fatSectors = <int>[];
    for (var i = 0; i < 109; i++) {
      final s = _u32(0x4C + i * 4);
      if (s != _freeSect && s != _endOfChain) fatSectors.add(s);
    }
    var difat = _u32(0x44);
    var guard = 0;
    while (difat != _endOfChain && difat != _freeSect) {
      if (guard++ > 100000) _bad();
      final base = _sectorOffset(difat);
      if (base + sectorSize > data.length) _bad();
      for (var i = 0; i < perSector - 1; i++) {
        final s = _u32(base + i * 4);
        if (s != _freeSect && s != _endOfChain) fatSectors.add(s);
      }
      difat = _u32(base + (perSector - 1) * 4);
    }
    for (final fs in fatSectors) {
      final base = _sectorOffset(fs);
      if (base + sectorSize > data.length) _bad();
      for (var i = 0; i < perSector; i++) {
        _fat.add(_u32(base + i * 4));
      }
    }

    // 디렉터리
    for (final s in _chain(_u32(0x30), _fat)) {
      final base = _sectorOffset(s);
      if (base + sectorSize > data.length) _bad();
      for (var o = base; o < base + sectorSize; o += 128) {
        final nameLen = _u16(o + 0x40);
        final type = data[o + 0x42];
        var name = '';
        if (nameLen >= 2 && nameLen <= 64) {
          final units = <int>[];
          for (var k = 0; k < nameLen - 2; k += 2) {
            units.add(_u16(o + k));
          }
          name = String.fromCharCodes(units);
        }
        entries.add(_Entry(name, type, _u32(o + 0x74), _u32(o + 0x78), o));
      }
    }
    if (entries.isEmpty || entries.first.type != 5) _bad();

    // 작은 스트림 저장소와 그 FAT
    _miniStreamSectors = _chain(entries.first.start, _fat);
    for (final s in _chain(_u32(0x3C), _fat)) {
      final base = _sectorOffset(s);
      if (base + sectorSize > data.length) _bad();
      for (var i = 0; i < perSector; i++) {
        _miniFat.add(_u32(base + i * 4));
      }
    }
  }

  /// 스트림이 차지한 자리(할당된 구역 전체)를 파일 위치로 돌려준다.
  List<_Seg> segments(_Entry e) {
    final segs = <_Seg>[];
    if (e.size < cutoff) {
      for (final m in _chain(e.start, _miniFat)) {
        final pos = m * miniSize;
        final idx = pos ~/ sectorSize;
        if (idx >= _miniStreamSectors.length) _bad();
        segs.add(_Seg(
            _sectorOffset(_miniStreamSectors[idx]) + pos % sectorSize, miniSize));
      }
    } else {
      for (final s in _chain(e.start, _fat)) {
        segs.add(_Seg(_sectorOffset(s), sectorSize));
      }
    }
    for (final s in segs) {
      if (s.offset + s.length > data.length) _bad();
    }
    return segs;
  }

  Uint8List read(_Entry e) {
    final out = BytesBuilder();
    for (final s in segments(e)) {
      out.add(Uint8List.sublistView(data, s.offset, s.offset + s.length));
    }
    final all = out.toBytes();
    return Uint8List.sublistView(all, 0, e.size.clamp(0, all.length));
  }

  /// 같은 자리에 새 내용을 쓴다. 남는 자리는 0으로 채운다.
  void write(_Entry e, Uint8List content) {
    var p = 0;
    for (final s in segments(e)) {
      for (var i = 0; i < s.length; i++) {
        data[s.offset + i] = p < content.length ? content[p] : 0;
        p++;
      }
    }
    _bd.setUint32(e.offset + 0x78, content.length, Endian.little);
    _bd.setUint32(e.offset + 0x7C, 0, Endian.little);
  }

  /// 새 내용이 들어갈 수 있는 최대 크기.
  int capacity(_Entry e) {
    final cap = segments(e).fold<int>(0, (a, s) => a + s.length);
    // 작은 스트림은 기준 크기를 넘으면 저장 방식이 바뀌므로 넘기지 않는다.
    return e.size < cutoff ? cap.clamp(0, cutoff - 1) : cap;
  }

  Iterable<_Entry> get summaryStreams => entries.where((e) =>
      e.type == 2 &&
      e.name.startsWith('\u0005') &&
      e.name.contains('SummaryInformation'));
}

// ───────────────────────── 속성 묶음(요약 정보) ─────────────────────────

class _Prop {
  _Prop(this.id, this.raw);
  final int id;
  Uint8List raw; // 종류(4바이트) + 값
  int get type => raw.length >= 4
      ? ByteData.sublistView(raw).getUint32(0, Endian.little) & 0xFFFF
      : 0;
}

class _Section {
  _Section(this.fmtid, this.props);
  final Uint8List fmtid;
  final List<_Prop> props;
}

class _PropSet {
  _PropSet(this.header, this.sections);
  final Uint8List header; // 앞 28바이트
  final List<_Section> sections;

  static _PropSet? parse(Uint8List s) {
    if (s.length < 48) return null;
    final bd = ByteData.sublistView(s);
    if (bd.getUint16(0, Endian.little) != 0xFFFE) return null;
    final n = bd.getUint32(24, Endian.little);
    if (n < 1 || n > 8 || 28 + n * 20 > s.length) return null;
    final offs = [
      for (var i = 0; i < n; i++) bd.getUint32(28 + i * 20 + 16, Endian.little)
    ];
    final sections = <_Section>[];
    for (var i = 0; i < n; i++) {
      final off = offs[i];
      if (off + 8 > s.length) return null;
      final declared = bd.getUint32(off, Endian.little);
      var end = off + declared;
      final limit = i + 1 < n ? offs[i + 1] : s.length;
      if (end > limit || declared < 8) end = limit;
      final count = bd.getUint32(off + 4, Endian.little);
      if (count > 4096 || off + 8 + count * 8 > end) return null;
      final ids = <int>[];
      final pos = <int>[];
      for (var k = 0; k < count; k++) {
        ids.add(bd.getUint32(off + 8 + k * 8, Endian.little));
        pos.add(off + bd.getUint32(off + 12 + k * 8, Endian.little));
      }
      final sorted = [...pos, end]..sort();
      final props = <_Prop>[];
      for (var k = 0; k < count; k++) {
        if (pos[k] < off + 8 + count * 8 || pos[k] > end) return null;
        final next = sorted.firstWhere((p) => p > pos[k], orElse: () => end);
        props.add(_Prop(ids[k], Uint8List.fromList(s.sublist(pos[k], next))));
      }
      sections
          .add(_Section(Uint8List.fromList(s.sublist(28 + i * 20, 44 + i * 20)), props));
    }
    return _PropSet(Uint8List.fromList(s.sublist(0, 28)), sections);
  }

  Uint8List build() {
    final bodies = <Uint8List>[];
    for (final sec in sections) {
      final b = BytesBuilder();
      final table = ByteData(8 + sec.props.length * 8);
      var off = table.lengthInBytes;
      final values = BytesBuilder();
      for (var k = 0; k < sec.props.length; k++) {
        final raw = sec.props[k].raw;
        final padded = (raw.length + 3) & ~3;
        table.setUint32(8 + k * 8, sec.props[k].id, Endian.little);
        table.setUint32(12 + k * 8, off, Endian.little);
        values.add(raw);
        values.add(Uint8List(padded - raw.length));
        off += padded;
      }
      table.setUint32(0, off, Endian.little);
      table.setUint32(4, sec.props.length, Endian.little);
      b.add(table.buffer.asUint8List());
      b.add(values.toBytes());
      bodies.add(b.toBytes());
    }
    final out = BytesBuilder()..add(header);
    var off = 28 + sections.length * 20;
    for (var i = 0; i < sections.length; i++) {
      final o = ByteData(4)..setUint32(0, off, Endian.little);
      out.add(sections[i].fmtid.sublist(0, 16));
      out.add(o.buffer.asUint8List());
      off += bodies[i].length;
    }
    for (final b in bodies) {
      out.add(b);
    }
    return out.toBytes();
  }
}

int _codePage(_Section sec) {
  for (final p in sec.props) {
    if (p.id == 1 && p.raw.length >= 6) {
      return ByteData.sublistView(p.raw).getUint16(4, Endian.little);
    }
  }
  return 0;
}

String _readString(_Prop p, int codePage) {
  final bd = ByteData.sublistView(p.raw);
  if (p.raw.length < 8) return '';
  final count = bd.getUint32(4, Endian.little);
  if (p.type == _vtLpwstr) {
    final units = <int>[];
    for (var i = 0; i < count && 8 + i * 2 + 1 < p.raw.length; i++) {
      final u = bd.getUint16(8 + i * 2, Endian.little);
      if (u == 0) break;
      units.add(u);
    }
    return String.fromCharCodes(units);
  }
  final end = (8 + count).clamp(8, p.raw.length);
  var bytes = p.raw.sublist(8, end);
  final nul = bytes.indexOf(0);
  if (nul >= 0) bytes = bytes.sublist(0, nul);
  if (codePage == 65001) return utf8.decode(bytes, allowMalformed: true);
  if (codePage == 1200) {
    return String.fromCharCodes(Uint16List.sublistView(
        Uint8List.fromList(bytes), 0, bytes.length ~/ 2));
  }
  return bytes.every((b) => b < 0x80)
      ? ascii.decode(bytes)
      : '(이 앱에서 표시할 수 없는 글자, ${bytes.length}바이트)';
}

Uint8List _wide(String v) {
  final units = v.codeUnits;
  final raw = ByteData(8 + (units.length + 1) * 2);
  raw.setUint32(0, _vtLpwstr, Endian.little);
  raw.setUint32(4, units.length + 1, Endian.little);
  for (var i = 0; i < units.length; i++) {
    raw.setUint16(8 + i * 2, units[i], Endian.little);
  }
  return raw.buffer.asUint8List();
}

Uint8List _narrow(String v, int codePage) {
  final bytes = codePage == 65001
      ? utf8.encode(v)
      : v.codeUnits.map((c) => c < 0x80 ? c : 0x3F).toList();
  final raw = ByteData(8 + bytes.length + 1);
  raw.setUint32(0, _vtLpstr, Endian.little);
  raw.setUint32(4, bytes.length + 1, Endian.little);
  for (var i = 0; i < bytes.length; i++) {
    raw.setUint8(8 + i, bytes[i]);
  }
  return raw.buffer.asUint8List();
}

Uint8List _filetime(DateTime? d) {
  final raw = ByteData(12);
  raw.setUint32(0, _vtFiletime, Endian.little);
  if (d != null) {
    final ticks = BigInt.from(d.toUtc().microsecondsSinceEpoch) * BigInt.from(10) +
        BigInt.parse('116444736000000000');
    raw.setUint32(4, (ticks & BigInt.from(0xFFFFFFFF)).toInt(), Endian.little);
    raw.setUint32(8, (ticks >> 32).toInt(), Endian.little);
  }
  return raw.buffer.asUint8List();
}

DateTime? _readFiletime(_Prop p) {
  if (p.raw.length < 12) return null;
  final bd = ByteData.sublistView(p.raw);
  final ticks = (BigInt.from(bd.getUint32(8, Endian.little)) << 32) |
      BigInt.from(bd.getUint32(4, Endian.little));
  if (ticks == BigInt.zero) return null;
  final micros =
      (ticks - BigInt.parse('116444736000000000')) ~/ BigInt.from(10);
  return DateTime.fromMicrosecondsSinceEpoch(micros.toInt(), isUtc: true);
}

const _summaryLabels = {
  2: '제목',
  3: '주제',
  4: '작성자',
  5: '키워드',
  6: '설명',
  8: '마지막 저장한 사람',
  9: '버전 정보',
  11: '마지막 인쇄',
  12: '만든 날짜',
  13: '수정한 날짜',
  18: '프로그램',
  20: '날짜 글자',
};
const _docSummaryLabels = {14: '관리자', 15: '회사'};

bool _isMainSummary(String name) => !name.contains('Document');

/// hwp/doc/xls/ppt 메타데이터를 읽는다.
Map<String, String> readCfbMeta(Uint8List bytes) {
  final cfb = _Cfb(Uint8List.fromList(bytes));
  final out = <String, String>{};
  for (final e in cfb.summaryStreams) {
    final ps = _PropSet.parse(cfb.read(e));
    if (ps == null || ps.sections.isEmpty) continue;
    final sec = ps.sections.first;
    final cp = _codePage(sec);
    final labels = _isMainSummary(e.name) ? _summaryLabels : _docSummaryLabels;
    for (final p in sec.props) {
      final label = labels[p.id];
      if (label == null) continue;
      if (p.type == _vtLpwstr || p.type == _vtLpstr) {
        final v = _readString(p, cp).trim();
        if (v.isNotEmpty) out[label] = v;
      } else if (p.type == _vtFiletime) {
        final d = _readFiletime(p);
        if (d != null) out[label] = showDate(d);
      }
    }
  }
  return out;
}

/// hwp/doc/xls/ppt 메타데이터를 지우거나([edit]가 null) 일부만 고친다.
DocOutput cleanCfb(Uint8List bytes, {DocEdit? edit}) {
  final cfb = _Cfb(Uint8List.fromList(bytes));
  final notes = <String>[];
  final streams = cfb.summaryStreams.toList();
  if (streams.isEmpty) {
    return DocOutput(cfb.data, const ['이 문서에는 요약 정보(제목·작성자 등)가 들어 있지 않아요.']);
  }
  for (final e in streams) {
    final ps = _PropSet.parse(cfb.read(e));
    if (ps == null) {
      throw const DocUnsupported('문서 요약 정보의 형식을 알 수 없어 처리하지 못했어요.');
    }
    final main = _isMainSummary(e.name);
    if (edit != null && !main) continue; // 일부 수정은 주 요약 정보만

    final edited = <_Prop, String>{}; // 넘칠 때 줄일 수 있는 글자 칸
    for (var si = 0; si < ps.sections.length; si++) {
      final sec = ps.sections[si];
      final cp = _codePage(sec);
      final wide = sec.props.any((p) => p.type == _vtLpwstr) ||
          !sec.props.any((p) => p.type == _vtLpstr);
      Uint8List str(String v) => wide ? _wide(v) : _narrow(v, cp);

      if (edit == null) {
        for (final p in sec.props) {
          if (p.id < 2) continue;
          if (p.type == _vtLpwstr) p.raw = _wide('');
          if (p.type == _vtLpstr) p.raw = _narrow('', cp);
          if (p.type == _vtFiletime) p.raw = _filetime(null);
        }
        continue;
      }
      if (si != 0) continue;

      void setString(int id, String v) {
        var p = sec.props.where((x) => x.id == id).firstOrNull;
        if (p == null) {
          p = _Prop(id, str(v));
          sec.props.add(p);
        } else {
          p.raw = (p.type == _vtLpstr) ? _narrow(v, cp) : _wide(v);
        }
        edited[p] = v;
        if (p.type == _vtLpstr && cp != 65001 && v.codeUnits.any((c) => c >= 0x80)) {
          notes.add('이 옛 형식 문서는 한글 글자를 새로 적을 수 없어 "?"로 들어갔어요. 영문·숫자로 적어 주세요.');
        }
      }

      void setDate(int id, DateTime d) {
        final p = sec.props.where((x) => x.id == id).firstOrNull;
        if (p == null) {
          sec.props.add(_Prop(id, _filetime(d)));
        } else if (p.type == _vtFiletime) {
          p.raw = _filetime(d);
        }
      }

      if (edit.title != null) setString(2, edit.title!);
      if (edit.author != null) {
        setString(4, edit.author!);
        setString(8, edit.author!);
      }
      if (edit.program != null) {
        // 프로그램 이름 칸(18)이나 한글의 버전 정보 칸(9)이 있을 때만 바꾼다.
        for (final id in const [18, 9]) {
          final p = sec.props.where((x) => x.id == id).firstOrNull;
          if (p != null && (p.type == _vtLpwstr || p.type == _vtLpstr)) {
            setString(id, edit.program!);
          }
        }
      }
      if (edit.date != null) {
        setDate(12, edit.date!);
        setDate(13, edit.date!);
        final ds = sec.props.where((x) => x.id == 20).firstOrNull;
        if (ds != null && ds.type == _vtLpwstr) {
          ds.raw = _wide(koreanDateString(edit.date!));
        }
      }
    }

    // 원래 자리보다 커지면 고친 글자를 줄여서 맞춘다.
    final cap = cfb.capacity(e);
    var built = ps.build();
    var cut = false;
    while (built.length > cap) {
      final target = edited.entries
          .where((x) => x.value.isNotEmpty)
          .fold<MapEntry<_Prop, String>?>(
              null, (a, b) => a == null || b.value.length > a.value.length ? b : a);
      if (target == null) {
        throw const DocUnsupported('이 문서는 여유 공간이 없어 고친 내용을 넣을 수 없어요. "전부 지우기"는 가능해요.');
      }
      final shorter = target.value.substring(0, target.value.length - 1);
      edited[target.key] = shorter;
      target.key.raw = target.key.type == _vtLpstr
          ? _narrow(shorter, _codePage(ps.sections.first))
          : _wide(shorter);
      cut = true;
      built = ps.build();
    }
    if (cut) {
      notes.add('이 형식(hwp 등)은 문서 안의 정해진 자리에만 쓸 수 있어, 길이가 넘친 글자를 줄였어요: '
          '${edited.values.where((v) => v.isNotEmpty).join(' / ')}');
    }
    // 원래보다 작아지면 0으로 채워 크기를 지킨다. 크기가 기준 아래로 내려가면
    // 파일 안의 저장 방식이 달라져 다른 프로그램이 읽지 못한다.
    if (built.length < e.size) {
      built = Uint8List(e.size)..setRange(0, built.length, built);
    }
    cfb.write(e, built);
  }
  const office = {'WordDocument', 'Workbook', 'Book', 'PowerPoint Document'};
  if (cfb.entries.any((e) => office.contains(e.name))) {
    notes.add('옛 형식(doc·xls·ppt)은 요약 정보만 처리해요. 본문 속 변경 기록까지 지우려면 '
        'docx 등 새 형식으로 저장한 뒤 다시 지워 주세요.');
  }
  return DocOutput(cfb.data, notes);
}
