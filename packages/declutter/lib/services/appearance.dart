import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../core/logger.dart';
import 'paths.dart';

/// 앱 꾸미기: 창 제목, 런처 아이콘(안드로이드), 바로가기용 아이콘 파일
class Appearance {
  static const _launcher = MethodChannel('binugi/launcher');
  static bool _windowReady = false;

  static bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// 데스크톱 창 준비 (main에서 1회)
  static Future<void> initWindow(String title) async {
    if (!isDesktop) return;
    try {
      await windowManager.ensureInitialized();
      _windowReady = true;
      await windowManager.setTitle(title);
    } catch (e) {
      log.warn('창 제목 설정 불가: $e');
    }
  }

  /// 창 제목 바로 바꾸기
  static Future<void> setTitle(String title) async {
    if (!_windowReady) return;
    try {
      await windowManager.setTitle(title);
    } catch (e) {
      log.warn('창 제목 바꾸기 실패: $e');
    }
  }

  /// 안드로이드 런처 아이콘 바꾸기 (box·house·recycle·sparkle). 다른 기기는 false.
  static Future<bool> setLauncherIcon(String name) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _launcher.invokeMethod<bool>('setIcon', {'name': name}) ?? false;
    } catch (e) {
      log.error('[앱 꾸미기] 런처 아이콘 바꾸기 실패', e);
      return false;
    }
  }

  /// 바로가기 아이콘으로 쓸 파일(PNG·ICO)을 내보내기 폴더에 저장
  static Future<Directory> exportIconFiles(AppPaths paths, Uint8List png) async {
    final dir = Directory(p.join(paths.exports.path, '아이콘'));
    await dir.create(recursive: true);
    final decoded = img.decodeImage(png)!;
    final sq = img.copyResizeCropSquare(decoded, size: 256);
    await File(p.join(dir.path, '비우기비서_아이콘.png')).writeAsBytes(img.encodePng(sq));
    await File(p.join(dir.path, '비우기비서_아이콘.ico')).writeAsBytes(img.encodeIco(sq));
    return dir;
  }
}
