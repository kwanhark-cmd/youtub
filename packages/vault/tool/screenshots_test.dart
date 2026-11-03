// 보고서용 화면 캡처 도구(일반 테스트에는 포함되지 않음).
// 실행: flutter test tool/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:account_vault/logic/alerts.dart';
import 'package:account_vault/ui/app.dart';
import 'package:account_vault/ui/screens/accounts_screens.dart';

import 'package:account_vault/ui/screens/cleanup_screens.dart';
import 'package:account_vault/ui/screens/subscriptions_screens.dart';
import 'package:account_vault/ui/screens/settings_screens.dart';
import 'package:account_vault/ui/screens/voice_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/fakes.dart';

Future<void> loadFonts() async {
  final kr = FontLoader('NotoSansKR')
    ..addFont(rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/NotoSansKR-Bold.ttf'));
  await kr.load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/opt/sdk/flutter';
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.view(
          File(
            '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytesSync().buffer,
        ),
      ),
    );
  await icons.load();
}

Future<void> shot(WidgetTester tester, String name) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump(const Duration(milliseconds: 150));
  }
  final ro = tester.renderObject(find.byType(MaterialApp).first);
  RenderObject? node = ro;
  while (node != null && node is! RenderRepaintBoundary) {
    node = node.parent;
  }
  final boundary = node! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 2);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('docs/screenshots/$name.png')..createSync(recursive: true);
    f.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('screenshots', (tester) async {
    await tester.runAsync(loadFonts);
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late TestRig rig;
    await tester.runAsync(() async {
      rig = await TestRig.create();
      await rig.controller.updateSettings((s) => s.autoLockSeconds = 0);
    });
    await tester.pumpWidget(
      RepaintBoundary(child: VaultApp(controller: rig.controller)),
    );
    await shot(tester, '01_첫실행');

    await tester.runAsync(() async {
      await rig.controller.createProfile('엄마', 'fake-master-phrase-1');
      rig.controller.endOnboarding();
      await rig.controller.mutate((d) {
        final s = sampleData(rig.controller.now());
        d.subscriptions.addAll(
          s.subscriptions.where((x) => !x.serviceName.startsWith('아주')),
        );
        d.credits.addAll(s.credits);
        d.accounts.addAll(s.accounts);
        markSeen(d, computeAlerts(d, rig.controller.now()));
      });
    });
    await shot(tester, '02_홈');

    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    for (final (name, w) in [
      ('03_구독', const SubscriptionsScreen() as Widget),
      (
        '04_계정상세',
        AccountDetailScreen(id: rig.controller.data.accounts.first.id),
      ),
      ('05_정리도우미', const CleanupScreen()),
      ('06_음성비서', const VoiceScreen()),
      ('10_건강보고서', const HealthScreen()),
      ('11_설정', const SettingsScreen()),
      ('12_지메일도우미', const GmailSettingsScreen()),
      ('13_계정목록', const AccountsScreen()),
    ]) {
      nav.push(MaterialPageRoute(builder: (_) => w));
      await shot(tester, name);
      nav.pop();
      await shot(tester, '_tmp');
    }

    await tester.runAsync(
      () => rig.controller.updateSettings((s) => s.themeMode = 'dark'),
    );
    await shot(tester, '07_홈_어두운모드');
    await tester.runAsync(
      () => rig.controller.updateSettings((s) => s.themeMode = 'contrast'),
    );
    await shot(tester, '08_홈_고대비');
    await tester.runAsync(() async {
      await rig.controller.updateSettings((s) => s.themeMode = 'light');
      await rig.controller.lock();
    });
    await shot(tester, '09_잠금화면');
    File('docs/screenshots/_tmp.png').deleteSync();
    rig.dispose();
  });
}
