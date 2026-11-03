import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// 상태를 하나의 띠로 덮지 않고 따로 보여줌: 가져온 대화 수 / AI 연결 / 지메일 연결.
/// 설정을 저장하면 바로 바뀝니다(다시 시작할 필요 없음).
class StatusStrip extends StatelessWidget {
  final VoidCallback? onTapAi;
  final VoidCallback? onTapGmail;
  const StatusStrip({super.key, this.onTapAi, this.onTapGmail});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final s = c.session;
    if (s == null) return const SizedBox.shrink();
    final real = s.store.realCount();
    final samples = s.store.sampleCount();
    final convText = real > 0
        ? '가져온 대화 $real개'
        : samples > 0
        ? '샘플 대화만 있어요($samples개)'
        : '가져온 대화 없음';
    return Wrap(
      spacing: AppSize.gapS,
      runSpacing: AppSize.gapS,
      children: [
        _StatusPill(icon: Icons.forum_rounded, text: convText, kind: real > 0 ? StatusKind.done : StatusKind.check),
        _StatusPill(
          icon: Icons.smart_toy_rounded,
          text: c.aiConnected ? 'AI 연결: 켜짐' : 'AI 연결: 꺼짐(무료 검색만)',
          kind: c.aiConnected ? StatusKind.done : StatusKind.progress,
          onTap: onTapAi,
        ),
        _StatusPill(
          icon: Icons.mail_rounded,
          text: c.gmailConnected ? '지메일: 연결됨' : '지메일: 연결 안 됨',
          kind: c.gmailConnected ? StatusKind.done : StatusKind.progress,
          onTap: onTapGmail,
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final StatusKind kind;
  final VoidCallback? onTap;
  const _StatusPill({required this.icon, required this.text, required this.kind, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context).palette;
    final (bg, fg, stateIcon) = p.status(kind);
    final body = Container(
      constraints: const BoxConstraints(minHeight: AppSize.minTouch),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppSize.radius)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text, style: Theme.of(context).textTheme.labelMedium!.copyWith(color: fg)),
          ),
          const SizedBox(width: 4),
          Icon(stateIcon, color: fg, size: 18),
        ],
      ),
    );
    if (onTap == null) {
      return Semantics(
        label: text,
        child: ExcludeSemantics(child: body),
      );
    }
    return Semantics(
      button: true,
      label: text,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSize.radius),
        child: ExcludeSemantics(child: body),
      ),
    );
  }
}
