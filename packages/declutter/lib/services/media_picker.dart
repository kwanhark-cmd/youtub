import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/logger.dart';

/// 카메라·파일 고르기 실패 종류 (화면은 오류 대신 안내 + 다른 방법으로 자동 대체)
enum PickError { denied, noDevice, failed }

class PickException implements Exception {
  final PickError kind;
  final String detail;
  PickException(this.kind, [this.detail = '']);
  String get userMessage => switch (kind) {
    PickError.denied => '카메라 사용이 허락되지 않았어요. 사진 파일을 골라 주세요. (기기 설정 → 앱 → 권한에서 바꿀 수 있어요)',
    PickError.noDevice => '이 기기에서는 카메라를 쓸 수 없어요. 사진 파일을 골라 주세요.',
    PickError.failed => '사진을 가져오지 못했어요. 사진 파일로 다시 골라 주세요.',
  };
}

PickException _toPick(Object e) {
  if (e is PlatformException) {
    final c = e.code.toLowerCase();
    if (c.contains('denied') || c.contains('permission')) return PickException(PickError.denied, e.code);
    if (c.contains('no_available_camera') || c.contains('camera') && c.contains('unavailable')) return PickException(PickError.noDevice, e.code);
  }
  if (e is UnimplementedError || e is MissingPluginException) return PickException(PickError.noDevice, '$e');
  return PickException(PickError.failed, '$e');
}

class PickedFile {
  final String path;
  final Uint8List bytes;
  PickedFile(this.path, this.bytes);
  String get ext {
    final i = path.lastIndexOf('.');
    return i < 0 ? '.jpg' : path.substring(i).toLowerCase();
  }
}

/// 사진·영상 고르기. 카메라가 없으면 파일 넣기로 대신. 테스트에서는 가짜로 바꿔 끼움.
abstract class MediaPicker {
  bool get hasCamera;
  Future<PickedFile?> takePhoto();
  Future<List<PickedFile>> pickPhotos();
  Future<String?> takeVideo();
  Future<String?> pickVideo();
  Future<String?> pickBackupFile();

  /// 글자 파일 내용 읽기 (AI 열쇠, 구글 JSON, 제미나이 정리 파일 등)
  Future<String?> pickTextFile({List<String> extensions = const ['txt', 'csv', 'md', 'json']});
  Future<String?> chooseSaveFolder();
}

class DeviceMediaPicker implements MediaPicker {
  final _picker = ImagePicker();

  @override
  bool get hasCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<PickedFile?> _read(XFile? x) async => x == null ? null : PickedFile(x.path, await x.readAsBytes());

  /// 실패하면 [PickException] (권한 거부·카메라 없음·기타)
  @override
  Future<PickedFile?> takePhoto() async {
    if (!hasCamera) throw PickException(PickError.noDevice);
    try {
      return await _read(await _picker.pickImage(source: ImageSource.camera, maxWidth: 3000, maxHeight: 3000, imageQuality: 92));
    } catch (e) {
      log.error('[카메라] 사진 찍기 실패', e);
      throw _toPick(e);
    }
  }

  @override
  Future<List<PickedFile>> pickPhotos() async {
    try {
      final list = await _picker.pickMultiImage(maxWidth: 3000, maxHeight: 3000, imageQuality: 92, limit: 30);
      return [for (final x in list) PickedFile(x.path, await x.readAsBytes())];
    } catch (e) {
      log.error('[파일] 사진 고르기 실패', e);
      return [];
    }
  }

  @override
  Future<String?> takeVideo() async {
    if (!hasCamera) throw PickException(PickError.noDevice);
    try {
      return (await _picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 1)))?.path;
    } catch (e) {
      log.error('[카메라] 영상 찍기 실패', e);
      throw _toPick(e);
    }
  }

  @override
  Future<String?> pickVideo() async {
    try {
      return (await _picker.pickVideo(source: ImageSource.gallery))?.path;
    } catch (e) {
      log.error('[파일] 영상 고르기 실패', e);
      return null;
    }
  }

  @override
  Future<String?> pickBackupFile() async {
    try {
      final f = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: '백업 파일', extensions: ['binugi']),
        ],
      );
      return f?.path;
    } catch (e) {
      log.error('[파일] 백업 파일 고르기 실패', e);
      return null;
    }
  }

  @override
  Future<String?> pickTextFile({List<String> extensions = const ['txt', 'csv', 'md', 'json']}) async {
    try {
      final f = await openFile(
        acceptedTypeGroups: [XTypeGroup(label: '파일', extensions: extensions)],
      );
      return f == null ? null : await f.readAsString();
    } catch (e) {
      log.error('[파일] 파일 읽기 실패', e);
      return null;
    }
  }

  @override
  Future<String?> chooseSaveFolder() async {
    if (Platform.isAndroid || Platform.isIOS) return null;
    try {
      return await getDirectoryPath(confirmButtonText: '여기에 저장');
    } catch (_) {
      return null;
    }
  }
}
