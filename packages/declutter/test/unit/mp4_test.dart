import 'dart:io';
import 'dart:typed_data';

import 'package:binugi/services/mp4_writer.dart';
import 'package:binugi/services/timelapse_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../helpers.dart';

Uint8List gradientYuv(int w, int h, int seed) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgb(x, y, (x * 255 ~/ w + seed * 60) % 256, y * 255 ~/ h, (seed * 90) % 256);
    }
  }
  return rgbToI420(im);
}

bool get hasFfmpeg => Process.runSync('which', ['ffprobe']).exitCode == 0;

void main() {
  test('MP4(H.264) 파일 만들기: 구조와 프레임 수', () async {
    final dir = await Directory.systemTemp.createTemp('mp4_');
    final f = File('${dir.path}/t.mp4');
    final w = await Mp4Writer.create(f, width: 160, height: 96);
    await w.addStill(gradientYuv(160, 96, 1), 15);
    await w.addStill(gradientYuv(160, 96, 2), 15);
    await w.close();
    final b = f.readAsBytesSync();
    expect(String.fromCharCodes(b.sublist(4, 8)), 'ftyp');
    expect(String.fromCharCodes(b), contains('moov'));
    expect(String.fromCharCodes(b), contains('avcC'));
    if (hasFfmpeg) {
      final probe = Process.runSync('ffprobe', [
        '-v',
        'error',
        '-count_frames',
        '-select_streams',
        'v:0',
        '-show_entries',
        'stream=codec_name,width,height,nb_read_frames,r_frame_rate',
        '-of',
        'default=nw=1',
        f.path,
      ]);
      expect(probe.exitCode, 0, reason: probe.stderr.toString());
      final out = probe.stdout.toString();
      expect(out, contains('codec_name=h264'));
      expect(out, contains('width=160'));
      expect(out, contains('height=96'));
      expect(out, contains('nb_read_frames=30'));
      expect(out, contains('r_frame_rate=30/1'));
      // 디코딩 오류 없음 + 첫 화면 색이 맞는지 (가운데 점)
      final dec = Process.runSync('ffmpeg', ['-v', 'error', '-i', f.path, '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], stdoutEncoding: null);
      expect(dec.exitCode, 0, reason: dec.stderr.toString());
      expect(dec.stderr.toString().trim(), isEmpty);
      final rgb = dec.stdout as List<int>;
      expect(rgb.length, 160 * 96 * 3);
      final i = (48 * 160 + 80) * 3;
      expect(rgb[i + 1], closeTo(48 * 255 ~/ 96, 12), reason: '초록 값이 원본과 비슷');
    }
  });

  test('타임랩스 MP4: 세로 9:16·가로 16:9, 엔딩 크레딧 포함, 1번 앱 폴더', () async {
    final (s, _) = await makeState();
    final paths = <String>[];
    for (var i = 0; i < 2; i++) {
      paths.add((await s.savePhoto(fakeJpeg(w: 320, h: 240, seed: i))).photoPath);
    }
    final credits = Uint8List.fromList(img.encodePng(img.Image(width: 90, height: 160)));
    final v = await s.timelapse.makeMp4(paths, spot: '거실', portrait: true, creditsPng: credits, width: 144, height: 256);
    expect(v.path, contains('1번앱_타임랩스'));
    expect(v.path, endsWith('.mp4'));
    final h = await s.timelapse.makeMp4(paths, spot: '거실', portrait: false, width: 256, height: 144);
    if (hasFfmpeg) {
      for (final (file, ww, hh, frames) in [
        (v, 144, 256, 2 * TimelapseService.photoFrames + TimelapseService.creditFrames),
        (h, 256, 144, 2 * TimelapseService.photoFrames),
      ]) {
        final probe = Process.runSync('ffprobe', [
          '-v',
          'error',
          '-count_frames',
          '-select_streams',
          'v:0',
          '-show_entries',
          'stream=width,height,nb_read_frames',
          '-of',
          'csv=p=0',
          file.path,
        ]);
        expect(probe.stdout.toString().trim(), '$ww,$hh,$frames');
      }
    }
  });
}
