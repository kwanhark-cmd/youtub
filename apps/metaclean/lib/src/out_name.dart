import 'dart:io';

import 'package:intl/intl.dart';

import 'photo_edit.dart' show DateAction;

/// 결과 파일의 이름을 정한다.
///
/// 폰 카메라는 사진 이름을 찍은 날짜로 짓는다(예: 20261112_143000.jpg).
/// 그 이름을 그대로 이어 쓰면 사진 속 날짜를 고치거나 지워도 이름에 옛 날짜가 남는다.
/// 그래서 날짜를 지운 결과는 원본 이름을 아예 쓰지 않고, 날짜를 바꾼 결과는
/// 바꾼 날짜로 이름을 짓는다.

/// 날짜로 지은 파일 이름 (폰 카메라와 같은 형식: 19800101_120000).
String dateStem(DateTime d) => DateFormat('yyyyMMdd_HHmmss').format(d);

/// 확장자를 뗀 이름.
String baseName(String fileName) => fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

/// 파일 내용에서 뽑은 짧은 구분 글자(6자).
///
/// 시각이나 기기와 무관하고, 내용이 같으면 늘 같다. 서로 다른 사진이 같은 이름을
/// 갖지 않게 이름 끝에 붙인다. (이름이 같으면 공유할 때 주소가 같아져 다른 사진과
/// 섞일 수 있고, 갤러리가 이름을 제멋대로 바꾼다.)
String contentTag(List<int> bytes) {
  var h = 0x811C9DC5; // FNV-1a 32비트
  for (final b in bytes) {
    h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
  }
  final folded = (h >> 24) ^ (h & 0xFFFFFF);
  return folded.toRadixString(16).padLeft(6, '0');
}

/// "사진 지우기" 결과 이름. 원본 이름(찍은 날짜·기기 표시가 들어 있다)은 쓰지 않는다.
String cleanStem(List<int> out) => '사진_${contentTag(out)}';

/// "사진 수정" 결과 이름.
///
/// - 날짜를 바꿈: 바꾼 날짜로 짓는다 (사진 속 날짜와 이름이 같아진다)
/// - 날짜를 지움: 원본 이름을 쓰지 않는다
/// - 날짜를 그대로 둠: 원본 이름을 잇는다
String editStem({
  required DateAction dateAction,
  DateTime? date,
  required String originalName,
  required List<int> out,
}) {
  final tag = contentTag(out);
  switch (dateAction) {
    case DateAction.change:
      return '${dateStem(date!)}_$tag';
    case DateAction.remove:
      return '사진_$tag';
    case DateAction.keep:
      final base = baseName(originalName);
      return base.isEmpty ? '사진_$tag' : '${base}_$tag';
  }
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
