import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'mp4_writer.dart';
import 'paths.dart';

/// 같은 자리에서 찍은 사진을 이어 움직이는 그림(GIF)으로 만듭니다. 마지막에 엔딩 크레딧.
class TimelapseService {
  final AppPaths paths;
  TimelapseService(this.paths);

  static Uint8List _build(List<Uint8List> frames, Uint8List? credits, int side) {
    final anim = img.Image(width: side, height: side ~/ 4 * 3, numChannels: 3);
    img.Image? first;
    img.Image fitFrame(Uint8List b) {
      final d = img.decodeImage(b)!;
      final f = img.copyResizeCropSquare(d, size: side);
      return img.copyCrop(f, x: 0, y: (side - side ~/ 4 * 3) ~/ 2, width: side, height: side ~/ 4 * 3);
    }

    for (final b in frames) {
      final f = fitFrame(b)..frameDuration = 700;
      if (first == null) {
        first = f;
      } else {
        first.addFrame(f);
      }
    }
    if (credits != null) {
      final c = img.copyResize(img.decodeImage(credits)!, width: side, height: side ~/ 4 * 3)..frameDuration = 2500;
      if (first == null) {
        first = c;
      } else {
        first.addFrame(c);
      }
    }
    return img.encodeGif(first ?? anim, repeat: 0);
  }

  /// [creditsPng]: 화면에서 그린 엔딩 크레딧 그림(선택)
  Future<File> makeGif(List<String> photoPaths, {Uint8List? creditsPng, required String spot, int side = 480}) async {
    if (photoPaths.isEmpty) throw ArgumentError('사진이 없어요');
    final frames = <Uint8List>[for (final path in photoPaths) await File(paths.abs(path)).readAsBytes()];
    final gif = await Isolate.run(() => _build(frames, creditsPng, side));
    final safe = spot.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final f = File(p.join(paths.exportTimelapse.path, '타임랩스_${safe}_${DateTime.now().millisecondsSinceEpoch}.gif'));
    await f.writeAsBytes(gif);
    return f;
  }

  // ---------- MP4 (유튜브 업로드용) ----------
  static const photoFrames = 24; // 사진 한 장 0.8초 (30fps)
  static const creditFrames = 90; // 엔딩 크레딧 3초

  /// 세로(9:16, 720×1280) 또는 가로(16:9, 1280×720) MP4. 엔딩 크레딧 그림을 마지막에 붙입니다.
  Future<File> makeMp4(List<String> photoPaths, {required String spot, required bool portrait, Uint8List? creditsPng, int? width, int? height}) async {
    if (photoPaths.isEmpty) throw ArgumentError('사진이 없어요');
    final w = width ?? (portrait ? 720 : 1280);
    final h = height ?? (portrait ? 1280 : 720);
    final frames = <Uint8List>[for (final path in photoPaths) await File(paths.abs(path)).readAsBytes()];
    final safe = spot.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final out = File(p.join(paths.exportTimelapse.path, '타임랩스_${safe}_${portrait ? '세로' : '가로'}_${DateTime.now().millisecondsSinceEpoch}.mp4'));
    // 사진 변환·영상 만들기는 화면이 멈추지 않게 별도 작업으로
    await Isolate.run(() async {
      final writer = await Mp4Writer.create(out, width: w, height: h);
      for (final b in frames) {
        await writer.addStill(rgbToI420(fitFrame(img.decodeImage(b)!, w, h)), photoFrames);
      }
      if (creditsPng != null) {
        final c = img.decodeImage(creditsPng)!;
        await writer.addStill(rgbToI420(fitFrame(c, w, h)), creditFrames);
      }
      await writer.close();
    });
    return out;
  }
}

/// 사진을 영상 크기에 맞춤: 사진 전체가 보이게 가운데 두고, 빈 곳은 흐리게 확대한 사진으로 채움
img.Image fitFrame(img.Image src, int w, int h) {
  final bg = img.copyResize(img.copyResizeCropSquare(src, size: 48), width: w, height: h, interpolation: img.Interpolation.average);
  img.adjustColor(bg, brightness: 0.55);
  final scale = (w / src.width) < (h / src.height) ? w / src.width : h / src.height;
  final fw = (src.width * scale).round().clamp(1, w);
  final fh = (src.height * scale).round().clamp(1, h);
  final fg = img.copyResize(src, width: fw, height: fh, interpolation: img.Interpolation.average);
  img.compositeImage(bg, fg, dstX: (w - fw) ~/ 2, dstY: (h - fh) ~/ 2);
  return bg;
}

/// RGB 그림 → I420(YUV 4:2:0, BT.601 제한 범위)
Uint8List rgbToI420(img.Image im) {
  final w = im.width, h = im.height;
  final out = Uint8List(w * h + (w * h ~/ 2));
  final cw = w ~/ 2;
  final uOff = w * h, vOff = w * h + (w * h ~/ 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final px = im.getPixel(x, y);
      final r = px.r.toInt(), g = px.g.toInt(), b = px.b.toInt();
      out[y * w + x] = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
    }
  }
  for (var y = 0; y < h ~/ 2; y++) {
    for (var x = 0; x < cw; x++) {
      var r = 0, g = 0, b = 0;
      for (final (dx, dy) in const [(0, 0), (1, 0), (0, 1), (1, 1)]) {
        final px = im.getPixel(x * 2 + dx, y * 2 + dy);
        r += px.r.toInt();
        g += px.g.toInt();
        b += px.b.toInt();
      }
      r >>= 2;
      g >>= 2;
      b >>= 2;
      out[uOff + y * cw + x] = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
      out[vOff + y * cw + x] = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
    }
  }
  return out;
}
