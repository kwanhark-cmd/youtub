import '../../core/db.dart';
import '../../core/strings.dart';
import '../ai/brain.dart';
import '../edits/edit_service.dart';
import '../youtube/youtube_service.dart';
import 'briefing.dart';
import 'memos.dart';
import 'voice_commands.dart';

/// 음성 명령 결과: 읽어 줄 말 + (있으면) 이동할 화면.
class VoiceResult {
  VoiceResult(this.spoken, {this.navigateTo, this.command, this.needsConfirmation = false});
  final String spoken;
  final String? navigateTo; // 'home' | 'channels' | 'produce' | 'review' | 'edits' | 'memos'
  final VoiceCommand? command;
  final bool needsConfirmation;
}

/// 다른 단계 기능이 음성 명령에 답할 수 있게 하는 연결점.
typedef PrivateListProvider = List<String> Function();
typedef MakeContentHandler = Future<String> Function(String channelTitle, ContentFormat format, String topic);

class VoiceController {
  VoiceController({
    required this.youtube,
    required this.edits,
    required this.briefing,
    required this.memos,
    required this.now,
  });

  final YouTubeService youtube;
  final EditService edits;
  final BriefingService briefing;
  final MemoService memos;
  final DateTime Function() now;
  final parser = VoiceCommandParser();

  PrivateListProvider privateList = () => const [];
  MakeContentHandler? makeContent;

  VoiceCommand parse(String text) => parser.parse(text, channelTitles: youtube.channels().map((c) => c.title).toList());

  /// [confirmed] 가 false 이고 중요한 명령이면 실행하지 않고 확인을 요청한다.
  Future<VoiceResult> handle(String text, {bool confirmed = false}) async {
    final cmd = parse(text);
    if (cmd.notAllowed) {
      return VoiceResult(
        cmd.type == CommandType.publish ? S.voicePublishNotAllowed : S.voiceDeleteNotAllowed,
        navigateTo: cmd.type == CommandType.publish ? 'review' : null,
        command: cmd,
      );
    }
    if (cmd.needsConfirmation && !confirmed) {
      final what = switch (cmd.type) {
        CommandType.upload => '확인 대기 목록에서 업로드할 콘텐츠를 고르시겠어요?',
        CommandType.revertToday => '오늘 한 수정을 모두 되돌릴까요?',
        CommandType.runEdits => '지금 영상 수정을 실행할까요? 수정 전 내용은 기록되어 언제든 되돌릴 수 있어요.',
        _ => '실행할까요?',
      };
      return VoiceResult(what, command: cmd, needsConfirmation: true);
    }
    switch (cmd.type) {
      case CommandType.weeklyViews:
        return VoiceResult(
          S.voiceWeeklyViews(youtube.totalViews(), youtube.viewsDelta(7)),
          navigateTo: 'home',
          command: cmd,
        );
      case CommandType.channelSummary:
        return VoiceResult(channelSummary(cmd.channelHint), navigateTo: 'channels', command: cmd);
      case CommandType.readPrivateList:
        final list = privateList();
        return VoiceResult(
          S.voicePrivateList(list.length, list.take(5).join(', ')),
          navigateTo: 'review',
          command: cmd,
        );
      case CommandType.makeContent:
        final h = makeContent;
        if (h == null) return VoiceResult('제작 기능을 준비하고 있어요.', command: cmd);
        final chans = youtube.channels();
        if (chans.isEmpty) return VoiceResult(S.channelNone, navigateTo: 'channels', command: cmd);
        final target = chans.firstWhere(
          (c) => cmd.channelHint.isNotEmpty && c.title.contains(cmd.channelHint),
          orElse: () => chans.first,
        );
        final msg = await h(target.title, cmd.format ?? ContentFormat.shorts, '');
        return VoiceResult(msg, navigateTo: 'produce', command: cmd);
      case CommandType.todayEdits:
        return VoiceResult(edits.dailySummary(dayKey(now())), navigateTo: 'edits', command: cmd);
      case CommandType.revertToday:
        final r = await edits.revertDay(dayKey(now()));
        return VoiceResult(
          '${r.reverted}개를 되돌렸어요.${r.conflicts > 0 ? ' 유튜브에서 직접 바뀐 ${r.conflicts}개는 화면에서 확인해 주세요.' : ''}',
          navigateTo: 'edits',
          command: cmd,
        );
      case CommandType.runEdits:
        var total = 0;
        for (final c in youtube.channels()) {
          final p = await edits.plan(c.channelId);
          total += (await edits.apply(p)).applied;
        }
        return VoiceResult(total == 0 ? S.editsNone : S.editsDone(total), navigateTo: 'edits', command: cmd);
      case CommandType.briefing:
        final b = briefing.compose();
        briefing.markDone();
        return VoiceResult(b.spoken, navigateTo: 'home', command: cmd);
      case CommandType.memo:
        if (cmd.text.isEmpty) return VoiceResult('남길 내용을 "메모" 다음에 말씀해 주세요.', command: cmd);
        memos.add(cmd.text);
        return VoiceResult(S.voiceMemoSaved, navigateTo: 'memos', command: cmd);
      case CommandType.upload:
        return VoiceResult('확인 대기 목록을 열게요. 올릴 콘텐츠의 "올리기" 버튼을 눌러 주세요.', navigateTo: 'review', command: cmd);
      case CommandType.help:
        return VoiceResult(S.voiceHelp, command: cmd);
      case CommandType.publish:
      case CommandType.delete:
      case CommandType.unknown:
        return VoiceResult(S.voiceUnknown, command: cmd);
    }
  }

  String channelSummary([String hint = '']) {
    final chans = youtube.channels().where((c) => hint.isEmpty || c.title.contains(hint)).toList();
    if (chans.isEmpty) return S.channelNone;
    final b = StringBuffer('채널 ${chans.length}개. ');
    for (final c in chans.take(10)) {
      b.write('${c.title}, ${S.subscribers(c.subscriberCount)}, ${S.views(c.viewCount)}. ');
    }
    if (chans.length > 10) b.write('외 ${chans.length - 10}개 채널이 더 있어요.');
    return b.toString().trim();
  }
}
