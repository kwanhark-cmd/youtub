import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metaclean/src/clean_screen.dart';
import 'package:metaclean/src/edit_screen.dart';
import 'package:metaclean/src/photo_library.dart';
import 'package:metaclean/src/photo_pick.dart';
import 'package:metaclean/src/stamp_screen.dart';

import 'fake_library.dart';

PickPhotos _picker(List<Uint8List> photos, {List<bool>? multipleSeen}) =>
    (context, library, {required bool multiple}) async {
      multipleSeen?.add(multiple);
      return [
        for (var i = 0; i < photos.length; i++)
          PickedPhoto(
              name: '20231102_003300_$i.jpg',
              path: null,
              read: () async => photos[i]),
      ];
    };

Future<void> _show(WidgetTester tester, Widget body) async {
  await tester.binding.setSurfaceSize(const Size(420, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
}

/// 파일 쓰기 같은 진짜 비동기 일이 끝나도록 잠깐씩 기다린다.
Future<void> _settleIo(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pump();
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('metaclean_flow_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> runEdit(WidgetTester tester) async {
    await tester.tap(find.text('바꾸기').first); // 날짜 바꾸기 (위치는 그대로)
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('사진 고르고 수정하기 (여러 장 가능)'));
    });
    await _settleIo(tester);
  }

  testWidgets('사진 수정: 위치가 남은 사진은 실제 좌표를, 가려진 사진은 분명한 안내를 보여 준다',
      (tester) async {
    final lib = FakeLibrary();
    await _show(
      tester,
      EditScreen(
        deviceLookup: () async => null,
        pickPhotos:
            _picker([testPhoto(redacted: true), testPhoto(redacted: false)]),
        library: lib,
        tempDir: () async => tmp,
      ),
    );
    await runEdit(tester);

    expect(find.text('⚠️ 폰이 사진 1장을 위치 정보 없이 넘겨줬어요'), findsOneWidget);
    expect(find.textContaining('위치 없음(폰이 위치를 가린 채 넘겨줌)'), findsOneWidget);
    expect(find.textContaining('위치 유지됨 (37.24, 127.18)'), findsOneWidget);
    expect(lib.requests, 0);

    // 안내의 단추: 이미 모두 허용돼 있으면 다시 골라 달라고만 한다
    await tester.tap(find.text('권한 허용하기'));
    await tester.pump();
    expect(find.text('허용돼 있어요. 사진을 다시 골라 주세요'), findsOneWidget);
    expect(lib.requests, 0);
  });

  testWidgets('사진 수정: 위치를 바꾸면 바뀐 좌표를 보여 준다', (tester) async {
    await _show(
      tester,
      EditScreen(
        deviceLookup: () async => null,
        pickPhotos: _picker([testPhoto(redacted: false)]),
        library: FakeLibrary(),
        tempDir: () async => tmp,
      ),
    );
    await tester.tap(find.text('바꾸기').at(1)); // 위치 바꾸기
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '35.1, 129.04');
    await tester.runAsync(() async {
      await tester.tap(find.text('사진 고르고 수정하기 (여러 장 가능)'));
    });
    await _settleIo(tester);
    expect(find.textContaining('위치 바뀜 (35.10, 129.04)'), findsOneWidget);
  });

  testWidgets('사진 지우기: 원본 좌표를 보여 주고, 가려진 사진이면 권한을 다시 묻거나 설정을 연다',
      (tester) async {
    final lib = FakeLibrary(
        current: LibraryAccess.limited, afterRequest: LibraryAccess.limited);
    await _show(
      tester,
      CleanScreen(
        pickPhotos:
            _picker([testPhoto(redacted: true), testPhoto(redacted: false)]),
        library: lib,
        tempDir: () async => tmp,
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('사진 고르기 (여러 장 가능)'));
    });
    await _settleIo(tester);
    expect(find.textContaining('위치정보(GPS) 제거됨 (원본 위치 37.24, 127.18)'),
        findsOneWidget);
    expect(find.textContaining('원본 위치 확인 불가'), findsOneWidget);
    expect(find.text('⚠️ 폰이 사진 1장을 위치 정보 없이 넘겨줬어요'), findsOneWidget);

    // 일부만 허용이면 한 번 묻고, 그래도 안 되면 설정 열기를 권한다
    await tester.tap(find.text('권한 허용하기'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // 알림 띠가 다 올라오도록
    expect(lib.requests, 1);
    expect(find.textContaining('"모두 허용"을 고른 뒤'), findsOneWidget);
    await tester.tap(find.text('설정 열기'));
    await tester.pump();
    expect(lib.settings, 1);
  });

  testWidgets('구매 기록: 한 장만 고르고, 사진 속 위치를 보여 준다', (tester) async {
    final seen = <bool>[];
    await _show(
      tester,
      StampScreen(
        pickPhotos: _picker([testPhoto(redacted: false)], multipleSeen: seen),
        library: FakeLibrary(),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('받은 사진 고르기'));
    });
    await _settleIo(tester);
    expect(seen, [false]);
    expect(find.textContaining('사진 속 위치: 37.24, 127.18'), findsOneWidget);
    expect(find.textContaining('폰이 사진'), findsNothing);
  });

  testWidgets('구매 기록: 가려진 사진이면 안내를 보여 준다', (tester) async {
    await _show(
      tester,
      StampScreen(
        pickPhotos: _picker([testPhoto(redacted: true)]),
        library: FakeLibrary(),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('받은 사진 고르기'));
    });
    await _settleIo(tester);
    expect(find.text('⚠️ 폰이 사진 1장을 위치 정보 없이 넘겨줬어요'), findsOneWidget);
    expect(find.textContaining('사진 속 위치'), findsNothing);
  });

  testWidgets('안드로이드: 앱 안 고르기 화면에서 고른 사진의 원본(위치 포함)으로 수정한다', (tester) async {
    final photos = [
      for (var i = 0; i < 5; i++)
        FakePhoto('p$i', testPhoto(redacted: false),
            name: '20231102_00330$i.jpg'),
    ];
    final lib = FakeLibrary(albums: {'최근 사진': photos});
    var otherWays = 0;
    Future<List<PickedPhoto>> never({required bool multiple}) async {
      otherWays++;
      return const [];
    }

    await _show(
      tester,
      EditScreen(
        deviceLookup: () async => null,
        pickPhotos: (context, library, {required bool multiple}) =>
            pickPhotosVia(context, library,
                multiple: multiple,
                android: true,
                fileWindow: never,
                gallery: never),
        library: lib,
        tempDir: () async => tmp,
      ),
    );
    await tester.tap(find.text('바꾸기').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('사진 고르고 수정하기 (여러 장 가능)'));
    await tester.pumpAndSettle();

    expect(find.text('사진 고르기'), findsOneWidget); // 앱 안 고르기 화면
    await tester.tap(find.byKey(const ValueKey('photo-p1')));
    await tester.tap(find.byKey(const ValueKey('photo-p3')));
    await tester.pump();
    expect(find.text('2장 골랐어요'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('고른 사진 2장 쓰기'));
    });
    await tester.pumpAndSettle();
    await _settleIo(tester);

    expect(otherWays, 0);
    expect(photos.map((p) => p.reads), [0, 1, 0, 1, 0]);
    expect(find.text('20231102_003301.jpg'), findsOneWidget);
    expect(find.text('20231102_003303.jpg'), findsOneWidget);
    expect(find.textContaining('위치 유지됨 (37.24, 127.18)'), findsNWidgets(2));
    expect(find.textContaining('폰이 사진'), findsNothing);
  });
}
