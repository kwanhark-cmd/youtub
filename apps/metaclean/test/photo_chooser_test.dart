import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metaclean/src/app_theme.dart';
import 'package:metaclean/src/photo_library.dart';
import 'package:metaclean/src/photo_pick.dart';

import 'fake_library.dart';

List<FakePhoto> _photos(String prefix, int n) => [
      for (var i = 0; i < n; i++)
        FakePhoto('$prefix$i', testPhoto(redacted: false)),
    ];

/// 단추 하나를 누르면 [pickPhotosVia]로 고르고, 결과를 [out]에 담는 시험용 화면.
class _Host extends StatelessWidget {
  const _Host({
    required this.library,
    required this.multiple,
    required this.out,
    this.android = true,
    this.fileWindow,
    this.gallery,
  });

  final PhotoLibrary library;
  final bool multiple;
  final List<List<PickedPhoto>> out;
  final bool android;
  final PickWith? fileWindow;
  final PickWith? gallery;

  static Future<List<PickedPhoto>> _none({required bool multiple}) async =>
      const [];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async => out.add(await pickPhotosVia(
              context,
              library,
              multiple: multiple,
              android: android,
              fileWindow: fileWindow ?? _none,
              gallery: gallery ?? _none,
            )),
            child: const Text('열기'),
          ),
        ),
      );
}

Future<List<List<PickedPhoto>>> _open(
  WidgetTester t,
  PhotoLibrary lib, {
  bool multiple = true,
  bool android = true,
  PickWith? fileWindow,
  PickWith? gallery,
  Size size = const Size(360, 740),
}) async {
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  final out = <List<PickedPhoto>>[];
  await t.pumpWidget(MaterialApp(
    theme: MetaTheme.build(),
    home: _Host(
      library: lib,
      multiple: multiple,
      out: out,
      android: android,
      fileWindow: fileWindow,
      gallery: gallery,
    ),
  ));
  await t.tap(find.text('열기'));
  await t.pumpAndSettle();
  return out;
}

void main() {
  testWidgets('모두 허용: 최근 사진을 격자로 보여 주고, 여러 장을 고른 순서대로 돌려준다', (t) async {
    final photos = _photos('a', 7);
    final lib = FakeLibrary(albums: {'최근 사진': photos});
    final out = await _open(t, lib);

    expect(find.text('사진 고르기'), findsOneWidget);
    expect(find.textContaining('일부 사진만'), findsNothing);
    expect(find.textContaining('위치 정보 접근이 꺼져'), findsNothing);
    expect(find.text('사진을 눌러 고르세요 (여러 장 가능)'), findsOneWidget);
    // 아무것도 안 골랐으면 확인 단추는 눌리지 않는다
    final confirm = find.widgetWithText(FilledButton, '고른 사진 쓰기');
    expect(t.widget<FilledButton>(confirm).onPressed, isNull);

    await t.tap(find.byKey(const ValueKey('photo-a4')));
    await t.tap(find.byKey(const ValueKey('photo-a0')));
    await t.tap(find.byKey(const ValueKey('photo-a2')));
    await t.pump();
    expect(find.text('3장 골랐어요'), findsOneWidget);
    // 고른 순서 번호
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('photo-a4')),
            matching: find.text('1')),
        findsOneWidget);
    // 다시 누르면 빠진다
    await t.tap(find.byKey(const ValueKey('photo-a0')));
    await t.pump();
    expect(find.text('2장 골랐어요'), findsOneWidget);

    // 확인 단추는 크고 굵다
    final btn = find.widgetWithText(FilledButton, '고른 사진 2장 쓰기');
    expect(t.getSize(btn).height, greaterThanOrEqualTo(52));
    await t.tap(btn);
    await t.pumpAndSettle();

    expect(out, hasLength(1));
    expect(out.single.map((p) => p.name), ['a4.jpg', 'a2.jpg']);
    final bytes = await out.single.first.read();
    expect(bytes, photos[4].bytes);
    expect(photos[4].reads, 1);
    expect(lib.requests, 0);
  });

  testWidgets('한 장 고르기: 다른 사진을 누르면 바뀌고, "이 사진 쓰기"', (t) async {
    final lib = FakeLibrary(albums: {'최근 사진': _photos('b', 3)});
    final out = await _open(t, lib, multiple: false);
    expect(find.text('사진 한 장 고르기'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('photo-b0')));
    await t.tap(find.byKey(const ValueKey('photo-b1')));
    await t.pump();
    expect(find.text('1장 골랐어요'), findsOneWidget);
    await t.tap(find.text('이 사진 쓰기'));
    await t.pumpAndSettle();
    expect(out.single.map((p) => p.name), ['b1.jpg']);
  });

  testWidgets('앨범을 바꿀 수 있다', (t) async {
    final lib = FakeLibrary(albums: {
      '최근 사진': _photos('r', 2),
      'Camera': _photos('c', 3),
    });
    await _open(t, lib);
    expect(find.byKey(const ValueKey('photo-r0')), findsOneWidget);
    await t.tap(find.text('최근 사진 (2)'));
    await t.pumpAndSettle();
    await t.tap(find.text('Camera (3)').last);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo-r0')), findsNothing);
    expect(find.byKey(const ValueKey('photo-c2')), findsOneWidget);
  });

  testWidgets('사진이 많으면 내려가면서 더 읽는다', (t) async {
    final lib = FakeLibrary(albums: {'최근 사진': _photos('m', 200)});
    await _open(t, lib);
    expect(lib.pagesAsked, [0]);
    await t.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await t.pumpAndSettle();
    expect(lib.pagesAsked, containsAllInOrder([0, 1]));
  });

  testWidgets('허용 전: 한국어로 이유를 먼저 설명하고, 누르면 묻고, 허용하면 사진이 보인다', (t) async {
    final lib = FakeLibrary(
      current: LibraryAccess.denied,
      afterRequest: LibraryAccess.full,
      albums: {'최근 사진': _photos('d', 2)},
    );
    await _open(t, lib);
    expect(find.text('사진을 보려면 허용이 필요해요'), findsOneWidget);
    expect(find.textContaining('"모두 허용"'), findsWidgets);
    expect(lib.requests, 0); // 설명 전에 안드로이드 창을 띄우지 않는다
    await t.tap(find.text('사진 보기 허용하기'));
    await t.pumpAndSettle();
    expect(lib.requests, 1);
    expect(find.byKey(const ValueKey('photo-d1')), findsOneWidget);
  });

  testWidgets('허용하지 않으면 설정 열기·파일 창으로 고르기를 고를 수 있다', (t) async {
    final lib = FakeLibrary(
        current: LibraryAccess.denied, afterRequest: LibraryAccess.denied);
    final asked = <bool>[];
    final out =
        await _open(t, lib, fileWindow: ({required bool multiple}) async {
      asked.add(multiple);
      return [
        PickedPhoto(
            name: 'f.jpg',
            path: null,
            read: () async => testPhoto(redacted: true)),
      ];
    });
    await t.tap(find.text('사진 보기 허용하기'));
    await t.pumpAndSettle();
    expect(find.text('사진을 보려면 허용이 필요해요'), findsOneWidget);
    expect(find.text('허용했어요'), findsOneWidget);
    await t.tap(find.text('설정 열기'));
    await t.pump();
    expect(lib.settings, 1);

    await t.scrollUntilVisible(find.text('파일 창에서 고르기'), 200);
    await t.tap(find.text('파일 창에서 고르기'));
    await t.pumpAndSettle();
    expect(asked, [true]);
    expect(out.single.map((p) => p.name), ['f.jpg']);
  });

  testWidgets('설정에서 허용하고 돌아와 "허용했어요"를 누르면 사진이 보인다', (t) async {
    final lib = FakeLibrary(
      current: LibraryAccess.denied,
      afterRequest: LibraryAccess.denied,
      albums: {'최근 사진': _photos('s', 1)},
    );
    await _open(t, lib);
    await t.tap(find.text('사진 보기 허용하기'));
    await t.pumpAndSettle();
    lib.current = LibraryAccess.full; // 설정에서 허용함
    await t.tap(find.text('허용했어요'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo-s0')), findsOneWidget);
  });

  testWidgets('일부 사진만 허용(안드로이드 14): 이유와 설정 열기를 보여 주고, 보이는 사진으로는 계속 할 수 있다',
      (t) async {
    final lib = FakeLibrary(
        current: LibraryAccess.limited, albums: {'최근 사진': _photos('l', 2)});
    final out = await _open(t, lib);
    expect(find.text('⚠️ 일부 사진만 허용돼 있어요'), findsOneWidget);
    expect(find.textContaining('위치를 그대로 읽으려면'), findsOneWidget);
    await t.tap(find.text('설정 열기'));
    await t.pump();
    expect(lib.settings, 1);
    await t.tap(find.text('보여 줄 사진 더 고르기'));
    await t.pumpAndSettle();
    expect(lib.pickMore, 1);

    await t.tap(find.byKey(const ValueKey('photo-l0')));
    await t.pump();
    await t.tap(find.text('고른 사진 1장 쓰기'));
    await t.pumpAndSettle();
    expect(out.single, hasLength(1));
  });

  testWidgets('모두 허용인데 위치 정보 접근이 꺼져 있으면 알린다', (t) async {
    final lib =
        FakeLibrary(location: false, albums: {'최근 사진': _photos('x', 1)});
    await _open(t, lib);
    expect(find.text('⚠️ 사진 위치 정보 접근이 꺼져 있어요'), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-x0')), findsOneWidget);
  });

  testWidgets('뒤로 가면 아무것도 고르지 않은 것', (t) async {
    final lib = FakeLibrary(albums: {'최근 사진': _photos('z', 1)});
    final out = await _open(t, lib);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(out.single, isEmpty);
  });

  testWidgets('안드로이드가 아니면 예전 사진 고르기 창을 쓴다', (t) async {
    final lib = FakeLibrary(albums: {'최근 사진': _photos('g', 1)});
    final seen = <bool>[];
    final out = await _open(t, lib, android: false,
        gallery: ({required bool multiple}) async {
      seen.add(multiple);
      return const [];
    });
    expect(seen, [true]);
    expect(out.single, isEmpty);
    expect(find.text('사진 고르기'), findsNothing);
  });

  for (final scale in [1.0, 1.5]) {
    for (final access in [
      LibraryAccess.full,
      LibraryAccess.limited,
      LibraryAccess.denied
    ]) {
      testWidgets('360×740 · 글씨 $scale배 · $access: 넘치지 않고 단추는 52 이상',
          (t) async {
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final lib = FakeLibrary(current: access, albums: {
          '최근 사진': _photos('q', 30),
          '아주 긴 이름의 앨범 이름이 들어가도 괜찮은지 보기': _photos('w', 1),
        });
        await _open(t, lib);
        expect(t.takeException(), isNull);
        if (access != LibraryAccess.denied) {
          await t.scrollUntilVisible(
              find.byKey(const ValueKey('photo-q0')), 200,
              scrollable: find.byType(Scrollable).first);
          await t.tap(find.byKey(const ValueKey('photo-q0')));
          await t.pump();
          expect(t.takeException(), isNull);
        }
        for (final e in find
            .byWidgetPredicate((w) =>
                w is FilledButton || w is OutlinedButton || w is TextButton)
            .evaluate()) {
          final box = e.renderObject as RenderBox?;
          if (box == null || !box.hasSize || !box.attached) continue;
          expect(box.size.height, greaterThanOrEqualTo(51.99),
              reason: '${e.widget}');
        }
      });
    }
  }
}
