import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as ip;

import 'photo_chooser.dart';
import 'photo_library.dart';

/// 고른 사진 한 장.
class PickedPhoto {
  const PickedPhoto(
      {required this.name, required this.path, required this.read});

  /// 원래 파일 이름.
  final String name;

  /// 앱이 받아 둔 사본의 경로 (미리보기용). 없을 수 있다.
  final String? path;

  /// 사진 바이트를 읽는다.
  final Future<Uint8List> Function() read;
}

/// 사진을 고르는 방법. 화면 테스트에서는 가짜로 바꿔 끼운다.
typedef PickPhotos = Future<List<PickedPhoto>> Function(
    BuildContext context, PhotoLibrary library,
    {required bool multiple});

/// 고를 수 있는 사진 확장자.
const photoExtensions = [
  'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'tif', 'tiff', 'heic', 'heif', //
];

/// 한 가지 고르기 창으로 사진을 고르는 방법 (파일 창·사진 고르기 창).
typedef PickWith = Future<List<PickedPhoto>> Function({required bool multiple});

/// 사진을 원본 그대로(위치 정보 포함) 받아 온다.
///
/// 안드로이드에서는 시스템 고르기 창(포토 피커·갤러리 고르기·파일 고르기 창)을 쓰지 않는다.
/// 폰마다 어느 창이 뜨는지 다르고, 그 창들은 사진 속 촬영 위치를 0으로 덮어 넘겨주기도
/// 한다 (삼성 One UI 에서 파일 고르기 창으로도 위치가 가려진 것을 확인). 대신 사진 보기
/// 권한과 사진 위치 정보 접근 권한을 받아, 앱 안의 고르기 화면([PhotoChooserPage])에서
/// 폰의 사진 보관함을 직접 보여 주고 원본(setRequireOriginal)을 읽는다.
/// 사진 보기를 허용하지 않으면 예전처럼 파일 고르기 창으로 고른다.
Future<List<PickedPhoto>> pickOriginalPhotos(
        BuildContext context, PhotoLibrary library,
        {required bool multiple}) =>
    pickPhotosVia(
      context,
      library,
      multiple: multiple,
      android: !kIsWeb && Platform.isAndroid,
      fileWindow: pickWithFileWindow,
      gallery: pickWithImagePicker,
    );

/// [pickOriginalPhotos]의 몸통. 테스트에서 안드로이드인 척하고 부를 수 있다.
@visibleForTesting
Future<List<PickedPhoto>> pickPhotosVia(
  BuildContext context,
  PhotoLibrary library, {
  required bool multiple,
  required bool android,
  required PickWith fileWindow,
  required PickWith gallery,
}) async {
  if (!android) return gallery(multiple: multiple);
  final r = await Navigator.of(context).push<ChooserResult>(
    MaterialPageRoute(
      builder: (_) => PhotoChooserPage(library: library, multiple: multiple),
    ),
  );
  if (r == null) return const [];
  if (r.useFileWindow) return fileWindow(multiple: multiple);
  return [
    for (final p in r.photos)
      PickedPhoto(
        name: await p.name(),
        path: null,
        read: () async {
          final b = await p.original();
          if (b == null) throw '사진 원본을 읽지 못했어요';
          return b;
        },
      ),
  ];
}

/// 안드로이드 파일 고르기 창(ACTION_OPEN_DOCUMENT). 사진 보기를 허용하지 않았을 때만 쓴다.
Future<List<PickedPhoto>> pickWithFileWindow({required bool multiple}) async {
  final List<fp.PlatformFile> files;
  if (multiple) {
    files = await fp.FilePicker.pickFiles(
        type: fp.FileType.custom, allowedExtensions: photoExtensions);
  } else {
    final one = await fp.FilePicker.pickFile(
        type: fp.FileType.custom, allowedExtensions: photoExtensions);
    files = [if (one != null) one];
  }
  return [
    for (final f in files)
      PickedPhoto(name: f.name, path: f.path, read: f.readAsBytes),
  ];
}

/// 안드로이드 밖의 기기: 예전처럼 사진 고르기 창.
Future<List<PickedPhoto>> pickWithImagePicker({required bool multiple}) async {
  final picker = ip.ImagePicker();
  final List<ip.XFile> files;
  if (multiple) {
    files = await picker.pickMultiImage();
  } else {
    final one = await picker.pickImage(source: ip.ImageSource.gallery);
    files = [if (one != null) one];
  }
  return [
    for (final f in files)
      PickedPhoto(name: f.name, path: f.path, read: f.readAsBytes),
  ];
}

/// [GpsHiddenNotice]를 보여 주는 화면.
enum GpsNoticeKind { edit, clean, stamp }

/// 폰이 위치를 가린 채 사진을 넘겨줬을 때 결과 목록 위에 보여 주는 안내.
class GpsHiddenNotice extends StatelessWidget {
  const GpsHiddenNotice({
    super.key,
    required this.count,
    required this.library,
    this.kind = GpsNoticeKind.edit,
  });

  /// 위치가 가려진 채 받은 사진 수.
  final int count;
  final PhotoLibrary library;

  /// 어느 화면의 안내인지 (무엇이 달라지는지 설명이 다르다).
  final GpsNoticeKind kind;

  Future<void> _fix(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    var a = await library.access();
    var loc = await library.canReadLocation();
    if (a != LibraryAccess.full || !loc) {
      a = await library.requestAccess();
      loc = await library.canReadLocation();
    }
    if (a == LibraryAccess.full && loc) {
      messenger.showSnackBar(
          const SnackBar(content: Text('허용돼 있어요. 사진을 다시 골라 주세요')));
      return;
    }
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: const Text('설정의 "권한 > 사진 및 동영상"에서 "모두 허용"을 고른 뒤, 사진을 다시 골라 주세요'),
      action: SnackBarAction(label: '설정 열기', onPressed: library.openSettings),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final what = switch (kind) {
      GpsNoticeKind.clean => '그래서 원본에 위치가 있었는지 이 앱에서는 확인할 수 없어요. '
          '(만든 사본에는 위치가 없어요.)',
      GpsNoticeKind.edit => '그래서 위치를 "그대로" 둘 수 없어 결과 사본에는 위치가 빠졌어요. '
          '(망가진 위치 칸은 넣지 않았어요.)',
      GpsNoticeKind.stamp => '위도·경도를 직접 적지 않으면 기록한 사진에는 위치가 들어가지 않아요. '
          '(망가진 위치 칸은 넣지 않아요.)',
    };
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '⚠️ 폰이 사진 $count장을 위치 정보 없이 넘겨줬어요',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: scheme.onErrorContainer),
            ),
            const SizedBox(height: 6),
            Text(
              '사진에 위치 칸은 있는데 좌표가 비어 있어요. 안드로이드가 위치를 가리고 넘겨준 것으로 보여요. '
              '$what\n'
              '고치는 법: 아래 단추로 사진 보기를 "모두 허용"하고 사진 위치 정보 접근도 허용한 뒤, '
              '사진을 다시 골라 주세요. (일부 사진만 허용이나 파일 창으로 고르면 위치가 가려질 수 있어요.)',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _fix(context),
              icon: const Icon(Icons.location_on),
              label: const Text('권한 허용하기'),
            ),
          ],
        ),
      ),
    );
  }
}
