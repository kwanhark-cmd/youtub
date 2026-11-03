import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../theme/app_theme.dart';
import 'paths.dart';

class SavedPhoto {
  final String photoPath; // 앱 폴더 기준 상대 경로
  final String thumbPath;
  final String? originalPath;
  final int width;
  final int height;
  SavedPhoto(this.photoPath, this.thumbPath, this.originalPath, this.width, this.height);
}

class _Resized {
  final Uint8List photo;
  final Uint8List thumb;
  final int w;
  final int h;
  _Resized(this.photo, this.thumb, this.w, this.h);
}

_Resized _resize(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('사진을 읽을 수 없어요');
  final oriented = img.bakeOrientation(decoded);
  img.Image fit(img.Image s, int maxSide) {
    if (s.width <= maxSide && s.height <= maxSide) return s;
    return s.width >= s.height ? img.copyResize(s, width: maxSide) : img.copyResize(s, height: maxSide);
  }

  final photo = fit(oriented, AppSizes.photoMaxSide);
  final thumb = fit(photo, AppSizes.thumb.toInt());
  return _Resized(Uint8List.fromList(img.encodeJpg(photo, quality: 85)), Uint8List.fromList(img.encodeJpg(thumb, quality: 75)), photo.width, photo.height);
}

/// 사진을 줄여서 저장 (메모리·저장공간 절약). 원본은 선택 시에만 보관.
class ImageService {
  final AppPaths paths;
  ImageService(this.paths);

  int _seq = 0;
  String _name(String prefix) => '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_seq++}.jpg';

  Future<SavedPhoto> save(Uint8List bytes, {bool keepOriginal = false, String? originalExt}) async {
    final r = await Isolate.run(() => _resize(bytes));
    final name = _name('p');
    final photo = File(p.join(paths.photos.path, name));
    final thumb = File(p.join(paths.thumbs.path, name));
    await photo.writeAsBytes(r.photo);
    await thumb.writeAsBytes(r.thumb);
    String? orig;
    if (keepOriginal) {
      final o = File(p.join(paths.originals.path, '${p.basenameWithoutExtension(name)}${originalExt ?? '.jpg'}'));
      await o.writeAsBytes(bytes);
      orig = paths.rel(o.path);
    }
    return SavedPhoto(paths.rel(photo.path), paths.rel(thumb.path), orig, r.w, r.h);
  }

  Future<Uint8List> readPhoto(String rel) => File(paths.abs(rel)).readAsBytes();

  /// 저장된 사진의 크기 (비용 계산용)
  Future<(int, int)> sizeOf(String rel) async {
    final bytes = await readPhoto(rel);
    final d = await Isolate.run(() => img.decodeJpg(bytes));
    return (d?.width ?? AppSizes.photoMaxSide, d?.height ?? AppSizes.photoMaxSide);
  }
}
