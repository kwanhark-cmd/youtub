import 'dart:typed_data';

/// 다룰 수 있는 문서 종류.
enum DocKind {
  /// PDF
  pdf,

  /// 워드·엑셀·파워포인트 (docx/xlsx/pptx)
  ooxml,

  /// 한글 (hwpx)
  hwpx,

  /// 한글(hwp)·옛 오피스(doc/xls/ppt)
  cfb,
}

/// 일부 수정할 내용. null인 칸은 손대지 않는다.
class DocEdit {
  const DocEdit({this.title, this.author, this.date, this.program});

  final String? title;
  final String? author;
  final DateTime? date;

  /// 문서를 만든 프로그램·기기 이름 (예: 어떤 컴퓨터 프로그램으로 만들었는지).
  final String? program;

  bool get isEmpty =>
      title == null && author == null && date == null && program == null;
}

/// 처리 결과.
class DocOutput {
  const DocOutput(this.bytes, [this.notes = const []]);

  final Uint8List bytes;

  /// 사용자에게 알려 줄 참고 사항.
  final List<String> notes;
}

/// 처리할 수 없는 문서.
class DocUnsupported implements Exception {
  const DocUnsupported(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 화면에 보일 날짜 글자.
String showDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final l = d.toLocal();
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

/// 한글 프로그램이 쓰는 날짜 글자 (예: 2026년 11월 10일 화요일 오전 9:30:00).
String koreanDateString(DateTime d) {
  const days = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
  String two(int n) => n.toString().padLeft(2, '0');
  final ampm = d.hour < 12 ? '오전' : '오후';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.year}년 ${d.month}월 ${d.day}일 ${days[d.weekday - 1]} '
      '$ampm $h:${two(d.minute)}:${two(d.second)}';
}
