import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/material.dart';

import '../app/assistant_state.dart';
import '../modules/lazy.dart';
import 'widgets.dart';

/// 모듈의 기존 홈을 그대로 띄우고, 맨 위에 같은 자리의 "뒤로"·"개인비서 홈" 띠를 둔다.
class ModuleHost extends StatefulWidget {
  const ModuleHost({super.key, required this.state, required this.module});
  final AssistantState state;
  final AssistantModule module;

  static Future<void> push(BuildContext context, AssistantState s, ModuleId id) {
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => ModuleHost(state: s, module: s.modules.of(id))));
  }

  @override
  State<ModuleHost> createState() => _ModuleHostState();
}

class _ModuleHostState extends State<ModuleHost> {
  final _moduleKey = GlobalKey();
  Future<Widget>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final sw = Stopwatch()..start();
    _future = widget.module.open().then((w) {
      CoreLog.info('${widget.module.id.title} 열기 ${sw.elapsedMilliseconds}ms');
      return w;
    });
  }

  /// 모듈 안 화면이 쌓여 있으면 한 단계 뒤로, 아니면 개인비서 홈으로.
  Future<void> _back() async {
    final nav = _findNavigator(_moduleKey.currentContext);
    if (nav != null && await nav.maybePop()) return;
    if (mounted) Navigator.of(context).pop();
  }

  NavigatorState? _findNavigator(BuildContext? ctx) {
    if (ctx == null) return null;
    NavigatorState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is NavigatorState) {
        found = e.state as NavigatorState;
        return;
      }
      e.visitChildren(visit);
    }

    (ctx as Element).visitChildren(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.module.id;
    final pkg = widget.module is PackagedModule ? (widget.module as PackagedModule).package : null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) {
        if (!did) _back();
      },
      child: Scaffold(
        body: Column(children: [
          Material(
            color: m.color,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 52,
                child: Row(children: [
                  TextButton.icon(
                    key: const Key('module-back'),
                    onPressed: _back,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    label: const Text('뒤로', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: Text(m.title, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  TextButton.icon(
                    key: const Key('module-home'),
                    onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                    icon: const Icon(Icons.home_rounded, color: Colors.white),
                    label: Text(widget.state.settings.appName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: FutureBuilder<Widget>(
                future: _future,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Notice(
                      icon: 'mascot_warning',
                      title: '${m.title}을(를) 열지 못했어요',
                      body: '잠시 뒤 다시 해 보세요. 계속되면 설정 → 문제 신고를 눌러 주세요.',
                      action: '다시 시도',
                      onAction: () => setState(_load),
                    );
                  }
                  if (!snap.hasData) {
                    return const Notice(icon: 'mascot_working', title: '여는 중이에요…');
                  }
                  Widget child = KeyedSubtree(key: _moduleKey, child: snap.data!);
                  if (pkg != null) child = DefaultAssetBundle(bundle: PackageAssetBundle(pkg), child: child);
                  return child;
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
