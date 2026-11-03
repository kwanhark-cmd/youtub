import 'package:flutter/material.dart';

import '../app/services.dart';
import '../core/db.dart';
import '../core/strings.dart';
import '../features/edits/edit_service.dart';
import 'common.dart';

/// "지금 수정 실행": 제안을 먼저 보여 주고, 확인하면 적용.
Future<void> runEditsFlow(BuildContext callerContext, UserContext u) async {
  final context = alive(callerContext);
  if (context == null) return;
  if (u.youtube.channels().isEmpty) {
    toast(context, S.channelNone);
    return;
  }
  final calls = u.youtube.channels().fold<int>(0, (s, c) => s + u.edits.remainingToday(c.channelId));
  if (!await confirmAiCost(context, u, calls: calls, output: 800)) return;
  if (!context.mounted) return;
  try {
    final proposals = await runWithProgress(context, S.editsPreviewTitle, (cancel, p) async {
      final all = <EditProposal>[];
      final chans = u.youtube.channels();
      for (var i = 0; i < chans.length; i++) {
        p(i / chans.length, S.edits1(chans[i].title));
        all.addAll(await u.edits.plan(chans[i].channelId, cancel: cancel));
      }
      return all;
    });
    if (proposals == null || !context.mounted) return;
    if (proposals.isEmpty) {
      toast(context, S.editsNone);
      return;
    }
    // 일괄 수정 미리보기: 한 화면에서 모든 변경안을 보고 고른 것만 적용
    final chosen = await showBatchPreview(context, u, proposals);
    if (chosen == null || chosen.isEmpty || !context.mounted) return;
    final lastId = u.editLog.list(limit: 1).firstOrNull?.id ?? 0;
    final r = await runWithProgress(
      context,
      S.editsApply,
      (cancel, p) => u.edits.apply(chosen, cancel: cancel, progress: p),
    );
    if (r == null || !context.mounted) return;
    final msg = S.edits4(
      S.editsDone(r.applied),
      r.failed > 0 ? ' 실패 ${r.failed}개.' : '',
      r.deferred > 0 ? ' ${S.runnerQuotaDefer}' : '',
    );
    if (r.applied > 0) {
      final justApplied = u.editLog
          .list(limit: 500)
          .where((e) => e.id > lastId && e.status == EditStatus.applied)
          .map((e) => e.id)
          .toList();
      celebrate(
        context,
        msg,
        action: SnackBarAction(
          label: S.batchUndoAll,
          onPressed: () async {
            for (final id in justApplied.reversed) {
              await u.edits.revert(id, force: true);
            }
          },
        ),
      );
    } else {
      toast(context, msg);
    }
    if (u.settings.ttsEnabled) await u.env.speaker.speak(msg);
  } catch (e) {
    if (context.mounted) await showFailure(context, e, onRetry: () => runEditsFlow(context, u));
  }
}

/// 일괄 수정 미리보기 (전체 화면): 영상마다 수정 전/후를 보여 주고 체크한 것만 돌려준다.
Future<List<EditProposal>?> showBatchPreview(
  BuildContext callerContext,
  UserContext u,
  List<EditProposal> proposals,
) async {
  final context = alive(callerContext);
  if (context == null) return null;
  return showDialog<List<EditProposal>>(
    context: context,
    builder: (c) => Dialog.fullscreen(
      child: _BatchPreview(u: u, proposals: proposals),
    ),
  );
}

class _BatchPreview extends StatefulWidget {
  const _BatchPreview({required this.u, required this.proposals});
  final UserContext u;
  final List<EditProposal> proposals;
  @override
  State<_BatchPreview> createState() => _BatchPreviewState();
}

class _BatchPreviewState extends State<_BatchPreview> {
  late final Set<int> on = {for (var i = 0; i < widget.proposals.length; i++) i};

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final u = widget.u;
    final list = widget.proposals;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: S.cancel, icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: const Text(S.editsPreviewTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppTokens.pagePad, AppTokens.gapS, AppTokens.pagePad, AppTokens.gapXl),
          children: [
            Row(
              children: [
                const Mascot(MascotMood.working, size: 56),
                const SizedBox(width: AppTokens.gapM),
                Expanded(
                  child: Text(
                    u.settings.isFirstMonth(u.env.now())
                        ? '${S.batchHelp} ${S.editsFirstMonth}'
                        : '${S.batchHelp} ${S.editsLimit(u.settings.editsPerChannelPerDay)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.gapS),
            ButtonWrap(
              children: [
                BigButton(
                  label: S.batchAll,
                  icon: Icons.done_all,
                  primary: false,
                  onPressed: () => setState(() => on.addAll(List.generate(list.length, (i) => i))),
                ),
                BigButton(
                  label: S.batchNone,
                  icon: Icons.remove_done,
                  primary: false,
                  onPressed: () => setState(on.clear),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.gapS),
            for (var i = 0; i < list.length; i++)
              Appear(
                index: i,
                child: StripeCard(
                  key: Key('batch-$i'),
                  status: on.contains(i) ? Status.progress : null,
                  onTap: () => setState(() => on.contains(i) ? on.remove(i) : on.add(i)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: on.contains(i),
                        onChanged: (v) => setState(() => v == true ? on.add(i) : on.remove(i)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              u.youtube.channel(list[i].video.channelId)?.title ?? '',
                              style: TextStyle(color: t.textSoft, fontSize: AppTokens.fontSmall),
                            ),
                            Text('${S.editBefore}: ${list[i].video.title}', style: TextStyle(color: t.textSoft)),
                            Text(
                              '${S.editAfter}: ${list[i].after.title}',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: AppTokens.gapXs),
                            Wrap(
                              spacing: AppTokens.gapS,
                              runSpacing: AppTokens.gapXs,
                              children: [
                                if (list[i].after.title != list[i].video.title)
                                  const InfoChip(Icons.title, S.batchTitle),
                                if (list[i].after.description != list[i].video.description)
                                  const InfoChip(Icons.notes, S.batchDesc),
                                if (list[i].after.tags.join() != list[i].video.tags.join())
                                  InfoChip(Icons.sell, S.edits2(list[i].after.tags.take(5).join(', '))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.gapL),
          child: BigButton(
            key: const Key('apply-edits'),
            label: S.batchApply(on.length),
            icon: Icons.check,
            onPressed: on.isEmpty
                ? null
                : () => Navigator.pop(context, [
                    for (var i = 0; i < list.length; i++)
                      if (on.contains(i)) list[i],
                  ]),
          ),
        ),
      ),
    );
  }
}

class EditsScreen extends StatefulWidget {
  const EditsScreen({super.key, required this.user, this.channelId});
  final UserContext user;
  final String? channelId;
  @override
  State<EditsScreen> createState() => _EditsScreenState();
}

class _EditsScreenState extends State<EditsScreen> {
  UserContext get u => widget.user;
  final busy = Busy();

  @override
  Widget build(BuildContext context) {
    final today = dayKey(u.env.now());
    final list = u.editLog.list(targetType: 'video', parentId: widget.channelId);
    final todayApplied = list.where((e) => e.day == today && e.status == EditStatus.applied).length;
    return Scaffold(
      appBar: pageBar(context, S.editsTitle),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.pagePad,
            AppTokens.gapS,
            AppTokens.pagePad,
            AppTokens.bottomSpace,
          ),
          children: [
            TipBanner(
              text: S.editsTip,
              seen: u.settings.tipSeen('edits'),
              onSeen: () => u.settings.markTipSeen('edits'),
            ),
            SectionCard(
              title: S.dailyReportTitle,
              icon3d: 'undo',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Mascot(todayApplied > 0 ? MascotMood.done : MascotMood.hello, size: 64),
                      const SizedBox(width: AppTokens.gapM),
                      Expanded(child: Text(u.edits.dailySummary(today), key: const Key('daily-summary'))),
                    ],
                  ),
                  const SizedBox(height: AppTokens.gapM),
                  ButtonWrap(
                    children: [
                      BigButton(
                        label: S.homeVoiceSummary,
                        icon: Icons.volume_up,
                        primary: false,
                        onPressed: () => u.env.speaker.speak(u.edits.dailySummary(today)),
                      ),
                      if (todayApplied > 0)
                        BigButton(
                          key: const Key('revert-all'),
                          label: S.editRevertAll,
                          icon: Icons.undo,
                          danger: true,
                          onPressed: () => busy.run(() => _revertDay(today)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (list.isEmpty) const EmptyState(icon: 'undo', message: S.editsEmptyHow),
            for (var i = 0; i < list.length; i++) Appear(index: i, child: _tile(list[i])),
          ],
        ),
      ),
    );
  }

  Widget _tile(EditRecord e) {
    final t = context.tokens;
    final (Status? st, String label) = switch (e.status) {
      EditStatus.applied => (Status.done, S.editStatusApplied),
      EditStatus.reverted => (null, S.editStatusReverted),
      EditStatus.failed => (Status.problem, S.editStatusFailed),
    };
    return StripeCard(
      status: st,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppTokens.gapS,
            runSpacing: AppTokens.gapS,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (st == null) InfoChip(Icons.undo, label) else StatusBadge(st, label),
              InfoChip(Icons.calendar_today, e.day),
              InfoChip(Icons.visibility, S.editViews(e.viewsBefore, e.viewsAfter)),
            ],
          ),
          const SizedBox(height: AppTokens.gapS),
          Text('${S.editBefore}: ${e.before.title}', style: TextStyle(color: t.textSoft)),
          Row(
            children: [
              Icon(Icons.arrow_downward, size: 18, color: t.primary),
              const SizedBox(width: AppTokens.gapXs),
              Expanded(
                child: Text('${S.editAfter}: ${e.after.title}', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          if (e.status == EditStatus.failed && e.reason.isNotEmpty) Text(e.reason),
          if (e.status == EditStatus.applied) ...[
            const SizedBox(height: AppTokens.gapS),
            BigButton(
              key: Key('revert-${e.id}'),
              label: S.editRevert,
              icon: Icons.undo,
              onPressed: () => busy.run(() => _revert(e)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _revert(EditRecord e, {bool force = false}) async {
    final r = await u.edits.revert(e.id, force: force);
    if (!mounted) return;
    switch (r.outcome) {
      case RevertOutcome.reverted:
      case RevertOutcome.alreadyReverted:
        celebrate(context, S.editReverted);
      case RevertOutcome.newerEditExists:
        toast(context, S.editRevertNewerFirst);
      case RevertOutcome.conflict:
        if (await confirm(context, S.editRevertConflict, yes: S.editRevertAnyway)) {
          await _revert(e, force: true);
          return;
        }
      case RevertOutcome.failed:
        await showFailure(context, r.failure ?? Exception(), onRetry: () => _revert(e, force: force));
    }
    if (mounted) setState(() {});
  }

  Future<void> _revertDay(String day) async {
    if (!await confirmDanger(context, S.editsRevertAllAsk, yes: S.editRevertAll)) return;
    final r = await u.edits.revertDay(day);
    if (!mounted) return;
    toast(context, S.edits5(r.reverted, r.conflicts > 0 ? ' 유튜브에서 직접 바뀐 ${r.conflicts}개는 하나씩 확인해 주세요.' : ''));
    setState(() {});
  }
}
