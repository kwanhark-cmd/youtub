import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// 썸네일 문구로 1280×720 썸네일 그림(PNG)을 만든다. 앱에 들어 있는 한국어 글꼴을 쓴다.
Future<Uint8List> renderThumbnail(String text, {int seed = 0}) async {
  const w = 1280.0, h = 720.0;
  const palettes = [
    [Color(0xFFD32F2F), Color(0xFF6A1B9A)],
    [Color(0xFF1565C0), Color(0xFF00897B)],
    [Color(0xFFEF6C00), Color(0xFFC62828)],
    [Color(0xFF2E7D32), Color(0xFF1565C0)],
  ];
  final colors = palettes[seed.abs() % palettes.length];
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(
    const Rect.fromLTWH(0, 0, w, h),
    Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(w, h), colors),
  );
  final tp = TextPainter(
    text: TextSpan(
      text: text.trim().isEmpty ? '오늘의 이야기' : text.trim(),
      style: const TextStyle(
        fontFamily: 'NotoSansKR',
        fontSize: 130,
        fontWeight: FontWeight.w900,
        color: Color(0xFFFFFFFF),
        height: 1.15,
        shadows: [Shadow(color: Color(0x99000000), offset: Offset(6, 6), blurRadius: 12)],
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    maxLines: 3,
    ellipsis: '…',
  )..layout(maxWidth: w - 140);
  tp.paint(c, Offset((w - tp.width) / 2, (h - tp.height) / 2));
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
