import '../ai/brain.dart';

enum CommandType {
  weeklyViews,
  channelSummary,
  readPrivateList,
  makeContent,
  todayEdits,
  revertToday,
  briefing,
  memo,
  runEdits,
  upload,
  publish,
  delete,
  help,
  unknown,
}

class VoiceCommand {
  VoiceCommand(this.type, {this.channelHint = '', this.format, this.text = ''});
  final CommandType type;
  final String channelHint;
  final ContentFormat? format;
  final String text;

  /// 실행 전에 화면과 음성으로 다시 확인해야 하는 중요한 명령.
  bool get needsConfirmation =>
      type == CommandType.upload || type == CommandType.revertToday || type == CommandType.runEdits;

  /// 안전을 위해 앱이 아예 하지 않는 명령 (안내만 한다).
  bool get notAllowed => type == CommandType.publish || type == CommandType.delete;
}

/// 기기 안에서 동작하는 한국어 명령 해석기 (추가 비용 없음).
class VoiceCommandParser {
  static String _norm(String s) => s.replaceAll(RegExp(r'[\s.,!?~]+'), ' ').trim();

  static bool _has(String s, List<String> words) => words.any(s.contains);

  VoiceCommand parse(String raw, {List<String> channelTitles = const []}) {
    final s = _norm(raw);
    if (s.isEmpty) return VoiceCommand(CommandType.unknown);

    // 메모: "메모 ...", "메모해 줘 ...", "기억해 ..."
    final memo = RegExp(r'^(메모|기록|기억)(해\s?줘|해|하기|해 둬)?\s*(.*)$').firstMatch(s);
    if (memo != null) {
      return VoiceCommand(CommandType.memo, text: (memo.group(3) ?? '').trim());
    }

    // 안전상 하지 않는 명령을 먼저 걸러 낸다.
    if (_has(s, ['삭제', '지워']) && _has(s, ['영상', '동영상', '비디오', '글'])) {
      return VoiceCommand(CommandType.delete);
    }
    if (_has(s, ['공개로', '공개 전환', '공개해', '공개 해', '공개로 바꿔', '게시해']) && !s.contains('비공개')) {
      return VoiceCommand(CommandType.publish);
    }

    if (_has(s, ['도움말', '뭘 할 수', '무엇을 할 수', '사용법'])) return VoiceCommand(CommandType.help);
    if (_has(s, ['브리핑'])) return VoiceCommand(CommandType.briefing);
    if (_has(s, ['비공개', '확인 대기', '확인대기'])) return VoiceCommand(CommandType.readPrivateList);
    if (_has(s, ['업로드', '올려'])) {
      return VoiceCommand(CommandType.upload, channelHint: _channel(s, channelTitles));
    }
    if (_has(s, ['되돌려', '되돌리', '원래대로'])) return VoiceCommand(CommandType.revertToday);
    if (_has(s, ['수정 내역', '수정내역', '뭐 고쳤', '뭘 고쳤', '수정한 것', '수정 요약'])) {
      return VoiceCommand(CommandType.todayEdits);
    }
    if (_has(s, ['수정 실행', '수정해', '고쳐', '다듬어'])) return VoiceCommand(CommandType.runEdits);

    final format = _format(s);
    if (_has(s, ['만들어', '만들기', '제작', '찍어', '써 줘', '써줘']) || (format != null && _has(s, ['하나', '한 개', '한개']))) {
      return VoiceCommand(
        CommandType.makeContent,
        channelHint: _channel(s, channelTitles),
        format: format ?? ContentFormat.shorts,
      );
    }
    if (_has(s, ['조회수', '조회 수', '구독자'])) {
      if (_has(s, ['이번 주', '이번주', '일주일', '주간'])) return VoiceCommand(CommandType.weeklyViews);
      return VoiceCommand(CommandType.channelSummary, channelHint: _channel(s, channelTitles));
    }
    if (_has(s, ['현황', '요약', '어때', '어떻게 돼'])) return VoiceCommand(CommandType.channelSummary);
    return VoiceCommand(CommandType.unknown, text: s);
  }

  static ContentFormat? _format(String s) {
    if (_has(s, ['쇼츠', '숏츠', '짧은 영상'])) return ContentFormat.shorts;
    if (_has(s, ['다큐'])) return ContentFormat.docu;
    if (_has(s, ['롱폼', '긴 영상'])) return ContentFormat.long;
    if (_has(s, ['사진', '이미지', '게시물'])) return ContentFormat.image;
    if (_has(s, ['대화형', '대화', '팟캐스트'])) return ContentFormat.talk;
    return null;
  }

  /// "요리 채널" → 채널 제목에 "요리" 가 들어간 채널.
  static String _channel(String s, List<String> titles) {
    final m = RegExp(r'(\S+)\s?채널').firstMatch(s);
    final word = m?.group(1) ?? '';
    if (word.isNotEmpty) {
      for (final t in titles) {
        if (t.contains(word)) return t;
      }
      return word;
    }
    for (final t in titles) {
      for (final w in t.split(' ')) {
        if (w.length >= 2 && s.contains(w)) return t;
      }
    }
    return '';
  }
}
