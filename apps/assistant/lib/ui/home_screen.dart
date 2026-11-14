import 'dart:async';

import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/material.dart';

import '../app/assistant_state.dart';
import '../app/keys.dart';
import 'module_host.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'suggestions_screen.dart';
import 'voice_sheet.dart';
import 'widgets.dart';

/// 하나의 홈: 마스코트 인사 + 오늘 할 일 + 검색창 + 모듈 타일 여섯.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});
  final AssistantState state;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<ModuleId, List<TodayItem>> _today = {};
  Map<ModuleId, String> _status = {};
  bool _loading = true;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 첫 화면을 먼저 그리고, 오늘 할 일은 그 뒤에 조용히 모은다(시작이 느려지지 않게)
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final sw = Stopwatch()..start();
    final s = widget.state;
    final today = <ModuleId, List<TodayItem>>{};
    final status = <ModuleId, String>{};
    final each = <String>[];
    await Future.wait(s.modules.all.map((m) async {
      final one = Stopwatch()..start();
      try {
        today[m.id] = await m.today().timeout(const Duration(seconds: 8));
      } catch (e) {
        CoreLog.warn('${m.id.title} 오늘 할 일 실패: $e');
      }
      try {
        status[m.id] = await m.statusLine().timeout(const Duration(seconds: 6));
      } catch (_) {
        status[m.id] = '눌러서 열기';
      }
      each.add('${m.id.title} ${one.elapsedMilliseconds}ms');
    }));
    CoreLog.info('오늘 할 일 모으기 ${sw.elapsedMilliseconds}ms (${each.join(', ')})');
    // 구글 "테스트" 앱 연결은 7일마다 만료: 3일 전부터 알려 준다
    try {
      final left = await SharedKeys(s.secrets).googleDaysLeft();
      if (left != null && left <= 3) {
        (today[ModuleId.channel] ??= []).add(TodayItem(
          module: ModuleId.channel,
          text: left <= 0 ? '구글 연결이 끝났어요. 설정 → 연결 상태에서 다시 이어 주세요' : '구글 연결이 $left일 뒤 끝나요. 미리 다시 이어 주세요',
          urgency: left <= 0 ? 98 : 85,
        ));
      }
    } catch (_) {}
    for (final sug in s.links.pending) {
      (today[sug.to] ??= []).add(TodayItem(module: sug.to, text: '새 소재 제안: ${sug.title}', urgency: 40));
    }
    if (!mounted) return;
    setState(() {
      _today = today;
      _status = status;
      _loading = false;
    });
  }

  Future<void> _open(ModuleId id) async {
    await ModuleHost.push(context, widget.state, id);
    if (mounted) unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final t = Theme.of(context).textTheme;
    final (top, rest) = Briefing.pickTop(_today.values.expand((e) => e));
    final wide = MediaQuery.sizeOf(context).width > 720;
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('home-mic'),
        onPressed: () => VoiceSheet.show(context, s, today: _today, openModule: _open),
        icon: const Icon(Icons.mic_rounded, size: 28),
        label: const Text('말로 하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            key: const PageStorageKey('home-list'),
            padding: const EdgeInsets.fromLTRB(AssistantTheme.gap, AssistantTheme.gap, AssistantTheme.gap, 120),
            children: [
              Row(children: [
                const Icon3d('mascot_hello', size: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('안녕하세요, ${s.user?.name ?? ''}님', style: t.headlineSmall),
                    Text(s.settings.appName, style: t.bodySmall),
                  ]),
                ),
                if (s.links.pending.isNotEmpty)
                  IconButton(
                    tooltip: '제안함',
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SuggestionsScreen(state: s))),
                    icon: Badge(label: Text('${s.links.pending.length}'), child: const Icon(Icons.inbox_rounded, size: 30)),
                  ),
                IconButton(
                  key: const Key('home-settings'),
                  tooltip: '설정',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(state: s))),
                  icon: const Icon(Icons.settings_rounded, size: 30),
                ),
              ]),
              const SizedBox(height: AssistantTheme.gap),
              _TodayHero(top: top, rest: rest, loading: _loading, onOpen: _open),
              const SizedBox(height: AssistantTheme.gap),
              TextField(
                key: const Key('home-search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '다섯 곳에서 한 번에 찾기 (영상·대화·파일·물건·구독)',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                ),
                onSubmitted: (q) {
                  if (q.trim().isEmpty) return;
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => SearchScreen(state: s, query: q, openModule: _open)));
                },
              ),
              const SizedBox(height: AssistantTheme.gap),
              LayoutBuilder(builder: (context, c) {
                // 글씨가 커져도 잘리지 않게: 고정 비율 대신 줄마다 높이를 맞춘다
                final cols = wide ? 3 : 2;
                final ids = ModuleId.values;
                return Column(children: [
                  for (var i = 0; i < ids.length; i += cols)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: IntrinsicHeight(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          for (var j = i; j < i + cols; j++) ...[
                            if (j > i) const SizedBox(width: 12),
                            Expanded(
                              child: j < ids.length
                                  ? _ModuleTile(id: ids[j], status: _status[ids[j]] ?? '', count: _today[ids[j]]?.length ?? 0, onTap: () => _open(ids[j]))
                                  : const SizedBox(),
                            ),
                          ],
                        ]),
                      ),
                    ),
                ]);
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayHero extends StatelessWidget {
  const _TodayHero({required this.top, required this.rest, required this.loading, required this.onOpen});
  final TodayItem? top;
  final List<TodayItem> rest;
  final bool loading;
  final void Function(ModuleId) onOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (top == null) {
      return FilledCard(
        child: Row(children: [
          Icon3d(loading ? 'mascot_working' : 'mascot_done', size: 56),
          const SizedBox(width: 12),
          Expanded(child: Text(loading ? '오늘 할 일을 모으는 중이에요…' : '오늘은 급한 일이 없어요. 아래에서 골라 보세요.', style: t.bodyLarge)),
        ]),
      );
    }
    final c = top!.module.color;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FilledCard(
        key: const Key('today-top'),
        color: c,
        onTap: () => onOpen(top!.module),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('오늘 가장 먼저 · ${top!.module.title}', style: t.bodySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(children: [
            Icon3d(moduleIcon(top!.module), size: 56),
            const SizedBox(width: 12),
            Expanded(child: Text(top!.text, style: t.titleMedium?.copyWith(color: Colors.white, fontSize: 22))),
          ]),
        ]),
      ),
      for (final r in rest.take(5))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilledCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            onTap: () => onOpen(r.module),
            child: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: r.module.color, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(child: Text(r.text, style: t.bodyLarge)),
              Text(r.module.title, style: t.bodySmall),
            ]),
          ),
        ),
    ]);
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.id, required this.status, required this.count, required this.onTap});
  final ModuleId id;
  final String status;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return FilledCard(
      key: Key('tile-${id.name}'),
      color: id.color,
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon3d(moduleIcon(id), size: 48),
          const Spacer(),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Text('$count', style: TextStyle(color: id.color, fontWeight: FontWeight.w800)),
            ),
        ]),
        const SizedBox(height: 28),
        Text(id.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(color: Colors.white)),
        Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: Colors.white)),
      ]),
    );
  }
}
