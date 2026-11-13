import 'dart:io';

import 'package:binugi/app.dart';
import 'package:binugi/data/models.dart';
import 'package:binugi/ui/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// 안드로이드는 새 버전을 설치하려면 기존 앱을 지워야 하고, 지우면 앱 안 파일도 지워진다.
/// 그래서 "백업 파일 만들기"는 백업을 꼭 앱 밖(사용자가 고른 곳)에 저장해야 하고,
/// 새로 설치한 앱에서 그 파일로 되살릴 수 있어야 한다.
void main() {
  Future<void> openSettings(WidgetTester t, FakePicker picker, dynamic s) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    await t.pumpWidget(BinugiApp(state: s, picker: picker, listenShares: false));
    await t.pump(const Duration(milliseconds: 300));
    navKey.currentState!.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> makeBackup(WidgetTester t, String pw) async {
    final btn = find.text('백업 파일 만들기');
    await t.scrollUntilVisible(btn, 300, scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(btn);
    await t.pump(const Duration(milliseconds: 300));
    await t.enterText(find.byType(TextField).last, pw);
    await t.tap(find.text('확인'));
    await t.pump();
    // 암호화(PBKDF2)와 파일 쓰기는 진짜 시간이 걸린다. 안내가 뜰 때까지 기다린다 (최대 60초).
    bool done() => find.textContaining('앱 밖에 저장했어요').evaluate().isNotEmpty || find.textContaining('앱 안에만').evaluate().isNotEmpty;
    for (var i = 0; i < 120 && !done(); i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('백업 파일 만들기 → 앱 밖에 저장 → 앱 지움 → 새로 설치한 앱에서 되살리기', (t) async {
    late Directory outside;
    late Directory oldRoot;
    final picker = FakePicker();
    late dynamic s;
    await t.runAsync(() async {
      outside = await Directory.systemTemp.createTemp('binugi_outside_');
      final (st, root) = await makeState();
      s = st;
      oldRoot = root;
      final photo = await st.savePhoto(fakeJpeg(w: 400, h: 300));
      await st.addItem(name: '옮길 커피 머신', photo: photo, decision: Decision.sell);
      st.global.onboarded = true;
      await st.refresh();
    });
    addTearDown(() => outside.deleteSync(recursive: true));
    picker.outside = outside;
    await openSettings(t, picker, s);
    await makeBackup(t, '1234');

    expect(picker.exported, hasLength(1), reason: '만든 백업을 앱 밖 저장 창으로 넘김');
    final saved = File(picker.exported.single);
    expect(saved.path.startsWith(outside.path), isTrue);
    expect(saved.path.startsWith(oldRoot.path), isFalse, reason: '앱 자료 폴더 안이 아님');
    expect(find.textContaining('앱 밖에 저장했어요'), findsOneWidget);

    await t.runAsync(() async {
      // 기존 앱 지우기: 앱 자료 폴더가 통째로 사라진다. 앱 밖 백업은 남는다.
      await oldRoot.delete(recursive: true);
      expect(saved.existsSync(), isTrue);

      // 새로 설치한 앱: 빈 자료 폴더에서 시작해 백업으로 되살린다.
      final (fresh, _) = await makeState();
      expect(fresh.items, isEmpty);
      await fresh.backup.restoreBytes(await saved.readAsBytes(), '1234');
      await fresh.reloadAfterRestore();
      final it = fresh.items.single;
      expect(it.name, '옮길 커피 머신');
      expect(it.decision, Decision.sell);
      expect(File(fresh.paths.abs(it.photoPath!)).existsSync(), isTrue, reason: '사진도 되살아남');
    });
  });

  testWidgets('저장 창을 취소하면 "앱 안에만 있어요, 앱 밖에 저장해 주세요" 안내', (t) async {
    final picker = FakePicker(); // outside == null → 사용자가 취소
    late dynamic s;
    await t.runAsync(() async {
      final (st, _) = await makeState();
      s = st;
      st.global.onboarded = true;
      await st.refresh();
    });
    await openSettings(t, picker, s);
    await makeBackup(t, '1234');
    expect(picker.exported, isEmpty);
    expect(find.textContaining('앱 안에만 있어요'), findsOneWidget);
    expect(find.textContaining('앱 밖에 저장했어요'), findsNothing);
  });
}
