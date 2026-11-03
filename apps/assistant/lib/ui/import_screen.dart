import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/material.dart';

import '../app/assistant_state.dart';
import '../app/legacy_import.dart';
import 'widgets.dart';

/// 기존 앱에서 가져오기: 따로 쓰던 다섯 앱의 사용자 폴더를 찾아 통합 앱 폴더로 복사한다(원본은 그대로).
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.state});
  final AssistantState state;
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  late final _imp = LegacyImporter(target: widget.state.root);
  late Future<List<LegacySource>> _found = _imp.discover();
  final Map<String, String> _result = {};
  bool _busy = false;

  Future<void> _run(LegacySource s) async {
    setState(() => _busy = true);
    try {
      final r = await _imp.importOne(s);
      _result[s.module.name] = r.message;
    } catch (e, st) {
      CoreLog.error('가져오기 실패 ${s.module.title}', e, st);
      _result[s.module.name] = '가져오지 못했어요. 문제 신고를 눌러 주세요.';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _found = _imp.discover();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('기존 앱에서 가져오기')),
      body: FutureBuilder<List<LegacySource>>(
        future: _found,
        builder: (context, snap) {
          if (!snap.hasData) return const Notice(icon: 'mascot_working', title: '이 기기에서 기존 앱 자료를 찾는 중…');
          final list = snap.data!;
          return ListView(padding: const EdgeInsets.all(AssistantTheme.gap), children: [
            Text('원본은 그대로 두고 복사만 해요. 단독 앱은 계속 써도 되고, 통합 앱 자료와는 따로예요.', style: t.bodyLarge),
            const SizedBox(height: AssistantTheme.gap),
            if (list.isEmpty) const Notice(icon: 'search', title: '이 기기에서 기존 앱 자료를 찾지 못했어요', body: '하드 자료 찾기는 PC 엔진을 그대로 쓰므로 옮길 것이 없어요.'),
            for (final s in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledCard(
                  color: s.module.color,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.module.title, style: t.titleMedium?.copyWith(color: Colors.white)),
                    Text(s.describe(), style: t.bodySmall?.copyWith(color: Colors.white)),
                    if (_result[s.module.name] != null) Text(_result[s.module.name]!, style: t.bodyLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: s.module.color),
                      onPressed: _busy || s.alreadyImported ? null : () => _run(s),
                      child: Text(s.alreadyImported ? '이미 가져왔어요' : '가져오기'),
                    ),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
