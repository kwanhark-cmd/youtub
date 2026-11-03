import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/material.dart';

import '../app/assistant_state.dart';
import 'widgets.dart';

/// 모듈 사이 제안함. 자동으로 올리거나 지우지 않고, 사용자가 "받기"를 눌러야 들어간다.
class SuggestionsScreen extends StatelessWidget {
  const SuggestionsScreen({super.key, required this.state});
  final AssistantState state;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('제안함')),
      body: ListenableBuilder(
        listenable: state.links,
        builder: (context, _) {
          final list = state.links.pending;
          if (list.isEmpty) return const Notice(icon: 'mascot_done', title: '새 제안이 없어요', body: '모듈 사이에서 쓸 만한 소재가 생기면 여기에 모여요.');
          return ListView(padding: const EdgeInsets.all(AssistantTheme.gap), children: [
            for (final sg in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sg.kind.title, style: t.bodySmall?.copyWith(color: sg.to.color, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(sg.title, style: t.titleMedium),
                    if (sg.detail.isNotEmpty) Text(sg.detail, style: t.bodyLarge),
                    const SizedBox(height: 12),
                    Row(children: [
                      FilledButton(
                        onPressed: () async {
                          final ok = await state.acceptSuggestion(sg);
                          if (context.mounted) say(context, ok ? '${sg.to.title}에 넣었어요' : '넣지 못했어요. 기록을 확인해 주세요.');
                        },
                        child: const Text('받기'),
                      ),
                      const SizedBox(width: 12),
                      TextButton(onPressed: () => state.links.dismiss(sg.id), child: const Text('괜찮아요')),
                    ]),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
