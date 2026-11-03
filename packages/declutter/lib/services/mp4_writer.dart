import 'dart:io';
import 'dart:typed_data';

/// 아주 작은 MP4(H.264) 만들기 — 추가 프로그램 없이 모든 기기에서 동작.
///
/// 사진 한 장 = 화질 손실 없는 키 프레임(I_PCM) 1장 + 같은 화면을 유지하는 아주 작은 프레임(P_Skip)들.
/// 그래서 30fps 표준 영상이 되고(유튜브 업로드 가능), 용량은 사진 수에 비례합니다.
/// 가로·세로 크기는 16의 배수여야 합니다 (예: 720×1280 세로, 1280×720 가로).
class Mp4Writer {
  final int width;
  final int height;
  final int fps;
  final RandomAccessFile _f;
  final List<int> _sizes = [];
  final List<int> _sync = [];
  int _mdatStart = 0;
  int _frameNum = 0;
  int _idrId = 0;
  late final Uint8List _sps = _makeSps();
  late final Uint8List _pps = _makePps();
  late final Uint8List _skip = _makeSkipSlice();

  Mp4Writer._(this._f, this.width, this.height, this.fps);

  static Future<Mp4Writer> create(File file, {required int width, required int height, int fps = 30}) async {
    if (width % 16 != 0 || height % 16 != 0) throw ArgumentError('크기는 16의 배수여야 해요');
    final f = await file.open(mode: FileMode.write);
    final w = Mp4Writer._(f, width, height, fps);
    await f.writeFrom(_box('ftyp', [..._ascii('isom'), ..._u32(0x200), ..._ascii('isom'), ..._ascii('iso2'), ..._ascii('avc1'), ..._ascii('mp41')]));
    w._mdatStart = await f.position();
    await f.writeFrom([0, 0, 0, 0, ..._ascii('mdat')]); // 크기는 마지막에 채움
    return w;
  }

  int get _mbW => width ~/ 16;
  int get _mbH => height ~/ 16;

  /// [yuv]: I420 (Y 전체, 그다음 U 1/4, V 1/4). [frames]: 이 화면을 몇 프레임 동안 보여 줄지.
  Future<void> addStill(Uint8List yuv, int frames) async {
    if (frames < 1) frames = 1;
    _frameNum = 0;
    final idr = _makeIdrSlice(yuv);
    _idrId ^= 1;
    _sync.add(_sizes.length + 1);
    await _writeSample([idr]);
    for (var i = 1; i < frames; i++) {
      _frameNum = (_frameNum + 1) % 256;
      await _writeSample([_skipWithFrameNum()]);
    }
  }

  Future<void> _writeSample(List<Uint8List> nals) async {
    var size = 0;
    for (final n in nals) {
      final e = _escape(n);
      await _f.writeFrom(_u32(e.length));
      await _f.writeFrom(e);
      size += 4 + e.length;
    }
    _sizes.add(size);
  }

  /// 마무리: mdat 크기 채우고 moov 쓰기
  Future<void> close() async {
    final end = await _f.position();
    await _f.setPosition(_mdatStart);
    await _f.writeFrom(_u32(end - _mdatStart));
    await _f.setPosition(end);
    await _f.writeFrom(_moov(_mdatStart + 8));
    await _f.close();
  }

  // ---------- H.264 ----------
  Uint8List _makeSps() {
    final b = _Bits()
      ..u(8, 66) // Baseline
      ..u(8, 0xC0) // constraint_set0,1 (Constrained Baseline)
      ..u(8, 40) // level 4.0
      ..ue(0) // sps id
      ..ue(4) // log2_max_frame_num - 4 → 8비트
      ..ue(2) // pic_order_cnt_type 2
      ..ue(1) // max_num_ref_frames
      ..u(1, 0)
      ..ue(_mbW - 1)
      ..ue(_mbH - 1)
      ..u(1, 1) // frame_mbs_only
      ..u(1, 1) // direct_8x8_inference
      ..u(1, 0) // cropping
      ..u(1, 0) // vui
      ..trailing();
    return Uint8List.fromList([0x67, ...b.bytes]);
  }

  Uint8List _makePps() {
    final b = _Bits()
      ..ue(0)
      ..ue(0)
      ..u(1, 0) // CAVLC
      ..u(1, 0)
      ..ue(0) // slice groups
      ..ue(0)
      ..ue(0)
      ..u(1, 0)
      ..u(2, 0)
      ..se(0)
      ..se(0)
      ..se(0)
      ..u(1, 1) // deblocking_filter_control_present
      ..u(1, 0)
      ..u(1, 0)
      ..trailing();
    return Uint8List.fromList([0x68, ...b.bytes]);
  }

  Uint8List _makeIdrSlice(Uint8List yuv) {
    final b = _Bits()
      ..ue(0) // first_mb
      ..ue(7) // I (모두)
      ..ue(0) // pps
      ..u(8, 0) // frame_num
      ..ue(_idrId)
      ..u(1, 0) // no_output_of_prior_pics
      ..u(1, 0) // long_term_reference
      ..se(0) // qp delta
      ..ue(1) // deblocking 끔
      ..ue(25) // 첫 매크로블록: I_PCM
      ..align();
    final out = BytesBuilder(copy: false)
      ..addByte(0x65)
      ..add(b.bytes);
    final ySize = width * height;
    final cW = width ~/ 2;
    final cSize = ySize ~/ 4;
    final mb = Uint8List(384);
    for (var my = 0; my < _mbH; my++) {
      for (var mx = 0; mx < _mbW; mx++) {
        if (my != 0 || mx != 0) {
          out.add(const [0x0D, 0x00]); // ue(25) + 정렬 0비트
        }
        var k = 0;
        for (var y = 0; y < 16; y++) {
          final row = (my * 16 + y) * width + mx * 16;
          for (var x = 0; x < 16; x++) {
            final v = yuv[row + x];
            mb[k++] = v == 0 ? 1 : v;
          }
        }
        for (var plane = 0; plane < 2; plane++) {
          final base = ySize + plane * cSize;
          for (var y = 0; y < 8; y++) {
            final row = base + (my * 8 + y) * cW + mx * 8;
            for (var x = 0; x < 8; x++) {
              final v = yuv[row + x];
              mb[k++] = v == 0 ? 1 : v;
            }
          }
        }
        out.add(Uint8List.fromList(mb));
      }
    }
    out.addByte(0x80); // rbsp_slice_trailing_bits
    return out.takeBytes();
  }

  Uint8List _makeSkipSlice() => _skipBits(1);

  Uint8List _skipWithFrameNum() => _frameNum == 1 ? _skip : _skipBits(_frameNum);

  Uint8List _skipBits(int frameNum) {
    final b = _Bits()
      ..ue(0)
      ..ue(5) // P (모두)
      ..ue(0)
      ..u(8, frameNum)
      ..u(1, 0) // num_ref_idx_active_override
      ..u(1, 0) // ref_pic_list_modification
      ..u(1, 0) // adaptive_ref_pic_marking
      ..se(0)
      ..ue(1)
      ..ue(_mbW * _mbH) // 전부 건너뛰기 (같은 화면 유지)
      ..trailing();
    return Uint8List.fromList([0x41, ...b.bytes]);
  }

  /// 시작 코드 흉내(00 00 0x) 막기
  static Uint8List _escape(Uint8List n) {
    var zeros = 0;
    var need = false;
    for (var i = 1; i < n.length; i++) {
      final v = n[i];
      if (zeros >= 2 && v <= 3) {
        need = true;
        break;
      }
      zeros = v == 0 ? zeros + 1 : 0;
    }
    if (!need) return n;
    final out = BytesBuilder(copy: false)..addByte(n[0]);
    zeros = 0;
    for (var i = 1; i < n.length; i++) {
      final v = n[i];
      if (zeros >= 2 && v <= 3) {
        out.addByte(3);
        zeros = 0;
      }
      out.addByte(v);
      zeros = v == 0 ? zeros + 1 : 0;
    }
    return out.takeBytes();
  }

  // ---------- MP4 상자 ----------
  Uint8List _moov(int dataOffset) {
    final n = _sizes.length;
    final durMs = (n * 1000 / fps).round();
    final matrix = [..._u32(0x10000), ..._u32(0), ..._u32(0), ..._u32(0), ..._u32(0x10000), ..._u32(0), ..._u32(0), ..._u32(0), ..._u32(0x40000000)];
    final mvhd = _full('mvhd', 0, 0, [
      ..._u32(0),
      ..._u32(0),
      ..._u32(1000),
      ..._u32(durMs),
      ..._u32(0x10000),
      ..._u16(0x100),
      ...List.filled(10, 0),
      ...matrix,
      ...List.filled(24, 0),
      ..._u32(2),
    ]);
    final tkhd = _full('tkhd', 0, 3, [
      ..._u32(0),
      ..._u32(0),
      ..._u32(1),
      ..._u32(0),
      ..._u32(durMs),
      ...List.filled(8, 0),
      ..._u16(0),
      ..._u16(0),
      ..._u16(0),
      ..._u16(0),
      ...matrix,
      ..._u32(width << 16),
      ..._u32(height << 16),
    ]);
    final mdhd = _full('mdhd', 0, 0, [..._u32(0), ..._u32(0), ..._u32(fps), ..._u32(n), ..._u16(0x55C4), ..._u16(0)]);
    final hdlr = _full('hdlr', 0, 0, [..._u32(0), ..._ascii('vide'), ...List.filled(12, 0), ..._ascii('VideoHandler'), 0]);
    final vmhd = _full('vmhd', 0, 1, List.filled(8, 0));
    final dinf = _box('dinf', _full('dref', 0, 0, [..._u32(1), ..._full('url ', 0, 1, [])]));
    final avcC = _box('avcC', [1, 66, 0xC0, 40, 0xFF, 0xE1, ..._u16(_sps.length), ..._sps, 1, ..._u16(_pps.length), ..._pps]);
    final avc1 = _box('avc1', [
      ...List.filled(6, 0), ..._u16(1), // data_reference_index
      ...List.filled(16, 0),
      ..._u16(width), ..._u16(height),
      ..._u32(0x00480000), ..._u32(0x00480000), ..._u32(0), ..._u16(1),
      ...List.filled(32, 0), ..._u16(0x18), ..._u16(0xFFFF),
      ...avcC,
    ]);
    final stsd = _full('stsd', 0, 0, [..._u32(1), ...avc1]);
    final stts = _full('stts', 0, 0, [..._u32(1), ..._u32(n), ..._u32(1)]);
    final stss = _full('stss', 0, 0, [..._u32(_sync.length), for (final s in _sync) ..._u32(s)]);
    final stsc = _full('stsc', 0, 0, [..._u32(1), ..._u32(1), ..._u32(n), ..._u32(1)]);
    final stsz = _full('stsz', 0, 0, [..._u32(0), ..._u32(n), for (final s in _sizes) ..._u32(s)]);
    final stco = _full('stco', 0, 0, [..._u32(1), ..._u32(dataOffset)]);
    final stbl = _box('stbl', [...stsd, ...stts, ...stss, ...stsc, ...stsz, ...stco]);
    final minf = _box('minf', [...vmhd, ...dinf, ...stbl]);
    final mdia = _box('mdia', [...mdhd, ...hdlr, ...minf]);
    final trak = _box('trak', [...tkhd, ...mdia]);
    return _box('moov', [...mvhd, ...trak]);
  }

  static List<int> _u32(int v) => [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255];
  static List<int> _u16(int v) => [(v >> 8) & 255, v & 255];
  static List<int> _ascii(String s) => s.codeUnits;
  static Uint8List _box(String type, List<int> body) => Uint8List.fromList([..._u32(8 + body.length), ..._ascii(type), ...body]);
  static Uint8List _full(String type, int version, int flags, List<int> body) =>
      _box(type, [version, (flags >> 16) & 255, (flags >> 8) & 255, flags & 255, ...body]);
}

/// 비트 단위 쓰기 (지수 골롬 부호 포함)
class _Bits {
  final List<int> bytes = [];
  int _cur = 0;
  int _n = 0;

  void u(int bits, int v) {
    for (var i = bits - 1; i >= 0; i--) {
      _cur = (_cur << 1) | ((v >> i) & 1);
      if (++_n == 8) {
        bytes.add(_cur);
        _cur = 0;
        _n = 0;
      }
    }
  }

  void ue(int v) {
    final x = v + 1;
    final len = x.bitLength;
    u(len - 1, 0);
    u(len, x);
  }

  void se(int v) => ue(v <= 0 ? -2 * v : 2 * v - 1);

  void align() {
    while (_n != 0) {
      u(1, 0);
    }
  }

  void trailing() {
    u(1, 1);
    align();
  }
}
