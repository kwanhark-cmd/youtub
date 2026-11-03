import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/material.dart';

import '../app/assistant_state.dart';
import '../app/keys.dart';
import 'keys_screen.dart';
import 'widgets.dart';

/// 연결 상태: 구글 / AI / 힉스필드 / 피그마 / 하드 엔진 / 얼굴 모델 — 초록·빨강 + 연결 테스트.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key, required this.state});
  final AssistantState state;
  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  Map<String, bool>? _r;

  @override
  void initState() {
    super.initState();
    _test();
  }

  Future<void> _test() async {
    setState(() => _r = null);
    final out = <String, bool>{};
    final keys = SharedKeys(widget.state.secrets);
    out['구글 (유튜브·블로거·지메일·캘린더·주소록)'] = await keys.hasGoogle();
    out['AI'] = await keys.hasAi();
    out['힉스필드'] = await keys.has(SharedKeys.higgsfield);
    out['피그마'] = await keys.has(SharedKeys.figma);
    for (final m in widget.state.modules.all) {
      try {
        out.addAll(await m.checkConnections().timeout(const Duration(seconds: 8)));
      } catch (e) {
        CoreLog.warn('${m.id.title} 연결 점검 실패: $e');
      }
    }
    out.putIfAbsent('얼굴 모델', () => false);
    if (mounted) setState(() => _r = out);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('연결 상태')),
      body: ListView(padding: const EdgeInsets.all(AssistantTheme.gap), children: [
        FilledCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_r == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            for (final e in (_r ?? const <String, bool>{}).entries)
              ListTile(
                leading: Icon(e.value ? Icons.check_circle_rounded : Icons.cancel_rounded, color: e.value ? const Color(0xFF1FA463) : const Color(0xFFD93025), size: 32),
                title: Text(e.key, style: t.bodyLarge),
                subtitle: Text(e.value ? '연결됨' : '연결 안 됨'),
              ),
          ]),
        ),
        const SizedBox(height: AssistantTheme.gap),
        FilledButton.icon(key: const Key('conn-test'), onPressed: _test, icon: const Icon(Icons.refresh), label: const Text('연결 테스트')),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          key: const Key('conn-keys'),
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => KeysScreen(state: widget.state)));
            if (mounted) await _test();
          },
          icon: const Icon(Icons.key_rounded),
          label: const Text('열쇠 넣기 (구글 하나·AI 하나)'),
        ),
      ]),
    );
  }
}
