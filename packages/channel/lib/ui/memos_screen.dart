import 'package:flutter/material.dart';

import '../app/services.dart';
import '../core/strings.dart';
import 'common.dart';

/// 음성 메모: 말로 남긴 아이디어를 글로 바꿔 저장. 제작 소재로 쓴다.
class MemosScreen extends StatefulWidget {
  const MemosScreen({super.key, required this.user});
  final UserContext user;
  @override
  State<MemosScreen> createState() => _MemosScreenState();
}

class _MemosScreenState extends State<MemosScreen> {
  UserContext get u => widget.user;
  final busy = Busy();

  Future<void> _record() async {
    toast(context, S.voiceListening);
    final words = await u.env.speech.listenOnce(max: const Duration(seconds: 30));
    if (!mounted) return;
    if (words == null || words.trim().isEmpty) {
      await _type();
      return;
    }
    u.memos.add(words);
    toast(context, S.voiceMemoSaved);
    setState(() {});
  }

  Future<void> _type() async {
    final c = TextEditingController();
    final t = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text(S.voiceMemoTitle),
        content: TextField(
          controller: c,
          maxLines: 5,
          decoration: const InputDecoration(labelText: S.voiceTypeInstead),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text(S.save)),
        ],
      ),
    );
    if (t == null || t.trim().isEmpty) return;
    u.memos.add(t);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final list = u.memos.list();
    return Scaffold(
      appBar: pageBar(context, S.voiceMemoTitle),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTokens.gapL),
          children: [
            ButtonWrap(
              children: [
                BigButton(label: S.voiceMemoRecord, icon: Icons.mic, onPressed: () => busy.run(_record)),
                BigButton(label: S.voiceTypeInstead, icon: Icons.keyboard, primary: false, onPressed: _type),
              ],
            ),
            const SizedBox(height: AppTokens.gapM),
            if (list.isEmpty) const EmptyState(icon: 'mic', message: S.memoEmptyHow),
            for (var i = 0; i < list.length; i++)
              Appear(
                index: i,
                child: ListCard(
                  icon: 'mic',
                  title: list[i].text,
                  subtitle: list[i].createdAt.toLocal().toString().substring(0, 16),
                  badge: list[i].used ? const StatusBadge(Status.done, S.memoUsed) : null,
                  trailing: IconButton(
                    tooltip: S.delete,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirmDanger(context, S.memo1)) {
                        u.memos.delete(list[i].id);
                        if (mounted) setState(() {});
                      }
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
