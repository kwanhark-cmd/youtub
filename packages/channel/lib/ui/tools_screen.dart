import 'package:flutter/material.dart';

import '../app/services.dart';
import '../core/strings.dart';
import '../features/tools/tools_service.dart';
import 'common.dart';

extension ToolsOf on UserContext {
  ToolsService get tools => extensions['tools']! as ToolsService;
}

/// 도구 연결 화면: 연결됨(초록)/안 됨(빨강), 연결 테스트, 연결 해제, 만료 시 다시 연결.
class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key, required this.user});
  final UserContext user;
  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  UserContext get u => widget.user;
  final busy = Busy();
  List<ToolInfo> tools = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await u.tools.all();
    if (mounted) setState(() => tools = t);
  }

  Status _status(ToolState s) => switch (s) {
    ToolState.connected => Status.done,
    ToolState.preparing => Status.progress,
    ToolState.notConnected => Status.problem,
    ToolState.expired => Status.problem,
  };

  String _label(ToolState s) => switch (s) {
    ToolState.connected => S.toolConnected,
    ToolState.notConnected => S.toolNotConnected,
    ToolState.expired => S.toolExpired,
    ToolState.preparing => S.toolPreparing,
  };

  @override
  Widget build(BuildContext context) {
    final s = u.settings;
    return Scaffold(
      appBar: pageBar(context, S.toolsTitle),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.pagePad,
            AppTokens.gapS,
            AppTokens.pagePad,
            AppTokens.bottomSpace,
          ),
          children: [
            for (final t in tools)
              StripeCard(
                status: _status(t.state),
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon3D(switch (t.id) {
                            ToolId.googleVids => 'video',
                            ToolId.higgsfield => 'sparkles',
                            ToolId.figma => 'picture',
                            ToolId.vrew => 'mic',
                          }, size: AppTokens.icon3dS),
                          const SizedBox(width: AppTokens.gapS),
                          Expanded(child: Text(t.name, style: Theme.of(context).textTheme.titleMedium)),
                        ],
                      ),
                      const SizedBox(height: AppTokens.gapXs),
                      StatusBadge(_status(t.state), _label(t.state)),
                      Text('${t.role} · ${_label(t.state)}', key: Key('tool-state-${t.id.name}')),
                      if (t.detail.isNotEmpty) Text(t.detail),
                      const SizedBox(height: AppTokens.gapS),
                      if (t.state != ToolState.preparing)
                        ButtonWrap(
                          children: [
                            if (t.state != ToolState.connected)
                              BigButton(
                                key: Key('tool-connect-${t.id.name}'),
                                label: t.state == ToolState.expired ? S.reconnect : S.toolConnect,
                                onPressed: () => busy.run(() => _connect(t.id)),
                              ),
                            if (t.state != ToolState.notConnected) ...[
                              BigButton(
                                label: S.toolTest,
                                primary: false,
                                onPressed: () => busy.run(() => _test(t.id)),
                              ),
                              BigButton(
                                label: S.toolDisconnect,
                                primary: false,
                                onPressed: () => busy.run(() async {
                                  await u.tools.disconnect(t.id);
                                  await _load();
                                }),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            SectionCard(
              title: S.toolPriority,
              icon3d: 'pin',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${S.toolVideoGen}: ${s.videoToolPriority.map(_toolName).join(' → ')}'),
                  Text('${S.toolNarration}: ${s.narrationToolPriority.map(_toolName).join(' → ')}'),
                  Text(S.tool1(S.toolMotion)),
                  const SizedBox(height: AppTokens.gapS),
                  BigButton(
                    label: S.tool2,
                    primary: false,
                    onPressed: () => setState(() {
                      final l = [...s.videoToolPriority];
                      l.add(l.removeAt(0));
                      s.videoToolPriority = l;
                    }),
                  ),
                  const SizedBox(height: AppTokens.gapS),
                  BigButton(
                    label: S.tool3,
                    primary: false,
                    onPressed: () => setState(() {
                      final l = [...s.narrationToolPriority];
                      l.add(l.removeAt(0));
                      s.narrationToolPriority = l;
                    }),
                  ),
                ],
              ),
            ),
            const ListTile(
              leading: Icon(Icons.lock),
              title: Text(S.toolVault),
              subtitle: Text(S.tool4),
              enabled: false,
            ),
          ],
        ),
      ),
    );
  }

  static String _toolName(String id) => switch (id) {
    'googleVids' => S.tool5,
    'higgsfield' => S.tool6,
    'ownFile' => S.tool7,
    'vrew' => S.tool8,
    _ => id,
  };

  Future<void> _connect(ToolId id) async {
    try {
      if (id == ToolId.higgsfield) {
        final c = TextEditingController();
        final key = await showDialog<String>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text(S.tool9(S.toolApiKey)),
            content: TextField(
              key: const Key('higgs-key'),
              controller: c,
              obscureText: true,
              decoration: const InputDecoration(labelText: S.toolApiKey),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d), child: const Text(S.cancel)),
              FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text(S.save)),
            ],
          ),
        );
        if (key == null || key.trim().isEmpty) return;
        await u.tools.connectHiggsfield(key);
      } else if (id == ToolId.figma) {
        final cid = TextEditingController(text: u.tools.figmaClientId);
        final sec = TextEditingController();
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text(S.tool10),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(S.tool11),
                const SizedBox(height: AppTokens.gapM),
                TextField(
                  controller: cid,
                  decoration: const InputDecoration(labelText: S.tool12),
                ),
                const SizedBox(height: AppTokens.gapM),
                TextField(
                  controller: sec,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: S.tool13),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text(S.cancel)),
              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text(S.toolConnect)),
            ],
          ),
        );
        if (ok != true) return;
        u.tools.figmaClientId = cid.text;
        if (sec.text.isNotEmpty) await u.secrets.write(ToolsService.figmaSecret, sec.text.trim());
        await u.tools.connectFigma();
      }
      await _load();
    } catch (e) {
      if (mounted) await showFailure(context, e, onRetry: () => _connect(id));
    }
  }

  Future<void> _test(ToolId id) async {
    try {
      await u.tools.test(id);
      if (mounted) toast(context, S.toolTestOk);
    } catch (e) {
      if (mounted) await showFailure(context, e, onReconnect: () => _connect(id), onRetry: () => _test(id));
    }
    await _load();
  }
}
