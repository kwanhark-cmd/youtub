import 'dart:async';

import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../app/assistant_state.dart';
import 'widgets.dart';

/// 소리로 읽기. 기기가 못 하면 조용히 넘어간다(글자로는 항상 보인다).
class Speaker {
  static FlutterTts? _tts;
  static Future<void> say(String text) async {
    try {
      _tts ??= FlutterTts();
      await _tts!.setLanguage('ko-KR');
      await _tts!.speak(Redact.text(text));
    } catch (e) {
      CoreLog.warn('소리 읽기 못 함: $e');
    }
  }

  static Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}

/// 마이크 하나로 다섯 모듈 명령. 마이크가 안 되는 기기는 글자 입력칸으로 자동 대체.
class VoiceSheet extends StatefulWidget {
  const VoiceSheet({super.key, required this.state, required this.today, required this.openModule});
  final AssistantState state;
  final Map<ModuleId, List<TodayItem>> today;
  final Future<void> Function(ModuleId) openModule;

  static Future<void> show(BuildContext context, AssistantState s, {required Map<ModuleId, List<TodayItem>> today, required Future<void> Function(ModuleId) openModule}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: VoiceSheet(state: s, today: today, openModule: openModule),
      ),
    );
  }

  @override
  State<VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<VoiceSheet> {
  final _text = TextEditingController();
  final _stt = SpeechToText();
  bool? _micOk;
  bool _listening = false;
  String _answer = '무엇을 도와드릴까요? 예: "아침 브리핑", "이번 주 조회수", "힉스필드 언제 끝나"';
  List<ModuleId> _choices = const [];

  @override
  void initState() {
    super.initState();
    _initMic();
  }

  Future<void> _initMic() async {
    var ok = false;
    try {
      ok = await _stt.initialize(onError: (e) => CoreLog.warn('음성 인식 오류: ${e.errorMsg}'));
    } catch (e) {
      CoreLog.warn('마이크를 쓸 수 없어 글자 입력으로 대체: $e');
    }
    if (mounted) setState(() => _micOk = ok);
  }

  @override
  void dispose() {
    _text.dispose();
    unawaited(Speaker.stop());
    try {
      _stt.cancel();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _listen() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    try {
      await _stt.listen(
        listenOptions: SpeechListenOptions(localeId: 'ko_KR', listenFor: const Duration(seconds: 20), pauseFor: const Duration(seconds: 3)),
        onResult: (r) {
          _text.text = r.recognizedWords;
          if (r.finalResult) {
            setState(() => _listening = false);
            _run(r.recognizedWords);
          }
        },
      );
    } catch (e) {
      CoreLog.warn('듣기 실패: $e');
      if (mounted) setState(() => _listening = false);
    }
  }

  Future<void> _reply(String msg) async {
    if (!mounted) return;
    setState(() => _answer = msg);
    unawaited(Speaker.say(msg)); // 읽는 동안에도 다음 질문(확인 창)을 바로 보여 준다
  }

  Future<void> _run(String said, {ModuleId? forced}) async {
    final s = widget.state;
    final r = forced != null ? RouteResult(module: forced, intent: 'ask') : s.router.route(said);
    setState(() => _choices = const []);
    if (r.refusal != null) return _reply(r.refusal!);
    switch (r.intent) {
      case 'briefing':
      case 'today':
        return _reply(Briefing.compose(widget.today, userName: s.user?.name ?? ''));
      case 'home':
        if (mounted) Navigator.of(context).popUntil((x) => x.isFirst);
        return;
      case 'ambiguous':
        setState(() => _choices = r.alternatives);
        return _reply('어느 쪽 이야기인가요? ${r.alternatives.map((e) => e.title).join(' 또는 ')}');
      case 'unknown':
      case 'empty':
        return _reply('잘 못 알아들었어요. 다시 말해 주세요. 예: "오늘 할 일", "2005년 아이들 영상"');
    }
    final id = r.module!;
    if (r.needsConfirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('정말 할까요?'),
          content: Text('"$said" — 중요한 일이라 한 번 더 확인해요. ${id.title} 화면에서 직접 확인하고 실행해요.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('아니요')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('네, 열기')),
          ],
        ),
      );
      if (ok != true) return _reply('하지 않았어요.');
      if (mounted) Navigator.of(context).pop();
      await widget.openModule(id);
      return;
    }
    ModuleReply? rep;
    try {
      rep = await s.modules.of(id).handle(VoiceCommand(said, intent: r.intent)).timeout(const Duration(seconds: 15));
    } catch (e) {
      CoreLog.warn('${id.title} 명령 실패: $e');
    }
    if (rep != null && rep.hasAction) {
      final act = rep;
      await _reply(act.speak);
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('정말 할까요?'),
          content: Text(act.confirmText ?? said),
          actions: [
            TextButton(key: const Key('voice-confirm-no'), onPressed: () => Navigator.pop(c, false), child: const Text('아니요')),
            FilledButton(key: const Key('voice-confirm-yes'), onPressed: () => Navigator.pop(c, true), child: const Text('네, 할게요')),
          ],
        ),
      );
      if (ok != true) return _reply('취소했어요. 아무것도 바꾸지 않았어요.');
      try {
        return await _reply(await act.onConfirm!());
      } catch (e) {
        CoreLog.error('${id.title} 음성 명령 실행 실패', e);
        return _reply('처리하지 못했어요. ${id.title} 화면에서 직접 해 주세요.');
      }
    }
    if (rep != null) {
      await _reply(rep.speak);
      if (!rep.openModule) return;
    } else {
      await _reply('${id.title}을(를) 열게요.');
    }
    if (mounted) Navigator.of(context).pop();
    await widget.openModule(id);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AssistantTheme.gap, 0, AssistantTheme.gap, AssistantTheme.gap),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon3d('mascot_hello', size: 56),
            const SizedBox(width: 12),
            Expanded(child: Text(_answer, key: const Key('voice-answer'), style: t.bodyLarge)),
          ]),
          if (_choices.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              for (final c in _choices)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: c.color),
                      onPressed: () => _run(_text.text, forced: c),
                      child: Text(c.title),
                    ),
                  ),
                ),
            ]),
          ],
          const SizedBox(height: AssistantTheme.gap),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('voice-text'),
                controller: _text,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(hintText: _micOk == false ? '마이크를 쓸 수 없어요. 글자로 적어 주세요' : '말하거나 적어 주세요', filled: true),
                onSubmitted: _run,
              ),
            ),
            const SizedBox(width: 8),
            if (_micOk == true)
              IconButton.filled(
                iconSize: 32,
                onPressed: _listen,
                icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
              )
            else
              IconButton.filled(key: const Key('voice-send'), iconSize: 32, onPressed: () => _run(_text.text), icon: const Icon(Icons.send_rounded)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final q in ['아침 브리핑', '오늘 할 일', '이번 주 조회수', '만료 임박 구독'])
              ActionChip(label: Text(q), onPressed: () {
                _text.text = q;
                _run(q);
              }),
          ]),
        ]),
      ),
    );
  }
}
