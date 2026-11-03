import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/models.dart';
import '../data/repository.dart';
import 'paths.dart';

/// 앱 용량 보기와 사진 정리
class StorageService {
  final AppPaths paths;
  final Repository repo;
  StorageService(this.paths, this.repo);

  static int dirSize(Directory d) {
    if (!d.existsSync()) return 0;
    var n = 0;
    for (final e in d.listSync(recursive: true, followLinks: false)) {
      if (e is File) n += e.lengthSync();
    }
    return n;
  }

  /// (전체, 사진·원본)
  (int, int) usage() => (dirSize(paths.root), dirSize(Directory(p.join(paths.root.path, '사진'))) + dirSize(Directory(p.join(paths.root.path, '원본'))));

  /// 정리 대상: 판매 완료·폐기 완료이고 사연이 없는 물건의 큰 사진(작은 썸네일은 남김)
  Future<List<Item>> cleanupTargets(int userId) async => (await repo.items(
    userId,
    includePractice: true,
  )).where((i) => i.isDone && i.story.trim().isEmpty && !i.digitalKeep && i.photoPath != null && i.photoPath != i.thumbPath).toList();

  /// 정리하고 줄인 용량(바이트)을 돌려줌
  Future<int> cleanupDonePhotos(int userId) async {
    var freed = 0;
    for (final it in await cleanupTargets(userId)) {
      for (final rel in [it.photoPath, it.originalPath]) {
        if (rel == null || rel == it.thumbPath) continue;
        final f = File(paths.abs(rel));
        if (f.existsSync()) {
          freed += f.lengthSync();
          f.deleteSync();
        }
      }
      it.photoPath = it.thumbPath;
      it.originalPath = null;
      await repo.updateItem(it);
    }
    return freed;
  }
}

String bytesKo(int b) {
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)}KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)}MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)}GB';
}
