@Tags(['tool'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:channel_biseo/ui/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 마스코트 그림 파일(assets/icons3d/mascot_*.png)을 만든다.
/// 실행: flutter test --tags tool test/tool_mascot_test.dart  (평소 테스트에서는 건너뜀)
void main() {
  test('마스코트 PNG 만들기', () async {
    if (Platform.environment['MAKE_ASSETS'] != '1') return;
    for (final m in MascotMood.values) {
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      MascotPainter(m).paint(c, const ui.Size(256, 256));
      final img = await rec.endRecording().toImage(256, 256);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('assets/icons3d/mascot_${m.name}.png').writeAsBytesSync(data!.buffer.asUint8List());
    }
  });
}
