import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:photo_manager/photo_manager.dart' as pm;

/// 폰의 사진 보관함을 볼 수 있는 정도.
enum LibraryAccess {
  /// 모든 사진 허용.
  full,

  /// 안드로이드 14+ "일부 사진만 허용" (사용자가 고른 사진만 보인다).
  limited,

  /// 허용하지 않음.
  denied,
}

/// 사진 보관함의 앨범 하나.
class LibraryAlbum {
  const LibraryAlbum({required this.id, required this.name, this.count});

  final String id;
  final String name;

  /// 사진 수. 모르면 null.
  final int? count;
}

/// 사진 보관함의 사진 한 장.
abstract class LibraryPhoto {
  String get id;

  /// 파일 이름 (예: 20231102_003300.jpg).
  Future<String> name();

  /// 작은 미리보기 그림.
  Future<Uint8List?> thumbnail();

  /// 원본 파일 바이트. 위치 접근이 허락돼 있으면 안드로이드가 위치를 가리지 않은
  /// 진짜 원본(MediaStore.setRequireOriginal)이다.
  Future<Uint8List?> original();
}

/// 폰의 사진 보관함(MediaStore). 화면 테스트에서는 가짜로 바꿔 끼운다.
///
/// 안드로이드는 사진을 넘겨주는 길(포토 피커·갤러리 고르기·파일 고르기 창)에 따라
/// 촬영 위치를 0으로 덮어서 넘겨주기도 한다. 이 앱은 그 길을 쓰지 않고,
/// "사진 및 동영상" 권한(READ_MEDIA_IMAGES, 안드로이드 12 이하는 READ_EXTERNAL_STORAGE)과
/// "사진 위치 정보 접근"(ACCESS_MEDIA_LOCATION) 권한을 함께 받아 보관함에서 직접
/// 원본(setRequireOriginal)을 읽는다. photo_manager 부품이 이 일을 한다.
class PhotoLibrary {
  const PhotoLibrary();

  static const _option = pm.PermissionRequestOption(
    androidPermission:
        pm.AndroidPermission(type: pm.RequestType.image, mediaLocation: true),
  );

  static LibraryAccess _map(pm.PermissionState s) => switch (s) {
        pm.PermissionState.authorized => LibraryAccess.full,
        pm.PermissionState.limited => LibraryAccess.limited,
        _ => LibraryAccess.denied,
      };

  /// 이 부품을 쓰는 기기인지. 안드로이드 밖에서는 예전 사진 고르기 창을 쓰므로
  /// 보관함 권한을 묻지 않는다 (아이폰은 묻는 이유 문구가 없으면 앱이 멈춘다).
  static bool get _applies => !kIsWeb && Platform.isAndroid;

  /// 지금 허용 상태 (묻지 않는다).
  Future<LibraryAccess> access() async {
    if (!_applies) return LibraryAccess.full;
    try {
      return _map(
          await pm.PhotoManager.getPermissionState(requestOption: _option));
    } catch (_) {
      return LibraryAccess.denied;
    }
  }

  /// 사진 보기와 사진 위치 정보 접근을 함께 묻는다 (안드로이드 창이 뜬다).
  Future<LibraryAccess> requestAccess() async {
    if (!_applies) return LibraryAccess.full;
    try {
      return _map(await pm.PhotoManager.requestPermissionExtend(
          requestOption: _option));
    } catch (_) {
      return LibraryAccess.denied;
    }
  }

  /// '사진 위치 정보 접근'(ACCESS_MEDIA_LOCATION)이 허락돼 있는지.
  /// 안드로이드 9 이하·다른 기기에서는 필요 없으므로 참.
  Future<bool> canReadLocation() async {
    if (!_applies) return true;
    try {
      return (await ph.Permission.accessMediaLocation.status).isGranted;
    } catch (_) {
      return false;
    }
  }

  /// 이 앱의 설정(권한) 화면을 연다.
  Future<void> openSettings() async {
    try {
      await pm.PhotoManager.openSetting();
    } catch (_) {}
  }

  /// "일부 사진만 허용"일 때, 보여 줄 사진을 더 고르는 안드로이드 창을 연다.
  Future<void> pickMoreForLimited() async {
    try {
      await pm.PhotoManager.presentLimited(type: pm.RequestType.image);
    } catch (_) {}
  }

  static final _filter = pm.FilterOptionGroup(
    orders: [
      const pm.OrderOption(type: pm.OrderOptionType.createDate, asc: false),
    ],
  );

  /// 앨범 목록. 첫 번째가 "최근"(모든 사진)이다.
  Future<List<LibraryAlbum>> albums() async {
    final paths = await pm.PhotoManager.getAssetPathList(
      type: pm.RequestType.image,
      filterOption: _filter,
    );
    final out = <LibraryAlbum>[];
    for (final p in paths) {
      int? count;
      try {
        count = await p.assetCountAsync;
      } catch (_) {}
      if (count == 0) continue;
      out.add(_PmAlbum(p, count));
    }
    return out;
  }

  /// 앨범의 사진을 최근 것부터 [size]장씩 [page]쪽을 가져온다.
  Future<List<LibraryPhoto>> photos(LibraryAlbum album,
      {required int page, required int size}) async {
    final path = (album as _PmAlbum).path;
    final list = await path.getAssetListPaged(page: page, size: size);
    return [for (final a in list) _PmPhoto(a)];
  }
}

class _PmAlbum extends LibraryAlbum {
  _PmAlbum(this.path, int? count)
      : super(
          id: path.id,
          name: path.isAll ? '최근 사진' : path.name,
          count: count,
        );

  final pm.AssetPathEntity path;
}

class _PmPhoto implements LibraryPhoto {
  _PmPhoto(this.asset);

  final pm.AssetEntity asset;

  @override
  String get id => asset.id;

  @override
  Future<String> name() async {
    final t = asset.title;
    if (t != null && t.isNotEmpty) return t;
    try {
      final a = await asset.titleAsync;
      if (a.isNotEmpty) return a;
    } catch (_) {}
    return 'photo_${asset.id}.jpg';
  }

  @override
  Future<Uint8List?> thumbnail() =>
      asset.thumbnailDataWithSize(const pm.ThumbnailSize.square(240));

  // photo_manager 는 ACCESS_MEDIA_LOCATION 이 허락돼 있으면
  // MediaStore.setRequireOriginal 을 붙인 주소로 원본을 읽는다.
  @override
  Future<Uint8List?> original() => asset.originBytes;
}
