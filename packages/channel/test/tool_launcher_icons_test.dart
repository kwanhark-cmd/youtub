@Tags(['tool'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:channel_biseo/features/settings/app_look.dart';
import 'package:channel_biseo/ui/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 안드로이드 홈 화면 아이콘 5가지 만들기 → android/app/src/main/res/mipmap-*/ic_launcher_<색>.png
/// 실행: MAKE_ICONS=1 flutter test --run-skipped --tags tool test/tool_launcher_icons_test.dart
void main() {
  test('launcher icons', () async {
    if (Platform.environment['MAKE_ICONS'] != '1') return;
    const sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
    for (final id in AppLook.builtInIcons) {
      for (final e in sizes.entries) {
        final rec = ui.PictureRecorder();
        AppIconPainter(Color(AppLook.iconColors[id]!)).paint(Canvas(rec), Size(e.value.toDouble(), e.value.toDouble()));
        final img = await rec.endRecording().toImage(e.value, e.value);
        final png = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        final dir = 'android/app/src/main/res/mipmap-${e.key}';
        File('$dir/ic_launcher_$id.png').writeAsBytesSync(png);
        // 기본 아이콘(설치 직후)도 파랑으로
        if (id == 'blue') File('$dir/ic_launcher.png').writeAsBytesSync(png);
      }
    }
  });
}
