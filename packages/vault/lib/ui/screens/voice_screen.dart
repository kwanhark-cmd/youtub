import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../logic/voice_assistant.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// 음성 비서: 말(또는 글자)로 묻고, 답을 소리로 들려준다. 비밀번호는 읽지 않는다.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  final input = TextEditingController();
  final assistant = VoiceAssistant();
  final log = <(bool, String)>[]; // (내 말인가, 내용)
  bool? micAvailable;
  bool listening = false;
  String partial = '';
  PendingAction? pending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await context.appRead.services.speech.isAvailable();
      if (mounted) setState(() => micAvailable = ok);
    });
  }

  AppServices? _services;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services ??= context.appRead.services;
  }

  @override
  void dispose() {
    input.dispose();
    _services?.speech.stop();
    _services?.tts.stop();
    super.dispose();
  }

  Future<void> _ask(String text) async {
    final app = context.appRead;
    if (!app.isUnlocked) return; // 잠겨 있으면 음성 기능도 잠김
    final q = text.trim();
    if (q.isEmpty) return;
    final r = assistant.handle(q, app.data, app.now());
    setState(() {
      log.add((true, q));
      log.add((false, r.text));
      pending = r.action;
      input.clear();
      partial = '';
    });
    if (app.settings.sound) await app.services.tts.speak(r.text);
  }

  Future<void> _confirm(bool yes) async {
    final app = context.appRead;
    final a = pending;
    if (a == null) return;
    setState(() => pending = null);
    if (yes) {
      await app.mutate(a.apply);
      setState(() => log.add((false, '네, 처리했어요.')));
      if (app.settings.sound) await app.services.tts.speak('네, 처리했어요.');
    } else {
      setState(() => log.add((false, '취소했어요.')));
    }
  }

  Future<void> _listen() async {
    final app = context.appRead;
    if (listening) {
      await app.services.speech.stop();
      setState(() => listening = false);
      return;
    }
    await app.services.tts.stop();
    final ok = await app.services.speech.listen(
      onPartial: (t) => setState(() => partial = t),
      onFinal: (t) {
        setState(() => listening = false);
        _ask(t);
      },
    );
    setState(() => listening = ok);
    if (!ok && mounted) context.toast('음성 인식을 시작하지 못했어요. 글자로 물어봐 주세요.');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return AppPage(
      title: '음성 비서',
      restoreId: 'voice',
      children: [
        const TipBubble(
          id: 'voice',
          text: '예: "이번 달 구독료 얼마야?", "힉스필드 크레딧 언제 끝나?", "넷플릭스 해지 후보에 넣어". 비밀번호는 소리로 읽어 드리지 않아요.',
        ),
        BigButton(
          label: '아침 브리핑 듣기',
          icon: Icons.wb_sunny_rounded,
          kind: ButtonKind.caution,
          onPressed: () => _ask('아침 브리핑'),
        ),
        gap,
        if (micAvailable == true) ...[
          Center(
            child: Semantics(
              button: true,
              label: listening ? '듣기 멈추기' : '말하기 시작',
              child: Press3D(
                onTap: _listen,
                radius: 999,
                color: listening ? p.dangerFill : p.primary,
                child: SizedBox(
                  width: 120,
                  height: 120,
                  child: Icon(
                    listening ? Icons.stop_rounded : Icons.mic_rounded,
                    size: 64,
                    color: listening ? p.onDangerFill : p.onPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            listening
                ? (partial.isEmpty ? '듣고 있어요…' : partial)
                : '버튼을 누르고 말씀하세요',
            textAlign: TextAlign.center,
            style: t.titleMedium,
          ),
          gap,
        ] else if (micAvailable == false) ...[
          FlatCard(
            child: Text(
              '이 기기에서는 음성 인식을 쓸 수 없어서 글자로 물어보시면 돼요.',
              style: t.bodyLarge,
            ),
          ),
          gap,
        ],
        Row(
          children: [
            Expanded(
              child: BigField(
                controller: input,
                label: '글자로 물어보기',
                onSubmitted: _ask,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: '보내기',
              iconSize: 30,
              constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
              onPressed: () => _ask(input.text),
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
        if (pending != null) ...[
          gap,
          FlatCard(
            status: StatusKind.caution,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(pending!.description, style: t.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: BigButton(
                        label: '아니요',
                        kind: ButtonKind.plain,
                        raised: false,
                        onPressed: () => _confirm(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: BigButton(
                        label: '네',
                        kind: ButtonKind.safe,
                        raised: false,
                        onPressed: () => _confirm(true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        gap,
        for (final (mine, text) in log.reversed)
          Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(maxWidth: 520),
              decoration: BoxDecoration(
                color: mine ? p.primary : p.surface,
                borderRadius: BorderRadius.circular(AppTokens.radiusCard),
                border: mine ? null : Border.all(color: p.border),
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: AppTokens.fontBody,
                  color: mine ? p.onPrimary : p.text,
                ),
              ),
            ),
          ),
        if (app.settings.voiceProvider != 'device')
          Text('외부 음성 서비스는 준비 중이에요. 지금은 기기 음성을 써요.', style: t.bodyMedium),
      ],
    );
  }
}
