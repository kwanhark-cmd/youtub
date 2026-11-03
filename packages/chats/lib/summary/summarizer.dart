import '../models/models.dart';

class Decision {
  final String text;
  final DateTime when;
  final int conversationId;
  final String conversationTitle;
  final AiSource source;
  const Decision(this.text, this.when, this.conversationId, this.conversationTitle, this.source);
}

/// 비용 없이 만드는 간단한 요약과 "정한 내용" 찾기.
class OfflineSummarizer {
  static final _decisionPattern = RegExp(r'(하기로|기로 (했|정했|결정)|결정(했|하였|함|이에요|입니다)|정했|확정|최종(적으로)?|으로 정함|로 정함|로 할게|으로 할게|로 하자|으로 하자|채택|선택했)');
  static final _sentenceSplit = RegExp(r'(?<=[.!?。])\s+|\n+');

  static String summarize(String title, List<Message> msgs) {
    final firstUser = msgs.firstWhere(
      (m) => m.role == Role.user && m.text.trim().isNotEmpty,
      orElse: () => const Message(role: Role.user, text: ''),
    );
    final ask = _firstSentence(firstUser.text, 50);
    final decisions = decisionsIn(msgs);
    final buf = StringBuffer(ask.isEmpty ? title : ask);
    if (decisions.isNotEmpty) {
      buf.write(' → ');
      buf.write(_clip(decisions.last, 50));
    } else {
      final firstAnswer = msgs.firstWhere(
        (m) => m.role == Role.assistant && m.text.trim().isNotEmpty,
        orElse: () => const Message(role: Role.assistant, text: ''),
      );
      final a = _firstSentence(firstAnswer.text, 50);
      if (a.isNotEmpty) buf.write(' → $a');
    }
    return buf.toString();
  }

  static List<String> decisionsIn(List<Message> msgs) {
    final out = <String>[];
    for (final m in msgs) {
      for (final raw in m.text.split(_sentenceSplit)) {
        final s = raw.trim();
        if (s.length < 4 || s.length > 160) continue;
        if (_decisionPattern.hasMatch(s) && !out.contains(s)) out.add(s);
      }
    }
    return out;
  }

  static String _firstSentence(String text, int max) {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return '';
    final m = RegExp(r'^(.+?[.!?。])(\s|$)').firstMatch(t);
    return _clip(m?.group(1) ?? t, max);
  }

  static String _clip(String s, int max) => s.length > max ? '${s.substring(0, max)}…' : s;
}
