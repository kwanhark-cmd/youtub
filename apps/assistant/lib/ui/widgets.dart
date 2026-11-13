import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/material.dart';

/// 3D 아이콘 (Fluent Emoji 3D, MIT)
class Icon3d extends StatelessWidget {
  const Icon3d(this.name, {super.key, this.size = 40});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset('assets/icons/$name.png', width: size, height: size, errorBuilder: (_, _, _) => SizedBox(width: size, height: size));
}

String moduleIcon(ModuleId m) => switch (m) {
      ModuleId.channel => 'video',
      ModuleId.chats => 'chat',
      ModuleId.harddisk => 'folder',
      ModuleId.declutter => 'package',
      ModuleId.vault => 'lock',
      ModuleId.metaclean => 'camera',
    };

/// 채워진 카드 + 그림자 (테두리만 있는 상자 금지)
class FilledCard extends StatelessWidget {
  const FilledCard({super.key, required this.child, this.color, this.onTap, this.padding = const EdgeInsets.all(AssistantTheme.gap)});
  final Widget child;
  final Color? color;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    return Card(
      color: color ?? Theme.of(context).colorScheme.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// 빈 자료·오류 안내 + 다음 행동 버튼
class Notice extends StatelessWidget {
  const Notice({super.key, required this.icon, required this.title, this.body, this.action, this.onAction});
  final String icon;
  final String title;
  final String? body;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AssistantTheme.gap * 1.5),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon3d(icon, size: 88),
          const SizedBox(height: AssistantTheme.gap),
          Text(title, style: t.titleMedium, textAlign: TextAlign.center),
          if (body != null) ...[const SizedBox(height: 8), Text(body!, style: t.bodyLarge, textAlign: TextAlign.center)],
          if (action != null) ...[const SizedBox(height: AssistantTheme.gap), FilledButton(onPressed: onAction, child: Text(action!))],
        ]),
      ),
    );
  }
}

/// 살아 있는 화면에서만 알림을 띄운다 (닫힌 화면에서 "다시 시도" 오류 방지)
void say(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
}
