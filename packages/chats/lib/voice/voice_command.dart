/// 말로 한 명령을 알아듣습니다. 알아듣지 못하면 검색으로 처리합니다.
sealed class VoiceCommand {
  const VoiceCommand();

  /// 실행 전에 확인이 필요한 명령(지우기·합치기).
  bool get needsConfirm => false;
}

class SearchCommand extends VoiceCommand {
  final String text;
  const SearchCommand(this.text);
}

class MoveToTopicCommand extends VoiceCommand {
  final String topic;
  const MoveToTopicCommand(this.topic);
}

class MergeTopicsCommand extends VoiceCommand {
  final String from;
  final String into;
  const MergeTopicsCommand(this.from, this.into);
  @override
  bool get needsConfirm => true;
}

class DeleteConversationCommand extends VoiceCommand {
  const DeleteConversationCommand();
  @override
  bool get needsConfirm => true;
}

class ClassifyRecentCommand extends VoiceCommand {
  final bool todayOnly;
  const ClassifyRecentCommand({this.todayOnly = true});
}

class AddNoteCommand extends VoiceCommand {
  final String text;
  const AddNoteCommand(this.text);
}

class ReadAloudCommand extends VoiceCommand {
  const ReadAloudCommand();
}

class StopReadingCommand extends VoiceCommand {
  const StopReadingCommand();
}

class StarCommand extends VoiceCommand {
  const StarCommand();
}

class GoHomeCommand extends VoiceCommand {
  const GoHomeCommand();
}

class VoiceCommandParser {
  static String _clean(String s) => s.trim().replaceAll(RegExp(r'[.!?~]+$'), '').replaceAll(RegExp(r'\s+'), ' ');

  static VoiceCommand parse(String input) {
    final t = _clean(input);
    RegExpMatch? m;

    m = RegExp(r'^(?:메모|기록)\s*(?:해\s*줘|해줘|남겨\s*줘|남겨줘)?\s*[:：]?\s*(.+)$').firstMatch(t);
    if (m != null && m.group(1)!.trim().isNotEmpty) return AddNoteCommand(m.group(1)!.trim());
    m = RegExp(r'^(.+?)\s*(?:라고|이라고)\s*메모(?:해\s*줘|해줘|해)?$').firstMatch(t);
    if (m != null) return AddNoteCommand(m.group(1)!.trim());

    m = RegExp(r'(?:이\s*대화(?:를|는)?\s*)?[\"“]?(.+?)[\"”]?\s*주제(?:로|에)\s*(?:옮겨|이동|넣어|보내)').firstMatch(t);
    if (m != null) {
      final name = m.group(1)!.replaceFirst(RegExp(r'^이\s*대화(를|는)?\s*'), '').trim();
      if (name.isNotEmpty) return MoveToTopicCommand(name);
    }

    m = RegExp(r'^(.+?)\s*주제(?:를|와|랑|하고)\s*(.+?)\s*주제(?:로|와|랑|에)?\s*(?:합쳐|합치|병합)').firstMatch(t);
    if (m != null) return MergeTopicsCommand(m.group(1)!.trim(), m.group(2)!.trim());

    if (RegExp(r'(이\s*대화).*(지워|삭제)').hasMatch(t) || RegExp(r'^(지워|삭제)(\s*해\s*줘)?$').hasMatch(t)) {
      return const DeleteConversationCommand();
    }

    if (RegExp(r'(오늘|방금|새로)\s*(가져온|넣은|들어온)\s*대화.*(정리|분류)').hasMatch(t)) {
      return const ClassifyRecentCommand(todayOnly: true);
    }
    if (RegExp(r'^(전부|모두|다)\s*(정리|분류)').hasMatch(t) || RegExp(r'대화\s*(전부|모두)\s*(정리|분류)').hasMatch(t)) {
      return const ClassifyRecentCommand(todayOnly: false);
    }

    if (RegExp(r'(그만|멈춰|중지|조용)').hasMatch(t) && t.length <= 12) return const StopReadingCommand();
    if (RegExp(r'(읽어\s*줘|읽어줘|소리\s*내어|들려\s*줘)').hasMatch(t) && t.length <= 20) return const ReadAloudCommand();
    if (RegExp(r'^(별표|즐겨찾기)').hasMatch(t)) return const StarCommand();
    if (RegExp(r'^(처음|홈)\s*(화면)?(으로)?').hasMatch(t) && t.length <= 10) return const GoHomeCommand();

    return SearchCommand(t);
  }
}
