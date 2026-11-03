import '../data/models.dart';

/// 제미나이(또는 다른 곳)에서 정리한 글을 물건 목록으로 바꿉니다.
/// 예)  "- 커피 머신: 판매 (잘 작동함)"  "2. 낡은 의자 → 폐기"  "책상 / 지금 사용"
class ImportedLine {
  String name;
  Decision? decision;
  String note;
  String room;
  bool selected;
  ImportedLine({required this.name, this.decision, this.note = '', this.room = '', this.selected = true});
}

final _bullet = RegExp(r'^\s*(?:[-*•·▪◦]|\d+[.)]|[①-⑳])\s*');
final _roomHeader = RegExp(r'^\s*(?:#+\s*)?\[?([가-힣A-Za-z ]{1,10}(?:방|실|거실|주방|부엌|베란다|현관|창고|다용도실))\]?\s*:?\s*$');

Decision? _decisionIn(String s) {
  if (RegExp(r'폐기|버리|버림|처분|분리수거|나눔|기부').hasMatch(s)) return Decision.discard;
  if (RegExp(r'판매|팔기|팔아|중고|당근|번개').hasMatch(s)) return Decision.sell;
  if (RegExp(r'사용|쓰는|쓸 것|유지|남기|keep', caseSensitive: false).hasMatch(s)) return Decision.use;
  return null;
}

/// 표 형식(쉼표·탭) 목록: 첫 줄이 "이름,분류,..." 같은 머리글이면 칸으로 읽음
List<ImportedLine>? _parseTable(String text) {
  final rows = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
  if (rows.length < 2) return null;
  final sep = rows.first.contains('\t') ? '\t' : ',';
  final head = rows.first.split(sep).map((h) => h.trim()).toList();
  final ni = head.indexWhere((h) => RegExp(r'이름|물건|name', caseSensitive: false).hasMatch(h));
  if (ni < 0) return null;
  final di = head.indexWhere((h) => RegExp(r'분류|결정|decision', caseSensitive: false).hasMatch(h));
  final ri = head.indexWhere((h) => RegExp(r'방|장소|위치|room', caseSensitive: false).hasMatch(h));
  final mi = head.indexWhere((h) => RegExp(r'메모|설명|상태|note', caseSensitive: false).hasMatch(h));
  String at(List<String> c, int i) => i >= 0 && i < c.length ? c[i].trim().replaceAll('"', '') : '';
  return [
    for (final r in rows.skip(1))
      if (at(r.split(sep), ni).isNotEmpty)
        ImportedLine(name: at(r.split(sep), ni), decision: _decisionIn(at(r.split(sep), di)), room: at(r.split(sep), ri), note: at(r.split(sep), mi)),
  ];
}

List<ImportedLine> parseImportText(String text) {
  final table = _parseTable(text);
  if (table != null) return table;
  final out = <ImportedLine>[];
  var room = '';
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    var line = raw.trim();
    if (line.isEmpty) continue;
    final h = _roomHeader.firstMatch(line);
    if (h != null) {
      room = h.group(1)!.trim();
      continue;
    }
    line = line.replaceFirst(_bullet, '').replaceAll('**', '').trim();
    if (line.isEmpty) continue;
    // 이름과 나머지 나누기  ":", "→", "->", "/", "-", "|"
    final parts = line.split(RegExp(r'\s*(?::|→|->|=>|\||/|\s-\s)\s*'));
    final name = parts.first.replaceAll(RegExp(r'[()\[\]]'), '').trim();
    if (name.isEmpty || name.length > 40) continue;
    final rest = parts.skip(1).join(' ').trim();
    var decision = _decisionIn(rest);
    var note = rest;
    final paren = RegExp(r'\(([^)]*)\)').firstMatch(line);
    if (paren != null) note = paren.group(1)!.trim();
    if (decision == null && parts.length == 1) {
      decision = _decisionIn(line);
    }
    // 헤더처럼 보이는 줄(분류 이름만 있는 줄)은 건너뜀
    if (RegExp(r'^(판매|폐기|사용|지금 쓰는 것)( 목록)?$').hasMatch(name)) continue;
    out.add(
      ImportedLine(
        name: name,
        decision: decision,
        note: note == rest && decision != null ? note.replaceAll(RegExp(r'판매|폐기|사용|지금 쓰는 것'), '').replaceAll(RegExp(r'[()]'), '').trim() : note,
        room: room,
      ),
    );
  }
  return out;
}
