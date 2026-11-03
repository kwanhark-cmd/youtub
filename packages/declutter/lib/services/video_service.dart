import 'dart:io';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail_platform_interface.dart';
import 'package:path/path.dart' as p;

import '../core/logger.dart';
import 'paths.dart';

/// 취소 신호
class CancelToken {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// 영상에서 장면 뽑기 방법 (테스트에서 가짜로 바꿔 끼움)
abstract class FrameExtractor {
  /// [atMs] 위치의 장면을 [outPath]에 JPEG로 저장. 영상 끝을 넘으면 false.
  Future<bool> frameAt(String videoPath, int atMs, String outPath);
}

class NativeFrameExtractor implements FrameExtractor {
  final _plugin = FcNativeVideoThumbnail();
  @override
  Future<bool> frameAt(String videoPath, int atMs, String outPath) async {
    // 윈도우는 시간 지정(탐색)이 안 되어 첫 장면만 사용.
    if (atMs > 0 && Platform.isWindows) return false;
    try {
      return await _plugin.saveThumbnailToFile(
        srcFile: videoPath,
        destFile: outPath,
        width: 1568,
        height: 1568,
        format: 'jpeg',
        quality: 85,
        at: FcVideoThumbnailTime(atMs, FcVideoThumbnailTimeUnit.milliseconds),
      );
    } catch (e) {
      log.warn('영상 장면 뽑기 실패: $e');
      return false;
    }
  }
}

/// 영상에서 일정 간격으로 장면을 뽑아 냅니다. 진행률과 취소를 지원.
class VideoService {
  final AppPaths paths;
  final FrameExtractor extractor;
  VideoService(this.paths, {FrameExtractor? extractor}) : extractor = extractor ?? NativeFrameExtractor();

  static const intervalMs = 2000;
  static const maxFrames = 20;

  Future<List<String>> extractFrames(String videoPath, {void Function(double progress)? onProgress, CancelToken? cancel}) async {
    final out = <String>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < maxFrames; i++) {
      if (cancel?.cancelled ?? false) break;
      final path = p.join(paths.frames.path, 'f_${stamp}_$i.jpg');
      final ok = await extractor.frameAt(videoPath, i * intervalMs, path);
      if (!ok || !File(path).existsSync()) break;
      // 영상 끝을 넘으면 같은 장면이 반복됨 → 멈춤
      if (out.isNotEmpty && File(out.last).lengthSync() == File(path).lengthSync() && _same(File(out.last).readAsBytesSync(), File(path).readAsBytesSync())) {
        File(path).deleteSync();
        break;
      }
      out.add(path);
      onProgress?.call((i + 1) / maxFrames);
    }
    onProgress?.call(1);
    return out;
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
