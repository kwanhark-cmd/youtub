import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'common.dart';
import 'dialogs.dart';

final dateText = DateFormat('yyyy년 M월 d일');
final dateTimeText = DateFormat('yyyy년 M월 d일 HH:mm');

/// 대화 카드: 제목 1줄(굵게) + 요약 2줄 + 날짜·AI 배지, 별표는 오른쪽 위, 왼쪽에 주제 색 띠.
/// 긴 목록용이라 그림자 없는 가벼운 평면 카드(배경색은 채움)입니다.
class ConversationTile extends StatelessWidget {
  final ConversationSummary c;
  final String? snippet;
  final List<String> highlight;
  final VoidCallback onOpen;
  final Widget? leading;
  final bool selected;
  final bool showReadAloud;

  const ConversationTile({
    super.key,
    required this.c,
    required this.onOpen,
    this.snippet,
    this.highlight = const [],
    this.leading,
    this.selected = false,
    this.showReadAloud = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context).palette;
    final tt = Theme.of(context).textTheme;
    final controller = context.read<AppController>();
    final preview = (snippet != null && snippet!.isNotEmpty) ? snippet : c.summary;
    final topics = controller.session?.topics.topicsOf(c.id) ?? const <Topic>[];
    final stripe = topics.isNotEmpty ? TopicColors.of(topics.first.id) : SourceBadge.colorOf(p, c.source);
    return Semantics(
      button: true,
      selected: selected,
      label: '${c.source.label} 대화, ${c.title}${c.starred ? ', 별표' : ''}',
      child: Material(
        color: selected ? Color.lerp(p.surface, p.primary, 0.12) : p.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSize.radius),
          side: p.borderWidth > 1 ? BorderSide(color: p.border, width: p.borderWidth) : BorderSide.none,
        ),
        child: InkWell(
          onTap: onOpen,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 6, color: stripe),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ?leading,
                            Expanded(
                              child: HighlightText(
                                c.title,
                                words: highlight,
                                style: tt.titleMedium!.copyWith(fontWeight: FontWeight.w800),
                                maxLines: 1,
                              ),
                            ),
                            if (c.starred) ...[
                              const SizedBox(width: 6),
                              Image.asset(AppIcons3d.star, width: 24, height: 24, semanticLabel: '별표'),
                            ],
                          ],
                        ),
                        if (preview != null && preview.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          HighlightText(
                            preview,
                            words: highlight,
                            style: tt.bodyMedium!.copyWith(color: p.textMuted),
                            maxLines: 2,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(dateText.format(c.createdAt), style: tt.bodySmall),
                            SourceBadge(c.source, small: true),
                            for (final t in topics.take(2)) TopicChip(t, small: true),
                            if (c.hasAttachments)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.attach_file_rounded, size: 18, color: p.textMuted),
                                  Text('첨부', style: tt.bodySmall),
                                ],
                              ),
                            if (showReadAloud && preview != null && preview.isNotEmpty)
                              IconButton(
                                tooltip: '읽어주기',
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints(minWidth: AppSize.minTouch, minHeight: AppSize.minTouch),
                                onPressed: () => readAloud(context, controller, '${c.title}. $preview'),
                                icon: Image.asset(AppIcons3d.speaker, width: 26, height: 26, excludeFromSemantics: true),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 주제 이름 + 주제 색 점.
class TopicChip extends StatelessWidget {
  final Topic topic;
  final bool small;
  const TopicChip(this.topic, {super.key, this.small = false});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context).palette;
    final color = TopicColors.of(topic.id);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 3 : 5),
      decoration: BoxDecoration(color: Color.lerp(p.surface, color, 0.16), borderRadius: BorderRadius.circular(AppSize.radiusSmall)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(topic.name, style: Theme.of(context).textTheme.labelMedium, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

Future<void> readAloud(BuildContext context, AppController c, String text) async {
  if (!c.settings.ttsEnabled) {
    showNotice(context, '읽어주기가 꺼져 있어요. 설정 > 음성에서 켤 수 있어요.', kind: StatusKind.check);
    return;
  }
  if (!c.voice.canSpeak) {
    showNotice(context, '이 기기에서는 읽어주기를 쓸 수 없어요.', kind: StatusKind.check);
    return;
  }
  await c.voice.stopSpeaking();
  await c.voice.speak(text, rate: c.settings.ttsRate);
}
