@Tags(['tool'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/features/ai/brain.dart';
import 'package:channel_biseo/features/production/thumbnail.dart';
import 'package:channel_biseo/stages.dart';
import 'package:channel_biseo/ui/produce_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 화면 사진 만들기 → docs/화면/<이름>-<밝음|어두움>.png
/// 실행: SHOTS=1 flutter test test/tool_screens_test.dart   (평소에는 건너뜀)
final _on = Platform.environment['SHOTS'] == '1';
final _out = Platform.environment['SHOTS_DIR'] ?? '../docs/화면';
final _only = Platform.environment['SHOTS_ONLY'];

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final f = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    await f.load();
  }

  await load('NotoSansKR', 'assets/fonts/NotoSansKR.ttf');
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  await load('MaterialIcons', '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
}

class Shot {
  Shot(this.name, this.open);
  final String name;

  /// 앱을 띄운 뒤 그 화면으로 가는 동작.
  final Future<void> Function(WidgetTester t, AppState s, TestKit k) open;
}

final _key = GlobalKey();

Future<void> _capture(WidgetTester t, String file) async {
  await t.runAsync(() async {
    // 그림 파일 미리 읽기
    final ctx = _key.currentContext!;
    final dir = Directory('assets/icons3d');
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.png'))) {
      await precacheImage(AssetImage('assets/icons3d/${f.uri.pathSegments.last}'), ctx);
    }
  });
  await t.pumpAndSettle();
  final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await t.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 1.5);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  File(file)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
}

Future<void> tapKey(WidgetTester t, String key) async {
  final f = find.byKey(Key(key));
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f, warnIfMissed: false);
  await t.pumpAndSettle();
}

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text).last;
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f, warnIfMissed: false);
  await t.pumpAndSettle();
}

Future<void> navIcon(WidgetTester t, IconData icon) async {
  await t.tap(find.byIcon(icon).last);
  await t.pumpAndSettle();
}

final shots = <Shot>[
  Shot('01-로그인', (t, s, k) async {
    s.logout();
    await t.pumpAndSettle();
  }),
  Shot('02-첫실행안내', (t, s, k) async {
    s.user!.settings.onboardingDone = false;
    s.refresh();
    await t.pumpAndSettle();
  }),
  Shot('03-홈', (t, s, k) async {}),
  Shot('04-채널현황', (t, s, k) async => navIcon(t, Icons.video_library)),
  Shot('05-채널상세', (t, s, k) async {
    await navIcon(t, Icons.video_library);
    await tapKey(t, 'channel-UC_mock_cook');
  }),
  Shot('06-수정내역', (t, s, k) async => tapKey(t, 'open-edits')),
  Shot('07-콘텐츠제작', (t, s, k) async => navIcon(t, Icons.movie_creation)),
  Shot('08-제작상세', (t, s, k) async {
    await navIcon(t, Icons.movie_creation);
    await tapKey(t, 'production-1');
  }),
  Shot('09-확인대기', (t, s, k) async {
    await navIcon(t, Icons.movie_creation);
    await tapKey(t, 'open-review');
  }),
  Shot('10-블로그', (t, s, k) async => navIcon(t, Icons.rss_feed)),
  Shot('11-내코너', (t, s, k) async => navIcon(t, Icons.auto_stories)),
  Shot('12-설정', (t, s, k) async => navIcon(t, Icons.settings)),
  Shot('13-게시달력', (t, s, k) async {
    await navIcon(t, Icons.movie_creation);
    await tapKey(t, 'open-calendar');
  }),
];

Future<(TestKit, AppState)> _prepare(WidgetTester t) async {
  registerStages();
  final k = TestKit();
  final s = AppState(k.env);
  await s.login(k.env.accounts.create('김사장', '1234'));
  final u = s.user!;
  u.settings.onboardingDone = true;
  await u.youtube.connectGoogle();
  for (final c in u.youtube.channels()) {
    await u.youtube.syncChannel(c.channelId);
  }
  await u.edits.apply(await u.edits.plan('UC_mock_cook'));
  final ps = productionOf(u);
  final p1 = await ps.create(channelId: 'UC_mock_cook', format: ContentFormat.shorts, topic: '김치찌개 끓이기');
  await t.runAsync(() => ps.makeThumbnail(p1.id, (text, seed) => renderThumbnail(text, seed: seed)));
  final p2 = await ps.create(channelId: 'UC_mock_trip', format: ContentFormat.long, topic: '제주 바다 산책');
  final v = File('${Directory.systemTemp.createTempSync('shot').path}/v.mp4')..writeAsBytesSync([1]);
  ps.attachOwnVideo(p2.id, v.path);
  await ps.uploadPrivate(p2.id, userConfirmed: true, aiLabelMethod: 'setting');
  u.memos.add('다음 주에 강릉 커피거리 영상 찍기');
  return (k, s);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final dark in [false, true]) {
    for (final shot in shots) {
      if (_only != null && !shot.name.contains(_only!)) continue;
      testWidgets('${shot.name} ${dark ? '어두움' : '밝음'}', (t) async {
        if (!_on) return;
        await _loadFonts();
        debugDisableShadows = false; // 실제 기기처럼 그림자 그리기
        t.view.physicalSize = Size(390 * 3, double.parse(Platform.environment['SHOTS_H'] ?? '844') * 3);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        final (k, s) = await _prepare(t);
        s.setView(themeMode: dark ? 'dark' : 'light');
        await t.pumpWidget(
          RepaintBoundary(
            key: _key,
            child: ChannelBiseoApp(state: s),
          ),
        );
        await t.pumpAndSettle();
        await shot.open(t, s, k);
        await _capture(t, '$_out/${shot.name}-${dark ? '어두움' : '밝음'}.png');
        await t.pumpWidget(const SizedBox());
        debugDisableShadows = true;
      });
    }
  }
}
