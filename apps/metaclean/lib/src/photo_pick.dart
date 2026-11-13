import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as ip;
import 'package:permission_handler/permission_handler.dart' as ph;

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
    {required bool multiple});

/// 고를 수 있는 사진 확장자.
const photoExtensions = [
  'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'tif', 'tiff', 'heic', 'heif', //
];

/// 사진을 원본 그대로(위치 정보 포함) 받아 온다.
///
/// 안드로이드에서는 시스템 "파일" 고르기 창(ACTION_OPEN_DOCUMENT)을 쓴다.
/// 사진 고르기 창(포토 피커)과 갤러리 고르기(ACTION_GET_CONTENT)로 받은 사진은
/// 안드로이드가 촬영 위치를 0으로 덮어서 넘겨주는 일이 있다 (포토 피커는 늘,
/// 갤러리 고르기는 폰의 미디어 모듈 판에 따라). 파일 고르기 창의 사진은 시스템 미디어
/// 저장소가 자기 이름으로 열어 주므로 위치가 그대로 온다.
Future<List<PickedPhoto>> pickOriginalPhotos({required bool multiple}) async {
  if (!kIsWeb && Platform.isAndroid) {
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
  // 그 밖의 기기: 예전처럼 사진 고르기 창.
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

/// '사진 위치 정보 접근'(ACCESS_MEDIA_LOCATION) 권한 상태.
enum MediaLocationStatus {
  /// 허락됨, 또는 이 기기에는 필요 없음 (안드로이드 9 이하·다른 기기).
  granted,

  /// 아직 허락하지 않음 (물어볼 수 있음).
  denied,

  /// 다시 묻지 않기로 함. 설정 화면에서만 바꿀 수 있다.
  blocked,
}

/// '사진 위치 정보 접근' 권한을 묻고 확인하는 방법. 테스트에서는 가짜로 바꿔 끼운다.
class MediaLocationAccess {
  const MediaLocationAccess();

  static MediaLocationStatus _map(ph.PermissionStatus s) {
    if (s.isGranted || s.isLimited || s.isRestricted) {
      return MediaLocationStatus.granted;
    }
    if (s.isPermanentlyDenied) return MediaLocationStatus.blocked;
    return MediaLocationStatus.denied;
  }

  bool get _applies => !kIsWeb && Platform.isAndroid;

  Future<MediaLocationStatus> status() async {
    if (!_applies) return MediaLocationStatus.granted;
    try {
      return _map(await ph.Permission.accessMediaLocation.status);
    } catch (_) {
      return MediaLocationStatus.granted; // 알 수 없으면 묻지 않는다
    }
  }

  Future<MediaLocationStatus> request() async {
    if (!_applies) return MediaLocationStatus.granted;
    try {
      return _map(await ph.Permission.accessMediaLocation.request());
    } catch (_) {
      return MediaLocationStatus.denied;
    }
  }

  /// 이 앱의 설정(권한) 화면을 연다.
  Future<void> openSettings() async {
    try {
      await ph.openAppSettings();
    } catch (_) {}
  }
}

/// 이번에 앱을 켠 뒤 이미 설명하고 물어봤는지 (한 번만 묻는다).
bool _askedThisRun = false;

@visibleForTesting
void resetMediaLocationAskedForTest() => _askedThisRun = false;

const mediaLocationWhy = '안드로이드는 따로 허락하지 않은 앱에 사진을 넘겨줄 때, 사진 속 촬영 위치(지도 정보)를 '
    '지우고 넘겨주기도 해요. 그러면 "위치 그대로"를 골라도 위치가 사라지고, '
    '"사진 지우기"에서도 원래 위치가 있었는지 알 수 없어요.\n\n'
    '다음에 뜨는 창에서 허용을 누르면, 고른 사진에 들어 있는 위치를 그대로 읽을 수 있어요. '
    '이 권한은 지금 내가 있는 곳을 알아내지 않고, 위치를 어디로 보내지도 않아요.';

/// 사진을 고르기 전에, 필요하면 '사진 위치 정보 접근'을 왜 쓰는지 설명하고 허락을 묻는다.
///
/// 앱을 켠 뒤 한 번만 묻는다. 허락하지 않아도 사진 고르기는 그대로 이어진다.
Future<void> askMediaLocationOnce(
    BuildContext context, MediaLocationAccess access) async {
  if (_askedThisRun) return;
  final st = await access.status();
  if (st != MediaLocationStatus.denied) return;
  _askedThisRun = true;
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('사진 위치를 그대로 받으려면'),
      content: const SingleChildScrollView(child: Text(mediaLocationWhy)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('나중에'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('허용하기'),
        ),
      ],
    ),
  );
  if (ok == true) await access.request();
}

/// [GpsHiddenNotice]를 보여 주는 화면.
enum GpsNoticeKind { edit, clean, stamp }

/// 폰이 위치를 가린 채 사진을 넘겨줬을 때 결과 목록 위에 보여 주는 안내.
class GpsHiddenNotice extends StatelessWidget {
  const GpsHiddenNotice({
    super.key,
    required this.count,
    required this.access,
    this.kind = GpsNoticeKind.edit,
  });

  /// 위치가 가려진 채 받은 사진 수.
  final int count;
  final MediaLocationAccess access;

  /// 어느 화면의 안내인지 (무엇이 달라지는지 설명이 다르다).
  final GpsNoticeKind kind;

  Future<void> _fix(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    var st = await access.status();
    if (st == MediaLocationStatus.denied) st = await access.request();
    if (st == MediaLocationStatus.blocked) {
      await access.openSettings();
      messenger.showSnackBar(const SnackBar(
          content: Text('권한 화면에서 위치 관련 권한을 허용한 뒤, 사진을 다시 골라 주세요')));
      return;
    }
    messenger.showSnackBar(SnackBar(
        content: Text(st == MediaLocationStatus.granted
            ? '허용됐어요. 사진을 다시 골라 주세요'
            : '허용하지 않았어요. 위치가 필요하면 다시 눌러 주세요')));
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
              '고치는 법: 아래 단추로 "사진 위치 정보 접근"을 허용한 뒤, 사진을 다시 골라 주세요. '
              '고르는 창에서는 왼쪽 메뉴의 "이미지"나 "최근"에서 고르면 돼요.',
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
