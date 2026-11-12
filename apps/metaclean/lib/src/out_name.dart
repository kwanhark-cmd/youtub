import 'dart:io';

import 'package:intl/intl.dart';

/// 결과 파일의 이름과 시각을 정한다.
///
/// 폰 카메라는 사진 이름을 찍은 날짜로 짓는다(예: 20261112_143000.jpg).
/// 그 이름을 그대로 이어 쓰면 사진 속 날짜를 고치거나 지워도 이름에 옛 날짜가 남는다.

/// 날짜로 지은 파일 이름 (폰 카메라와 같은 형식: 19800101_120000).
String dateStem(DateTime d) => DateFormat('yyyyMMdd_HHmmss').format(d);

/// 확장자를 뗀 이름.
String baseName(String fileName) => fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

// 20261112_143000, 2026-11-12 14.30.00, 20261112-143000123 같은 날짜·시각 덩어리
final _dateLike = RegExp(r'(?:19|20)\d{2}[-_.]?\d{2}[-_.]?\d{2}'
    r'(?:[-_. T]?\d{2}[-_.:]?\d{2}(?:[-_.:]?\d{2,5})?)?');
// 1731393000000 같은 긴 숫자(시각을 숫자로 적은 것)
final _longDigits = RegExp(r'\d{9,}');

/// 파일 이름에서 날짜·시각처럼 보이는 숫자를 뺀다. 남는 글자가 없으면 '사진'.
String scrubDateFromName(String base) {
  final s = base
      .replaceAll(_dateLike, '')
      .replaceAll(_longDigits, '')
      .replaceAll(RegExp(r'[-_. ()]{2,}'), '_')
      .replaceAll(RegExp(r'^[-_. ()]+|[-_. ()]+$'), '');
  return s.isEmpty ? '사진' : s;
}

/// 폴더 안에서 겹치지 않는 파일 경로를 만든다 (겹치면 _2, _3 …).
String uniquePathIn(Directory dir, String stem, String ext) {
  var path = '${dir.path}/$stem.$ext';
  for (var n = 2; File(path).existsSync(); n++) {
    path = '${dir.path}/${stem}_$n.$ext';
  }
  return path;
}

/// 이번 작업의 결과를 담을 새 폴더를 만든다.
///
/// 같은 이름의 결과 파일이 이전 작업 것과 섞이지 않게 작업마다 폴더를 따로 쓴다.
/// 30분이 지난 옛 작업 폴더는 지워서 저장 공간을 차지하지 않게 한다.
Future<Directory> freshRunDir(Directory tmp, String prefix) async {
  final now = DateTime.now().microsecondsSinceEpoch;
  try {
    await for (final e in tmp.list()) {
      final name = e.path.split('/').last;
      if (e is! Directory || !name.startsWith(prefix)) continue;
      final made = int.tryParse(name.substring(prefix.length));
      if (made != null && now - made > const Duration(minutes: 30).inMicroseconds) {
        await e.delete(recursive: true);
      }
    }
  } catch (_) {
    // 정리에 실패해도 작업은 계속한다.
  }
  final dir = Directory('${tmp.path}/$prefix$now');
  await dir.create(recursive: true);
  return dir;
}

/// 파일의 "수정한 날짜"를 맞춘다. 저장소가 허용하지 않으면 그대로 둔다.
Future<void> setFileTime(String path, DateTime t) async {
  try {
    await File(path).setLastModified(t);
  } catch (_) {}
}
