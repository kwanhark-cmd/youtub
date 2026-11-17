import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app/assistant_state.dart';
import '../app/data_folders.dart';
import '../app/folder_linker.dart';
import 'widgets.dart';

/// 설정 → 내 자료 폴더 연결. 폴더 이름·위치는 바꾸지 않고 읽기만 한다.
class FoldersScreen extends StatefulWidget {
  const FoldersScreen({super.key, required this.state, this.home});
  final AssistantState state;

  /// 시험용 사용자 폴더 (없으면 이 컴퓨터의 홈)
  final String? home;

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  late final linker = FolderLinker(widget.state);
  late String home = widget.home ?? Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  List<FolderMatch>? _found;
  final Map<String, String> _msg = {};
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _scan();
  }

  void _scan() {
    final found = home.isEmpty ? <FolderMatch>[] : DataFolderFinder(home).find();
    // 직접 골라 연결해 둔 폴더도 함께 보여 준다
    for (final m in [ModuleId.chats, ModuleId.channel]) {
      for (final pth in linker.connected.of(m)) {
        if (!found.any((f) => f.path == pth)) found.add(FolderMatch(pth, m));
      }
    }
    setState(() => _found = found);
  }

  Future<void> _connect(FolderMatch m) async {
    setState(() => _busy.add(m.path));
    final msg = await linker.connect(m);
    if (!mounted) return;
    setState(() {
      _busy.remove(m.path);
      _msg[m.path] = msg;
    });
  }

  Future<void> _pick() async {
    final dir = await getDirectoryPath(confirmButtonText: '이 폴더 고르기');
    if (dir == null || !mounted) return;
    final module = await showDialog<ModuleId>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('어느 모듈에 연결할까요?'),
        children: [
          for (final m in [ModuleId.chats, ModuleId.channel])
            SimpleDialogOption(onPressed: () => Navigator.pop(c, m), child: Text(m == ModuleId.chats ? 'AI 대화 기록 (대화 내보내기 파일)' : '채널 관리 (영상·사진·소리 소재)')),
        ],
      ),
    );
    if (module == null) return;
    final f = FolderMatch(dir, module);
    setState(() => (_found ??= []).add(f));
    await _connect(f);
  }

  String _short(String path) => home.isNotEmpty && path.startsWith(home) ? '~${path.substring(home.length)}' : path;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final found = _found;
    return Scaffold(
      appBar: AppBar(title: const Text('내 자료 폴더 연결')),
      body: ListView(key: const PageStorageKey('folders-list'), padding: const EdgeInsets.all(AssistantTheme.gap), children: [
        Text('컴퓨터에서 모듈에 맞는 폴더를 찾았어요. 폴더 이름·위치·파일은 바꾸지 않고 읽기만 해요.', style: t.bodyLarge),
        const SizedBox(height: 4),
        Text('법률·개인생활·백업처럼 민감한 폴더는 자동으로 고르지 않아요. 필요하면 아래 "직접 고르기"로 연결해요.', style: t.bodySmall),
        const SizedBox(height: AssistantTheme.gap),
        if (found == null) const Notice(icon: 'mascot_working', title: '폴더를 찾는 중…'),
        if (found != null && found.isEmpty)
          const Notice(icon: 'search', title: '맞는 폴더를 찾지 못했어요', body: '아래 "직접 고르기"로 폴더를 골라 연결할 수 있어요.'),
        for (final m in found ?? const <FolderMatch>[])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledCard(
              key: Key('folder-${m.name}'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: m.module.color, borderRadius: BorderRadius.circular(20)),
                    child: Text(m.module.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  if (linker.isConnected(m)) const Text('연결됨', style: TextStyle(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                Text(m.name, style: t.titleMedium),
                Text(_short(m.path), style: t.bodySmall),
                if (_msg[m.path] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg[m.path]!, style: t.bodyLarge)),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy.contains(m.path) ? null : () => _connect(m),
                  child: Text(_busy.contains(m.path) ? '가져오는 중…' : (linker.isConnected(m) ? '새 파일 다시 가져오기' : '연결하기')),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(key: const Key('folders-pick'), onPressed: _pick, icon: const Icon(Icons.folder_open), label: const Text('직접 고르기')),
        TextButton(onPressed: _scan, child: const Text('다시 찾기')),
      ]),
    );
  }
}
