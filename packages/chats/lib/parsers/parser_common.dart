import '../models/models.dart';

/// 파서 결과. 읽지 못한 항목은 건너뛰고 개수만 셉니다.
class ParseResult {
  final AiSource source;
  final List<ParsedConversation> conversations;
  final int skipped;
  final List<String> notices;

  const ParseResult({required this.source, required this.conversations, this.skipped = 0, this.notices = const []});
}

/// 파일을 전혀 읽을 수 없을 때. [hint]에는 대화 내용이 아닌 구조 정보만 담습니다.
enum UnreadableKind { unknown, expiredLink, empty }

class UnreadableFileException implements Exception {
  final String hint;
  final UnreadableKind kind;
  const UnreadableFileException(this.hint, {this.kind = UnreadableKind.unknown});
  @override
  String toString() => 'UnreadableFileException($hint)';
}

DateTime? parseAnyTime(dynamic v) {
  if (v == null) return null;
  if (v is num) {
    // 초 단위(ChatGPT) 또는 밀리초 단위
    final ms = v > 100000000000 ? v.toInt() : (v * 1000).round();
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  }
  if (v is String) {
    final d = DateTime.tryParse(v);
    return d?.toLocal();
  }
  return null;
}

String makeTitle(String? raw, List<Message> msgs) {
  final t = raw?.trim() ?? '';
  if (t.isNotEmpty) return t;
  final first = msgs.firstWhere(
    (m) => m.role == Role.user && m.text.trim().isNotEmpty,
    orElse: () => const Message(role: Role.user, text: ''),
  );
  final s = first.text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return '제목 없는 대화';
  return s.length > 40 ? '${s.substring(0, 40)}…' : s;
}

/// 구조 정보만 담은 짧은 설명(문제 신고용, 본문 없음).
String describeStructure(dynamic decoded) {
  if (decoded is List) {
    final first = decoded.isEmpty ? null : decoded.first;
    if (first is Map) {
      return '목록(${decoded.length}개), 항목 키: ${first.keys.take(12).join(',')}';
    }
    return '목록(${decoded.length}개)';
  }
  if (decoded is Map) {
    return '객체, 키: ${decoded.keys.take(12).join(',')}';
  }
  return decoded.runtimeType.toString();
}
