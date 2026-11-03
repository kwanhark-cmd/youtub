import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'common.dart';
import 'dialogs.dart';

/// 글자 입력칸 + 마이크 버튼. 음성을 쓸 수 없는 기기에서는 글자 입력칸만 보입니다.
class VoiceTextField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onSubmit;
  final TextEditingController? controller;
  final bool autofocus;
  final String submitLabel;
  final bool large; // 홈의 주인공 검색창(높이 68)

  const VoiceTextField({
    super.key,
    required this.hint,
    required this.onSubmit,
    this.controller,
    this.autofocus = false,
    this.submitLabel = '찾기',
    this.large = false,
  });

  @override
  State<VoiceTextField> createState() => _VoiceTextFieldState();
}

class _VoiceTextFieldState extends State<VoiceTextField> {
  late final TextEditingController _ctrl = widget.controller ?? TextEditingController();
  bool _listening = false;

  Future<void> _listen() async {
    final voice = context.read<AppController>().voice;
    if (_listening) {
      await voice.stopListening();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await voice.listen(
      onResult: (text, done) {
        if (!mounted) return;
        _ctrl.text = text;
        if (done) {
          setState(() => _listening = false);
          if (text.trim().isNotEmpty) widget.onSubmit(text.trim());
        }
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() => _listening = false);
        showNotice(context, msg, kind: StatusKind.check);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final p = AppTheme.of(context).palette;
    final canVoice = c.voice.canListen;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            autofocus: widget.autofocus,
            textInputAction: TextInputAction.search,
            style: widget.large ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: _listening ? '듣고 있어요… 말씀하세요' : widget.hint,
              contentPadding: widget.large ? const EdgeInsets.symmetric(horizontal: 16, vertical: 22) : null,
              filled: true,
              fillColor: p.surface,
              enabledBorder: widget.large
                  ? OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSize.radiusCard),
                      borderSide: BorderSide(color: p.primary, width: 2.5),
                    )
                  : null,
              prefixIcon: Icon(Icons.search_rounded, color: widget.large ? p.primaryText : p.textMuted, size: widget.large ? 34 : 28),
              suffixIcon: _ctrl.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '지우기',
                      icon: Icon(Icons.close_rounded, color: p.textMuted),
                      onPressed: () => setState(_ctrl.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (v) => widget.onSubmit(v.trim()),
          ),
        ),
        const SizedBox(width: AppSize.gapS),
        if (canVoice)
          SizedBox(
            width: widget.large ? 72 : 64,
            height: widget.large ? AppSize.searchHeight : AppSize.buttonHeight,
            child: Tooltip(
              message: _listening ? '그만 듣기' : '말로 하기',
              child: _MicButton(listening: _listening, onTap: _listen),
            ),
          )
        else
          BigButton(label: widget.submitLabel, onPressed: () => widget.onSubmit(_ctrl.text.trim()), expand: false, kind: ButtonKind.accent),
      ],
    );
  }
}

class _MicButton extends StatelessWidget {
  final bool listening;
  final VoidCallback onTap;
  const _MicButton({required this.listening, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context).palette;
    return Semantics(
      button: true,
      label: listening ? '그만 듣기' : '말로 하기',
      child: AnimatedContainer(
        duration: AppTheme.of(context).motion(context, AppMotion.normal),
        decoration: BoxDecoration(
          color: listening ? p.danger : p.accent,
          borderRadius: BorderRadius.circular(AppSize.radius),
          boxShadow: AppShadows.raised(p, pressed: listening),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSize.radius),
            onTap: onTap,
            child: Center(
              child: listening
                  ? Icon(Icons.stop_rounded, color: p.onDanger, size: 32)
                  : Image.asset('assets/icons3d/mic.png', width: 36, height: 36, excludeFromSemantics: true),
            ),
          ),
        ),
      ),
    );
  }
}

/// 처음 쓰는 기능에 한 번만 보이는 말풍선 안내(설정에서 다시 보기 가능).
class TipBubble extends StatelessWidget {
  final String id;
  final String text;
  const TipBubble({super.key, required this.id, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    if (c.settings.seenTips.contains(id)) return const SizedBox.shrink();
    final p = AppTheme.of(context).palette;
    return AppearUp(
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSize.gapM),
        padding: const EdgeInsets.all(AppSize.gapM),
        decoration: BoxDecoration(
          color: Color.lerp(p.surface, p.warning, 0.25),
          borderRadius: BorderRadius.circular(AppSize.radius),
          border: Border.all(color: p.warning, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset('assets/icons3d/bulb.png', width: 36, height: 36, excludeFromSemantics: true),
                const SizedBox(width: AppSize.gapM),
                Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
              ],
            ),
            const SizedBox(height: AppSize.gapS),
            BigButton(label: '알겠어요', expand: false, kind: ButtonKind.primary, onPressed: () => c.updateSettings((s) => s.seenTips.add(id))),
          ],
        ),
      ),
    );
  }
}
