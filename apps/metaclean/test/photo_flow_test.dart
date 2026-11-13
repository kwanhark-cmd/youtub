import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:metaclean/src/clean_screen.dart';
import 'package:metaclean/src/edit_screen.dart';
import 'package:metaclean/src/exif_utils.dart';
import 'package:metaclean/src/photo_pick.dart';
import 'package:metaclean/src/stamp_screen.dart';

/// 진짜 권한 부품 대신 쓰는 가짜. 몇 번 물었는지 센다.
class FakeAccess extends MediaLocationAccess {
  FakeAccess(this.current, {this.afterRequest = MediaLocationStatus.granted});

  MediaLocationStatus current;
  final MediaLocationStatus afterRequest;
  int requests = 0;
  int settings = 0;

  @override
  Future<MediaLocationStatus> status() async => current;

  @override
  Future<MediaLocationStatus> request() async {
    requests++;
    return current = afterRequest;
  }

  @override
  Future<void> openSettings() async => settings++;
}

Uint8List _photo({required bool redacted}) {
  final im = img.Image(width: 8, height: 8);
  im.exif.imageIfd['Model'] = 'SM-S918N';
  im.exif.exifIfd['DateTimeOriginal'] = '2026:10:01 12:00:00';
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

PickPhotos _picker(List<Uint8List> photos, {List<bool>? multipleSeen}) =>
    ({required bool multiple}) async {
      multipleSeen?.add(multiple);
      return [
        for (var i = 0; i < photos.length; i++)
          PickedPhoto(
              name: '20261001_120000_$i.jpg',
              path: null,
              read: () async => photos[i]),
      ];
    };

Future<void> _show(WidgetTester tester, Widget body) async {
  await tester.binding.setSurfaceSize(const Size(420, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
}

void main() {
  late Directory tmp;
  setUp(() {
    resetMediaLocationAskedForTest();
    tmp = Directory.systemTemp.createTempSync('metaclean_flow_');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> runEdit(WidgetTester tester) async {
    await tester.tap(find.text('바꾸기').first); // 날짜 바꾸기 (위치는 그대로)
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('사진 고르고 수정하기 (여러 장 가능)'));
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pump();
  }

  testWidgets('사진 수정: 폰이 위치를 가린 사진이면 결과 목록에 분명히 알린다', (tester) async {
    final access = FakeAccess(MediaLocationStatus.granted);
    await _show(
      tester,
      EditScreen(
        deviceLookup: () async => null,
        pickPhotos: _picker([_photo(redacted: true), _photo(redacted: false)]),
        mediaLocation: access,
        tempDir: () async => tmp,
      ),
    );
    await runEdit(tester);

    expect(find.text('⚠️ 폰이 사진 1장을 위치 정보 없이 넘겨줬어요'), findsOneWidget);
    expect(find.textContaining('위치 없음(폰이 위치를 가린 채 넘겨줌)'), findsOneWidget);
    expect(find.textContaining('위치 있음'), findsOneWidget);
    expect(access.requests, 0); // 이미 허락돼 있으면 묻지 않는다

    // 안내의 단추: 허락돼 있으면 다시 골라 달라고만 한다
    await tester.tap(find.text('권한 허용하기'));
    await tester.pump();
    expect(find.text('허용됐어요. 사진을 다시 골라 주세요'), findsOneWidget);
  });

  testWidgets('위치 권한이 없으면 고르기 전에 한 번 설명하고 묻는다', (tester) async {
    final access = FakeAccess(MediaLocationStatus.denied);
    final seen = <bool>[];
    await _show(
      tester,
      EditScreen(
        deviceLookup: () async => null,
        pickPhotos: _picker([_photo(redacted: false)], multipleSeen: seen),
        mediaLocation: access,
        tempDir: () async => tmp,
      ),
    );
    await tester.tap(find.text('바꾸기').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('사진 고르고 수정하기 (여러 장 가능)'));
    await tester.pumpAndSettle();
    expect(find.text('사진 위치를 그대로 받으려면'), findsOneWidget);
    expect(find.textContaining('지금 내가 있는 곳을 알아내지 않고'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('허용하기'));
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pump();
    expect(access.requests, 1);
    expect(seen, [true]); // 허락 뒤 사진 고르기가 이어진다
    expect(find.textContaining('위치 있음'), findsOneWidget);
    expect(find.textContaining('폰이 사진'), findsNothing);
  });

  testWidgets('"나중에"를 누르면 묻지 않고 고르기로 넘어가며, 같은 실행에선 다시 묻지 않는다',
      (tester) async {
    final access = FakeAccess(MediaLocationStatus.denied);
    final seen = <bool>[];
    await _show(
      tester,
      StampScreen(
        pickPhotos: _picker([_photo(redacted: true)], multipleSeen: seen),
        mediaLocation: access,
      ),
    );
    await tester.tap(find.text('받은 사진 고르기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('나중에'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pump();
    expect(access.requests, 0);
    expect(seen, [false]); // 구매 기록은 한 장만
    expect(find.text('⚠️ 폰이 사진 1장을 위치 정보 없이 넘겨줬어요'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('받은 사진 고르기'));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pump();
    expect(find.text('사진 위치를 그대로 받으려면'), findsNothing);
    expect(seen, [false, false]);
  });

  testWidgets('사진 지우기: 진짜 좌표가 있을 때만 "위치 제거됨"이라고 쓴다', (tester) async {
    final access = FakeAccess(MediaLocationStatus.blocked);
    await _show(
      tester,
      CleanScreen(
        pickPhotos: _picker([_photo(redacted: true), _photo(redacted: false)]),
        mediaLocation: access,
        tempDir: () async => tmp,
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('사진 고르기 (여러 장 가능)'));
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pump();
    // 다시 묻지 않기로 한 권한은 설명 창을 띄우지 않는다
    expect(find.text('사진 위치를 그대로 받으려면'), findsNothing);
    expect(find.textContaining('위치정보(GPS) 제거됨'), findsOneWidget);
    expect(find.textContaining('원본 위치 확인 불가'), findsOneWidget);
    expect(find.text('⚠️ 폰이 사진 1장을 위치 정보 없이 넘겨줬어요'), findsOneWidget);

    // 막힌 권한이면 단추가 설정 화면을 연다
    await tester.tap(find.text('권한 허용하기'));
    await tester.pump();
    expect(access.settings, 1);
  });
}
