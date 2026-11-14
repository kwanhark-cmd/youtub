import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:metaclean/src/exif_utils.dart';
import 'package:metaclean/src/photo_library.dart';

/// 진짜 사진 보관함(photo_manager) 대신 쓰는 가짜. 무엇을 불렀는지 센다.
class FakeLibrary extends PhotoLibrary {
  FakeLibrary({
    this.current = LibraryAccess.full,
    this.afterRequest = LibraryAccess.full,
    this.location = true,
    Map<String, List<FakePhoto>>? albums,
  }) : albumPhotos = albums ?? {};

  LibraryAccess current;
  final LibraryAccess afterRequest;
  bool location;
  final Map<String, List<FakePhoto>> albumPhotos;

  int requests = 0;
  int settings = 0;
  int pickMore = 0;
  final List<int> pagesAsked = [];

  @override
  Future<LibraryAccess> access() async => current;

  @override
  Future<LibraryAccess> requestAccess() async {
    requests++;
    return current = afterRequest;
  }

  @override
  Future<bool> canReadLocation() async => location;

  @override
  Future<void> openSettings() async => settings++;

  @override
  Future<void> pickMoreForLimited() async => pickMore++;

  @override
  Future<List<LibraryAlbum>> albums() async => [
        for (final e in albumPhotos.entries)
          LibraryAlbum(id: e.key, name: e.key, count: e.value.length),
      ];

  @override
  Future<List<LibraryPhoto>> photos(LibraryAlbum album,
      {required int page, required int size}) async {
    pagesAsked.add(page);
    final all = albumPhotos[album.id] ?? const [];
    final from = page * size;
    if (from >= all.length) return const [];
    return all.sublist(from, (from + size).clamp(0, all.length));
  }
}

class FakePhoto implements LibraryPhoto {
  FakePhoto(this.id, this.bytes, {String? name}) : _name = name ?? '$id.jpg';

  @override
  final String id;
  final Uint8List bytes;
  final String _name;
  int reads = 0;

  @override
  Future<String> name() async => _name;

  @override
  Future<Uint8List?> thumbnail() async => null;

  @override
  Future<Uint8List?> original() async {
    reads++;
    return bytes;
  }
}

/// 촬영 위치(37.2411, 127.1776)가 든 사진. [redacted]면 안드로이드가 가린 것처럼 좌표를 0으로 덮는다.
Uint8List testPhoto({required bool redacted}) {
  final im = img.Image(width: 8, height: 8);
  im.exif.imageIfd['Model'] = 'SM-F721N';
  im.exif.exifIfd['DateTimeOriginal'] = '2023:11:02 00:33:00';
  writeGps(im.exif, 37.2411, 127.1776);
  if (redacted) {
    final g = im.exif.gpsIfd.data;
    g[0x0001] = img.IfdValueAscii.list(const [0]);
    g[0x0003] = img.IfdValueAscii.list(const [0]);
    final zero = img.IfdValueRational(0, 0)
      ..value.addAll(img.IfdValueRational(0, 0).value)
      ..value.addAll(img.IfdValueRational(0, 0).value);
    g[0x0002] = zero;
    g[0x0004] = zero.clone();
  }
  return img.encodeJpg(im);
}
