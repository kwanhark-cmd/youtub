import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/material.dart';

import '../app/assistant_state.dart';
import 'widgets.dart';

/// 통합 검색 결과 (모듈별 묶음). 비밀번호는 절대 나오지 않는다.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.state, required this.query, required this.openModule});
  final AssistantState state;
  final String query;
  final Future<void> Function(ModuleId) openModule;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late Future<Map<ModuleId, List<SearchHit>>> _f = _run();

  Future<Map<ModuleId, List<SearchHit>>> _run() => UnifiedSearch(widget.state.modules.all).run(widget.query);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('"${widget.query}" 찾기')),
      body: FutureBuilder(
        future: _f,
        builder: (context, snap) {
          if (snap.hasError) {
            return Notice(icon: 'mascot_warning', title: '찾지 못했어요', action: '다시 시도', onAction: () => setState(() => _f = _run()));
          }
          if (!snap.hasData) return const Notice(icon: 'mascot_working', title: '다섯 곳에서 찾는 중…');
          final r = snap.data!;
          if (r.isEmpty) {
            return Notice(icon: 'search', title: '찾은 것이 없어요', body: '다른 말로 찾아보거나, 모듈을 한 번 열어 자료를 불러온 뒤 다시 찾아보세요.', action: '다시 찾기', onAction: () => setState(() => _f = _run()));
          }
          return ListView(padding: const EdgeInsets.all(AssistantTheme.gap), children: [
            for (final e in r.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Row(children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: e.key.color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text('${e.key.title} · ${e.value.length}개', style: t.titleMedium),
                ]),
              ),
              for (final h in e.value.take(20))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    onTap: () => widget.openModule(h.module),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(h.title, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                      if (h.subtitle != null && h.subtitle!.isNotEmpty) Text(h.subtitle!, style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ),
            ],
          ]);
        },
      ),
    );
  }
}
