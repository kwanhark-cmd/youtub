import 'dart:io';
import 'dart:typed_data';

import 'package:binugi/core/clock.dart';
import 'package:binugi/services/media_picker.dart';
import 'package:binugi/services/notification_service.dart';
import 'package:binugi/services/secret_store.dart';
import 'package:binugi/services/video_service.dart';
import 'package:binugi/services/voice_service.dart';
import 'package:binugi/state/app_state.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

int _n = 0;

/// 테스트용 앱 상태: 메모리 DB, 임시 폴더, 가짜 시계·음성·알림
Future<(AppState, Directory)> makeState({
  FakeClock? clock,
  http.Client? httpClient,
  FrameExtractor? extractor,
  SilentVoice? voice,
  SilentNotifier? notifier,
  SecretStore? secrets,
  Directory? root,
  String? dbPath,
}) async {
  sqfliteFfiInit();
  final dir = root ?? await Directory.systemTemp.createTemp('binugi_test_');
  final s = await AppState.open(
    dbFactory: databaseFactoryFfiNoIsolate,
    root: dir,
    dbPath: dbPath ?? 'file:mem${_n++}_${DateTime.now().microsecondsSinceEpoch}?mode=memory&cache=shared',
    clock: clock ?? FakeClock(DateTime(2026, 1, 1, 9)),
    voice: voice ?? SilentVoice(),
    notifier: notifier ?? SilentNotifier(),
    httpClient: httpClient ?? _NoNetwork(),
    extractor: extractor,
    secretStore: secrets ?? MemorySecretStore(),
  );
  return (s, dir);
}

/// 실수로 진짜 인터넷에 나가지 않도록 막는 HTTP
class _NoNetwork extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => throw StateError('테스트에서 실제 네트워크 호출 금지: ${request.url}');
}

/// 가짜 사진 (색이 다른 JPEG)
Uint8List fakeJpeg({int w = 2000, int h = 1500, int seed = 1}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8((seed * 40) % 255, (seed * 90) % 255, (seed * 150) % 255));
  img.fillRect(im, x1: w ~/ 4, y1: h ~/ 4, x2: w ~/ 2, y2: h ~/ 2, color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodeJpg(im, quality: 80));
}

/// 가짜 사진 고르기 (카메라 없는 환경 대체)
class FakePicker implements MediaPicker {
  final List<PickedFile> photos;
  String? video;
  String? backup;
  bool camera;
  PickException? cameraError;
  int pickCalls = 0;
  String? textFile;
  FakePicker({List<PickedFile>? photos, this.camera = false, this.cameraError, this.textFile}) : photos = photos ?? [];
  @override
  bool get hasCamera => camera;
  @override
  Future<PickedFile?> takePhoto() async {
    if (cameraError != null) throw cameraError!;
    return photos.isEmpty ? null : photos.first;
  }

  @override
  Future<List<PickedFile>> pickPhotos() async {
    pickCalls++;
    return photos;
  }

  @override
  Future<String?> takeVideo() async => video;
  @override
  Future<String?> pickVideo() async => video;
  @override
  Future<String?> pickBackupFile() async => backup;
  @override
  Future<String?> chooseSaveFolder() async => null;
  @override
  Future<String?> pickTextFile({List<String> extensions = const []}) async => textFile ?? '이름,분류\n커피 머신,판매';
}

/// 가짜 영상 장면 뽑기: 정해진 장 수만큼 JPEG 저장
class FakeExtractor implements FrameExtractor {
  final int frames;
  int calls = 0;
  FakeExtractor(this.frames);
  @override
  Future<bool> frameAt(String videoPath, int atMs, String outPath) async {
    calls++;
    final i = atMs ~/ VideoService.intervalMs;
    if (i >= frames) return false;
    await File(outPath).writeAsBytes(fakeJpeg(w: 320, h: 240, seed: i + 3));
    return true;
  }
}
