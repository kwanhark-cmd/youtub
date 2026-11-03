import 'package:flutter/material.dart';

import '../app/services.dart';
import '../core/strings.dart';
import '../features/ai/brain.dart';
import '../features/corner/corner_service.dart';
import '../features/corner/material_source.dart';
import '../features/production/production_service.dart';
import 'common.dart';
import 'produce_screen.dart';

CornerService cornerOf(UserContext u) => u.extensions['corner']! as CornerService;

class CornerScreen extends StatefulWidget {
  const CornerScreen({super.key, required this.user});
  final UserContext user;
  @override
  State<CornerScreen> createState() => _CornerScreenState();
}

class _CornerScreenState extends State<CornerScreen> {
  UserContext get u => widget.user;

  Future<void> _new() async {
    final chans = u.youtube.channels();
    if (chans.isEmpty) {
      toast(context, S.channelNone);
      return;
    }
    final name = TextEditingController();
    var ch = chans.first.channelId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text(S.cornerNew),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('corner-name'),
                controller: name,
                decoration: InputDecoration(labelText: S.corner1(S.cornerName)),
              ),
              const SizedBox(height: AppTokens.gapM),
              DropdownButtonFormField<String>(
                initialValue: ch,
                isExpanded: true,
                decoration: const InputDecoration(labelText: S.cornerChannel),
                items: [for (final x in chans) DropdownMenuItem(value: x.channelId, child: Text(x.title))],
                onChanged: (v) => setD(() => ch = v ?? ch),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(S.cancel)),
            FilledButton(
              key: const Key('corner-ok'),
              onPressed: () => Navigator.pop(c, true),
              child: const Text(S.save),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      cornerOf(u).create(name.text, ch);
    } catch (e) {
      if (mounted) await showFailure(context, e);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final list = cornerOf(u).corners();
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppTokens.pagePad, AppTokens.gapS, AppTokens.pagePad, AppTokens.bottomSpace),
      children: [
        TipBanner(text: S.corner2, seen: u.settings.tipSeen('corner'), onSeen: () => u.settings.markTipSeen('corner')),
        const SizedBox(height: AppTokens.gapM),
        BigButton(key: const Key('corner-new'), label: S.cornerNew, icon: Icons.add, onPressed: _new),
        const SizedBox(height: AppTokens.gapM),
        if (list.isEmpty)
          EmptyState(icon: 'corner', message: S.cornerEmptyHow, actionLabel: S.cornerNew, onAction: _new),
        for (var i = 0; i < list.length; i++)
          Appear(
            index: i,
            child: ListCard(
              key: Key('corner-${list[i].id}'),
              icon: 'corner',
              title: list[i].name,
              subtitle: S.corner3(
                u.youtube.channel(list[i].channelId)?.title ?? '',
                cornerOf(u).items(list[i].id).length,
              ),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CornerDetailScreen(user: u, cornerId: list[i].id),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
          ),
      ],
    );
  }
}

class CornerDetailScreen extends StatefulWidget {
  const CornerDetailScreen({super.key, required this.user, required this.cornerId});
  final UserContext user;
  final int cornerId;
  @override
  State<CornerDetailScreen> createState() => _CornerDetailScreenState();
}

class _CornerDetailScreenState extends State<CornerDetailScreen> {
  UserContext get u => widget.user;
  CornerService get cs => cornerOf(u);
  final busy = Busy();
  final Set<ContentFormat> formats = {ContentFormat.shorts, ContentFormat.long, ContentFormat.image};
  List<Production> made = [];

  String _crLabel(CornerItem i) => switch (i.copyright) {
    'own' => S.corner4,
    'licensed' => S.corner5,
    'approved' => S.corner6,
    'excluded' => S.corner7,
    _ => S.corner8,
  };

  @override
  Widget build(BuildContext context) {
    final c = cs.corner(widget.cornerId);
    if (c == null) return Scaffold(appBar: pageBar(context, S.navCorner), body: const EmptyHint(S.empty));
    final items = cs.items(c.id);
    return Scaffold(
      appBar: pageBar(context, c.name),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTokens.gapL),
          children: [
            ButtonWrap(
              children: [
                BigButton(
                  key: const Key('corner-add-video'),
                  label: S.cornerAddVideo,
                  icon: Icons.videocam,
                  primary: false,
                  onPressed: () => busy.run(_addVideo),
                ),
                BigButton(
                  key: const Key('corner-add-memo'),
                  label: S.cornerAddMemo,
                  icon: Icons.mic,
                  primary: false,
                  onPressed: () => busy.run(_addMemo),
                ),
                BigButton(label: S.corner9, icon: Icons.edit_note, primary: false, onPressed: () => busy.run(_addText)),
                BigButton(
                  key: const Key('corner-import'),
                  label: S.cornerImport,
                  icon: Icons.folder_open,
                  primary: false,
                  onPressed: () => busy.run(_import),
                ),
              ],
            ),
            SectionCard(
              title: S.corner10(items.length),
              icon: Icons.inventory_2,
              child: Column(
                children: [
                  if (items.isEmpty) const Text(S.empty),
                  for (final i in items)
                    ListCard(
                      key: Key('item-${i.id}'),
                      icon: switch (i.kind) {
                        'video' => 'video',
                        'audio' => 'mic',
                        'image' => 'picture',
                        'memo' => 'mic',
                        _ => 'memo',
                      },
                      title: i.title.isEmpty ? i.text : i.title,
                      status: i.needsCheck ? Status.check : (i.copyright == 'excluded' ? Status.problem : Status.done),
                      badge: StatusBadge(
                        i.needsCheck ? Status.check : (i.copyright == 'excluded' ? Status.problem : Status.done),
                        _crLabel(i),
                        shake: i.needsCheck,
                      ),
                      trailing: i.needsCheck
                          ? FilledButton(
                              key: Key('check-${i.id}'),
                              onPressed: () => _check(i),
                              child: const Text(S.cornerCopyright),
                            )
                          : IconButton(
                              tooltip: S.delete,
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                cs.removeItem(i.id);
                                setState(() {});
                              },
                            ),
                    ),
                ],
              ),
            ),
            SectionCard(
              title: S.cornerMake,
              icon: Icons.auto_awesome,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final f in ContentFormat.values)
                        FilterChip(
                          label: Text(formatLabel(f)),
                          selected: formats.contains(f),
                          onSelected: (v) => setState(() => v ? formats.add(f) : formats.remove(f)),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.gapM),
                  BigButton(
                    key: const Key('corner-make'),
                    label: S.cornerMake,
                    icon: Icons.auto_awesome,
                    onPressed: formats.isEmpty ? null : () => busy.run(() => _make(c)),
                  ),
                  for (final p in made)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text(p.title),
                      subtitle: Text(
                        S.join2(
                          formatLabel(p.format),
                          p.extra['srt'] != null && '${p.extra['srt']}'.isNotEmpty ? ' · ${S.cornerSubtitles} 있음' : '',
                        ),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ProductionDetailScreen(user: u, id: p.id),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addVideo() async {
    final path = await u.env.pickFile?.call(ProductionService.videoExtensions);
    if (path == null) return;
    try {
      final it = cs.addOwnVideo(widget.cornerId, path);
      if (it.needsCheck && mounted) await _check(it);
    } catch (e) {
      if (mounted) await showFailure(context, e);
    }
    if (mounted) setState(() {});
  }

  Future<void> _addMemo() async {
    final memos = u.memos.list(limit: 50);
    if (memos.isEmpty) {
      toast(context, S.corner11);
      return;
    }
    final id = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text(S.cornerAddMemo),
        children: [
          for (final m in memos) SimpleDialogOption(onPressed: () => Navigator.pop(c, m.id), child: Text(m.text)),
        ],
      ),
    );
    if (id == null) return;
    cs.addMemo(widget.cornerId, id);
    if (mounted) setState(() {});
  }

  Future<void> _addText() async {
    final t = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(S.corner12),
        content: TextField(
          controller: t,
          maxLines: 6,
          decoration: const InputDecoration(labelText: S.corner13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text(S.save)),
        ],
      ),
    );
    if (ok == true && t.text.trim().isNotEmpty) cs.addText(widget.cornerId, t.text);
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    final dir = await u.env.pickDirectory?.call();
    if (dir == null) return;
    final r = await cs.importFrom(widget.cornerId, FolderMaterialSource(dir));
    if (!mounted) return;
    toast(context, S.corner14(r.added, r.needCheck > 0 ? ' 저작권 확인이 필요한 소재가 ${r.needCheck}개 있어요.' : ''));
    setState(() {});
  }

  Future<void> _check(CornerItem i) async {
    final allow = await confirm(
      context,
      '${S.cornerCopyrightAsk}\n\n"${i.title}"',
      yes: S.cornerCopyrightYes,
      no: S.cornerCopyrightNo,
    );
    cs.decideCopyright(i.id, allow);
    if (mounted) setState(() {});
  }

  Future<void> _make(Corner c) async {
    if (!await confirmAiCost(context, u, calls: formats.length, output: 3000)) return;
    if (!mounted) return;
    try {
      final r = await runWithProgress(context, S.cornerMake, (cancel, p) => cs.make(c.id, formats: formats.toList()));
      if (r != null && mounted) {
        setState(() => made = r);
        toast(context, S.corner15(r.length));
      }
    } on ProductionBlocked catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) await showFailure(context, e);
    }
  }
}
