import 'dart:io';
import 'dart:typed_data';

import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/core/failure.dart';
import 'package:channel_biseo/core/strings.dart';
import 'package:channel_biseo/stages.dart';
import 'package:channel_biseo/ui/app_look_section.dart';
import 'package:channel_biseo/ui/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 앱 꾸미기: 이름·아이콘·색 묶음.
Future<(TestKit, AppState)> open(WidgetTester t, {bool android = false}) async {
  registerStages();
  t.view.physicalSize = const Size(390 * 2, 844 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final k = TestKit(android: android);
  final s = AppState(k.env);
  await s.login(k.env.accounts.create('꾸미기', '1234'));
  s.user!.settings.onboardingDone = true;
  await t.pumpWidget(ChannelBiseoApp(state: s));
  await t.pumpAndSettle();
  return (k, s);
}

Future<void> toLook(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.settings).last);
  await t.pumpAndSettle();
  await t.scrollUntilVisible(find.byKey(const Key('look-section')), 300, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

Future<void> tapKey(WidgetTester t, String key) async {
  final f = find.byKey(Key(key));
  await t.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  group('이름', () {
    testWidgets('바꾼 이름이 홈·창 제목·알림 제목에 바로', (t) async {
      final (k, s) = await open(t);
      expect(t.widget<MaterialApp>(find.byType(MaterialApp)).title, S.appName);
      await toLook(t);
      await t.enterText(find.byKey(const Key('look-name')), '우리집 채널 비서');
      await tapKey(t, 'look-name-save');
      expect(t.widget<MaterialApp>(find.byType(MaterialApp)).title, '우리집 채널 비서');
      expect(find.text('우리집 채널 비서'), findsWidgets);
      // 홈
      await t.tap(find.byIcon(Icons.dashboard).last);
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('home-app-name'))).data, '우리집 채널 비서');
      // 알림 제목
      final u = s.user!;
      u.settings.runnerEnabled = true;
      k.clock.t = DateTime(2026, 11, 3, 3, 0);
      await u.runner.tick();
      expect(k.notifier.shown.first.$1, '우리집 채널 비서');
      // 비우면 기본 이름
      u.look.setName('');
      expect(u.look.displayName, S.appName);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('아이콘', () {
    testWidgets('안드로이드: 기본 아이콘을 고르면 홈 화면 아이콘도 바꾸고, 바로가기를 이름·그림으로', (t) async {
      final (k, s) = await open(t, android: true);
      await toLook(t);
      await tapKey(t, 'look-icon-green');
      expect(k.launcherIcons, ['green']);
      expect(s.user!.settings.appIcon, 'green');
      s.user!.look.setName('김사장 비서');
      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('look-shortcut')));
        for (var i = 0; i < 50 && k.shortcuts.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await t.pumpAndSettle();
      expect(k.shortcuts.single.$1, '김사장 비서');
      expect(k.shortcuts.single.$2, greaterThan(100)); // PNG
      expect(find.byKey(const Key('look-icon-file')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('컴퓨터: 앱 안에 바로 적용 + 바로가기용 아이콘 파일(.png·.ico)과 안내', (t) async {
      final (k, s) = await open(t);
      await toLook(t);
      await tapKey(t, 'look-icon-purple');
      expect(k.launcherIcons, isEmpty); // 컴퓨터는 운영체제 아이콘을 건드리지 않음
      expect(s.user!.look.iconId, 'purple');
      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('look-icon-file')));
        for (var i = 0; i < 50 && find.byKey(const Key('look-icon-file-dialog')).evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await t.pump();
        }
      });
      await t.pumpAndSettle();
      expect(find.byKey(const Key('look-icon-file-dialog')), findsOneWidget);
      expect(find.textContaining('아이콘 변경'), findsOneWidget); // 윈도우 안내
      final ico = File('${k.env.documentsDir}/앱 아이콘/채널비서-아이콘.ico').readAsBytesSync();
      expect(ico.sublist(0, 4), [0, 0, 1, 0]);
      expect(ico.sublist(22, 26), [0x89, 0x50, 0x4E, 0x47]); // 안에 PNG
      await t.pumpWidget(const SizedBox());
    });

    test('내 그림: 사용자 폴더로 복사 (원본을 지워도 그대로), 그림이 아닌 파일은 거절', () async {
      final k = TestKit();
      final u = await k.user();
      final dir = Directory.systemTemp.createTempSync('look');
      final img = File('${dir.path}/me.png')..writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
      u.look.useCustomImage(img.path);
      img.deleteSync();
      expect(u.look.iconId, 'custom');
      expect(File(u.look.customIconPath).existsSync(), isTrue);
      expect(() => u.look.useCustomImage('${dir.path}/a.txt'), throwsA(isA<AppFailure>()));
      await expectLater(u.look.setIcon('rainbow'), throwsA(isA<AppFailure>()));
    });

    test('.ico 만들기', () {
      final ico = pngToIco(Uint8List.fromList([1, 2, 3]));
      expect(ico.length, 22 + 3);
      expect(ico[6], 0); // 256 폭
    });
  });

  group('색 묶음', () {
    for (final p in ColorTheme.values) {
      for (final dark in [false, true]) {
        test('${p.name} ${dark ? '어두움' : '밝음'}: 버튼·보조 버튼 글자 대비 4.5:1 이상', () {
          final t = (dark ? AppTokens.dark() : AppTokens.light()).withPalette(p);
          expect(contrastRatio(t.primary, t.onPrimary), greaterThanOrEqualTo(4.5));
          expect(contrastRatio(t.accent, t.onAccent), greaterThanOrEqualTo(4.5));
          expect(contrastRatio(t.tonal, t.onTonal), greaterThanOrEqualTo(4.5));
          expect(contrastRatio(t.primary, t.card), greaterThanOrEqualTo(3));
        });
      }
    }

    test('고대비 모드에서는 색 묶음보다 대비가 우선', () {
      final c = AppTokens.contrast(darkMode: true);
      expect(c.withPalette(ColorTheme.sunset).primary, c.primary);
    });

    testWidgets('고르면 앱 전체 색이 바로 바뀜', (t) async {
      final (_, s) = await open(t);
      Color primary() => Theme.of(t.element(find.byType(Scaffold).first)).colorScheme.primary;
      final before = primary();
      await toLook(t);
      await tapKey(t, 'choice-ocean');
      expect(s.user!.settings.colorTheme, 'ocean');
      expect(primary(), isNot(before));
      await t.pumpWidget(const SizedBox());
    });
  });
}
