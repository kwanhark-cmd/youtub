import 'dart:io';

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../core/failure.dart';
import '../core/strings.dart';
import '../features/ai/brain.dart';
import '../features/production/production_service.dart';
import '../features/production/thumbnail.dart';
import 'calendar_screen.dart';
import 'common.dart';
import 'tools_screen.dart';

ProductionService productionOf(UserContext u) => u.extensions['production']! as ProductionService;

/// 새 콘텐츠 만들기 창. 만든 콘텐츠를 돌려준다.
Future<Production?> newProductionFlow(
  BuildContext callerContext,
  UserContext u, {
  String? channelId,
  ContentFormat? format,
}) async {
  final context = alive(callerContext);
  if (context == null) return null;
  final chans = u.youtube.channels();
  if (chans.isEmpty) {
    toast(context, S.channelNone);
    return null;
  }
  var ch = channelId ?? chans.first.channelId;
  var fmt = format ?? ContentFormat.shorts;
  int? memoId;
  final topic = TextEditingController();
  final memos = u.memos.list(unusedOnly: true, limit: 30);
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
        title: const Text(S.produceNew),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: ch,
                isExpanded: true,
                decoration: const InputDecoration(labelText: S.produceChannel),
                items: [for (final x in chans) DropdownMenuItem(value: x.channelId, child: Text(x.title))],
                onChanged: (v) => setD(() => ch = v ?? ch),
              ),
              const SizedBox(height: AppTokens.gapM),
              const Text(S.produceFormat),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in ContentFormat.values)
                    ChoiceChip(
                      key: Key('format-${f.name}'),
                      label: Text(formatLabel(f)),
                      selected: fmt == f,
                      onSelected: (_) => setD(() => fmt = f),
                    ),
                ],
              ),
              const SizedBox(height: AppTokens.gapM),
              TextField(
                key: const Key('produce-topic'),
                controller: topic,
                decoration: const InputDecoration(labelText: S.produceTopic),
              ),
              if (memos.isNotEmpty) ...[
                const SizedBox(height: AppTokens.gapM),
                DropdownButtonFormField<int?>(
                  initialValue: memoId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: S.produceUseMemo),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text(S.prod1)),
                    for (final m in memos)
                      DropdownMenuItem<int?>(
                        value: m.id,
                        child: Text(m.text, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setD(() => memoId = v),
                ),
              ],
              const SizedBox(height: AppTokens.gapM),
              Text(S.prod2(productionOf(u).madeToday(), u.settings.produceDailyLimit)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(S.cancel)),
          FilledButton(
            key: const Key('produce-make'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text(S.produceMake),
          ),
        ],
      ),
    ),
  );
  if (go != true || !context.mounted) return null;
  if (!await confirmAiCost(context, u, calls: 1, output: 3000)) return null;
  if (!context.mounted) return null;
  try {
    return await runWithProgress(
      context,
      S.produceMake,
      (cancel, p) => productionOf(u).create(channelId: ch, format: fmt, topic: topic.text, memoId: memoId),
    );
  } on ProductionBlocked catch (e) {
    if (context.mounted) toast(context, e.message);
  } catch (e) {
    if (context.mounted) await showFailure(context, e);
  }
  return null;
}

/// 썸네일 그리는 함수 (테스트에서 빠른 가짜로 바꿀 수 있게).
Future<List<int>> Function(String text, int seed) thumbRenderer = (t, seed) => renderThumbnail(t, seed: seed);

/// 제작 상태 → 공통 상태 색.
Status productionStatusColor(ProductionStatus s) => switch (s) {
  ProductionStatus.draft => Status.progress,
  ProductionStatus.uploadTomorrow => Status.check,
  ProductionStatus.uploadedPrivate => Status.check,
  ProductionStatus.doneByUser => Status.done,
};

String formatIcon(ContentFormat f) => switch (f) {
  ContentFormat.shorts => 'fire',
  ContentFormat.long => 'create',
  ContentFormat.docu => 'corner',
  ContentFormat.image => 'picture',
  ContentFormat.talk => 'chat',
};

/// 제작 목록 한 줄 (가벼운 평면 카드).
Widget productionTile(
  BuildContext context,
  UserContext u,
  Production p, {
  required Key key,
  required VoidCallback onTap,
}) {
  final t = context.tokens;
  final st = productionStatusColor(p.status);
  return StripeCard(
    key: key,
    status: st,
    onTap: onTap,
    child: Row(
      children: [
        Icon3D(formatIcon(p.format), size: AppTokens.icon3dS + 8),
        const SizedBox(width: AppTokens.gapM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.title,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: AppTokens.fontBody),
              ),
              Text(
                '${formatLabel(p.format)} · ${u.youtube.channel(p.channelId)?.title ?? ''}',
                style: TextStyle(color: t.textSoft),
              ),
              const SizedBox(height: AppTokens.gapXs),
              StatusBadge(st, statusLabel(p.status), shake: p.status == ProductionStatus.uploadedPrivate),
            ],
          ),
        ),
        Icon(Icons.chevron_right, color: t.textSoft, size: AppTokens.iconM),
      ],
    ),
  );
}

String statusLabel(ProductionStatus s) => switch (s) {
  ProductionStatus.draft => S.prod3,
  ProductionStatus.uploadTomorrow => S.prod4,
  ProductionStatus.uploadedPrivate => S.prod5,
  ProductionStatus.doneByUser => S.blog9,
};

class ProduceScreen extends StatefulWidget {
  const ProduceScreen({super.key, required this.user});
  final UserContext user;
  @override
  State<ProduceScreen> createState() => _ProduceScreenState();
}

class _ProduceScreenState extends State<ProduceScreen> {
  UserContext get u => widget.user;
  int _limit = 30;

  @override
  Widget build(BuildContext context) {
    final ps = productionOf(u);
    final list = ps.list(limit: _limit);
    final review = ps.reviewList().length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppTokens.pagePad, AppTokens.gapS, AppTokens.pagePad, AppTokens.bottomSpace),
      children: [
        TipBanner(
          text: S.prodTip,
          seen: u.settings.tipSeen('produce'),
          onSeen: () => u.settings.markTipSeen('produce'),
        ),
        ButtonWrap(
          children: [
            BigButton(
              key: const Key('produce-new'),
              label: S.produceNew,
              icon: Icons.add,
              onPressed: () async {
                final p = await newProductionFlow(context, u);
                if (p != null && context.mounted) {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProductionDetailScreen(user: u, id: p.id),
                    ),
                  );
                }
                if (mounted) setState(() {});
              },
            ),
            BigButton(
              key: const Key('open-calendar'),
              label: S.calTitle,
              icon: Icons.calendar_month,
              primary: false,
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CalendarScreen(user: u)));
                if (mounted) setState(() {});
              },
            ),
            BigButton(
              key: const Key('open-review'),
              label: '${S.produceReviewList} ($review)',
              icon: Icons.fact_check,
              primary: false,
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReviewScreen(user: u)));
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: AppTokens.gapL),
        Text(S.produceDrafts, style: Theme.of(context).textTheme.titleLarge),
        if (list.isEmpty)
          EmptyState(
            icon: 'create',
            message: S.prodEmptyHow,
            actionLabel: S.produceNew,
            onAction: () async {
              await newProductionFlow(context, u);
              if (mounted) setState(() {});
            },
          ),
        for (var i = 0; i < list.length; i++)
          Appear(
            index: i,
            child: productionTile(
              context,
              u,
              list[i],
              key: Key('production-${list[i].id}'),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProductionDetailScreen(user: u, id: list[i].id),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
          ),
        if (list.length >= _limit)
          BigButton(label: S.loadMore, primary: false, onPressed: () => setState(() => _limit += 30)),
      ],
    );
  }
}

class ProductionDetailScreen extends StatefulWidget {
  const ProductionDetailScreen({super.key, required this.user, required this.id});
  final UserContext user;
  final int id;
  @override
  State<ProductionDetailScreen> createState() => _ProductionDetailScreenState();
}

class _ProductionDetailScreenState extends State<ProductionDetailScreen> {
  UserContext get u => widget.user;
  ProductionService get ps => productionOf(u);
  final busy = Busy();

  @override
  Widget build(BuildContext context) {
    final p = ps.byId(widget.id);
    if (p == null) return Scaffold(appBar: pageBar(context, S.navProduce), body: const EmptyHint(S.empty));
    Widget block(String label, String text) => SectionCard(
      title: label,
      trailing: IconButton(tooltip: S.copy, icon: const Icon(Icons.copy), onPressed: () => copyText(context, text)),
      child: SelectableText(text.isEmpty ? S.chan6 : text),
    );
    return Scaffold(
      appBar: pageBar(context, formatLabel(p.format)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.pagePad,
            AppTokens.gapS,
            AppTokens.pagePad,
            AppTokens.bottomSpace,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(productionStatusColor(p.status), statusLabel(p.status)),
            ),
            const SizedBox(height: AppTokens.gapS),
            block(S.prod6, p.title),
            block(S.chan5, p.description),
            block(S.chan7, p.tags.join(', ')),
            block(S.produceThumbnail, p.thumbnailText),
            block(S.produceScript, p.script),
            ButtonWrap(
              children: [
                BigButton(label: S.edit, icon: Icons.edit, primary: false, onPressed: () => _edit(p)),
                BigButton(
                  key: const Key('suggest-keywords'),
                  label: S.kwSuggest,
                  icon: Icons.manage_search,
                  primary: false,
                  onPressed: () => busy.run(() => _keywords(p)),
                ),
              ],
            ),
            SectionCard(
              title: S.thumbTitle,
              icon: Icons.image,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.hasThumb)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: Image.file(
                        File(p.thumbPath),
                        key: ValueKey(p.thumbPath),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon3D('picture', size: AppTokens.icon3dL),
                      ),
                    )
                  else
                    const Text(S.thumbNone),
                  if (p.extra['thumbError'] != null) const Text(S.thumbUploadFailed),
                  const SizedBox(height: AppTokens.gapS),
                  ButtonWrap(
                    children: [
                      BigButton(
                        key: const Key('thumb-compare'),
                        label: S.thumbCompare,
                        icon: Icons.compare,
                        onPressed: () => busy.run(() => _compareThumbs(p)),
                      ),
                      BigButton(
                        key: const Key('make-thumb'),
                        label: S.thumbMake,
                        icon: Icons.brush,
                        primary: false,
                        onPressed: () => busy.run(() async {
                          await ps.makeThumbnail(p.id, thumbRenderer);
                          if (mounted) setState(() {});
                        }),
                      ),
                      BigButton(
                        label: S.thumbAttach,
                        icon: Icons.add_photo_alternate,
                        primary: false,
                        onPressed: () => busy.run(() => _attachThumb(p)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (p.isUploadable) ...[
              SectionCard(
                title: S.prod7,
                icon: Icons.movie,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.hasVideo ? S.prod8(p.videoSource == 'own' ? '내가 만든 영상' : '힉스필드') : S.prod9),
                    const SizedBox(height: AppTokens.gapS),
                    const Text(S.prod10),
                    const SizedBox(height: AppTokens.gapS),
                    ButtonWrap(
                      children: [
                        BigButton(
                          key: const Key('attach-video'),
                          label: S.produceAddOwnVideo,
                          icon: Icons.upload_file,
                          primary: false,
                          onPressed: () => busy.run(() => _attach(p)),
                        ),
                        BigButton(
                          key: const Key('higgsfield'),
                          label: S.produceHiggsfield,
                          icon: Icons.auto_awesome,
                          primary: false,
                          onPressed: () => busy.run(() => _higgs(p)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (p.status == ProductionStatus.draft || p.status == ProductionStatus.uploadTomorrow)
                BigButton(
                  key: const Key('upload'),
                  label: S.produceUpload,
                  icon: Icons.cloud_upload,
                  onPressed: () => busy.run(() => _upload(p)),
                ),
              if (p.status == ProductionStatus.uploadedPrivate) ...[
                BigButton(
                  label: S.produceOpenYoutube,
                  icon: Icons.open_in_new,
                  primary: false,
                  onPressed: () => u.env.launchUrl(Uri.parse(p.studioUrl)),
                ),
                const SizedBox(height: AppTokens.gapM),
                BigButton(
                  key: const Key('mark-done'),
                  label: S.produceMarkPublished,
                  icon: Icons.check,
                  onPressed: () {
                    ps.markDoneByUser(p.id);
                    setState(() {});
                  },
                ),
              ],
            ] else
              const Text(S.prod11),
            const SizedBox(height: AppTokens.gapM),
            BigButton(
              label: S.delete,
              icon: Icons.delete_outline,
              danger: true,
              onPressed: () async {
                if (await confirmDanger(context, S.prod12)) {
                  ps.delete(p.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 검색어 추천: 인공지능 비용을 먼저 보여 주고, 고른 것만 키워드에 더한다.
  Future<void> _keywords(Production p) async {
    if (!await confirmAiCost(context, u, calls: 1, input: 1500, output: 300)) return;
    if (!mounted) return;
    final ch = u.youtube.channel(p.channelId);
    final style = StyleCard.decode(ch?.styleJson) ?? Brain.mockStyle(ch?.title ?? '', const []);
    final list = await runWithProgress(context, S.kwSuggest, (c, _) => u.brain.suggestKeywords(p.title, p.tags, style));
    if (list == null || !mounted) return;
    if (list.isEmpty) {
      toast(context, S.kwNone);
      return;
    }
    final picked = <String>{};
    final cost = u.ai.isPracticeMode
        ? S.kwCostFree
        : S.kwCost(u.ai.estimateCost('x' * 750, 'x' * 750, expectedOutput: 300).toStringAsFixed(4));
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: const Text(S.kwSuggest),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                InfoChip(Icons.payments, cost),
                const SizedBox(height: AppTokens.gapS),
                const Text(S.kwHelp),
                const SizedBox(height: AppTokens.gapM),
                Wrap(
                  spacing: AppTokens.gapS,
                  runSpacing: AppTokens.gapS,
                  children: [
                    for (final k in list)
                      FilterChip(
                        key: Key('kw-$k'),
                        label: Text(k),
                        selected: picked.contains(k),
                        onSelected: (v) => setD(() => v ? picked.add(k) : picked.remove(k)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text(S.cancel)),
            FilledButton(key: const Key('kw-add'), onPressed: () => Navigator.pop(d, true), child: const Text(S.kwAdd)),
          ],
        ),
      ),
    );
    if (ok != true || picked.isEmpty) return;
    ps.updateText(p.id, tags: [...p.tags, ...picked]);
    if (mounted) {
      celebrate(context, S.kwAdded(picked.length));
      setState(() {});
    }
  }

  Future<void> _edit(Production p) async {
    final t = TextEditingController(text: p.title);
    final d = TextEditingController(text: p.description);
    final k = TextEditingController(text: p.tags.join(', '));
    final th = TextEditingController(text: p.thumbnailText);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(S.edit),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: t,
                decoration: const InputDecoration(labelText: S.prod6),
              ),
              const SizedBox(height: AppTokens.gapM),
              TextField(
                controller: d,
                maxLines: 6,
                decoration: const InputDecoration(labelText: S.chan5),
              ),
              const SizedBox(height: AppTokens.gapM),
              TextField(
                controller: k,
                decoration: const InputDecoration(labelText: S.prod13),
              ),
              const SizedBox(height: AppTokens.gapM),
              TextField(
                controller: th,
                decoration: const InputDecoration(labelText: S.produceThumbnail),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text(S.save)),
        ],
      ),
    );
    if (ok != true) return;
    ps.updateText(
      p.id,
      title: t.text,
      description: d.text,
      tags: k.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      thumbnailText: th.text,
    );
    if (mounted) setState(() {});
  }

  /// 썸네일 2개를 만들어 나란히 보여 주고 고르게 한다.
  Future<void> _compareThumbs(Production p) async {
    final paths = await runWithProgress(
      context,
      S.thumbCompare,
      (c, _) => ps.makeThumbnailChoices(p.id, thumbRenderer),
    );
    if (paths == null || !mounted) return;
    final pick = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text(S.thumbCompareTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(S.thumbCompareHelp),
              const SizedBox(height: AppTokens.gapM),
              for (var i = 0; i < paths.length; i++) ...[
                Press3D(
                  key: Key('thumb-choice-$i'),
                  color: d.tokens.card,
                  onTap: () => Navigator.pop(d, paths[i]),
                  semanticLabel: S.thumbChoice(i == 0 ? 'A' : 'B'),
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.gapS),
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.file(
                            File(paths[i]),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon3D('picture', size: AppTokens.icon3dL),
                          ),
                        ),
                        const SizedBox(height: AppTokens.gapS),
                        Text(S.thumbChoice(i == 0 ? 'A' : 'B'), style: const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.gapM),
              ],
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text(S.cancel))],
      ),
    );
    if (pick == null || !mounted) return;
    ps.chooseThumbnail(p.id, pick);
    celebrate(context, S.thumbChosen);
    setState(() {});
  }

  Future<void> _attachThumb(Production p) async {
    final path = await u.env.pickFile?.call(ProductionService.imageExtensions);
    if (path == null) return;
    try {
      ps.attachThumbnail(p.id, path);
    } catch (e) {
      if (mounted) await showFailure(context, e);
    }
    if (mounted) setState(() {});
  }

  Future<void> _attach(Production p) async {
    final path = await u.env.pickFile?.call(ProductionService.videoExtensions);
    if (path == null) return;
    try {
      ps.attachOwnVideo(p.id, path);
    } catch (e) {
      if (mounted) await showFailure(context, e);
    }
    if (mounted) setState(() {});
  }

  Future<void> _higgs(Production p) async {
    try {
      final q = await ps.higgsfieldQuote(p.id);
      if (!mounted) return;
      final msg =
          S.produceHiggsfieldConfirm(q.estimate, q.left) + (await u.tools.higgsConnected ? '' : S.prodPracticeCredits);
      if (!mounted || !await confirm(context, msg, yes: S.prod14)) return;
      if (!mounted) return;
      await runWithProgress(
        context,
        S.produceHiggsfield,
        (cancel, _) => ps.generateWithHiggsfield(p.id, userApproved: true, cancel: cancel),
      );
    } on ProductionBlocked catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) await showFailure(context, e);
    }
    if (mounted) setState(() {});
  }

  /// 업로드 전 확인: AI 표시 방법 고르기 + 화면·음성 확인.
  Future<void> _upload(Production p) async {
    if (!p.hasVideo) {
      toast(context, S.produceNeedVideo);
      return;
    }
    var method = p.aiLabelMethod.isEmpty ? u.settings.aiLabelMethod : p.aiLabelMethod;
    if (u.settings.ttsEnabled) await u.env.speaker.speak(S.produceUploadConfirm);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text(S.voiceConfirmTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(S.produceUploadConfirm, style: TextStyle(fontSize: AppTokens.fontBody + 1)),
                const SizedBox(height: AppTokens.gapM),
                const Text(S.produceAiLabelCheck, style: TextStyle(fontWeight: FontWeight.w800)),
                RadioGroup<String>(
                  groupValue: method,
                  onChanged: (v) => setD(() => method = v ?? method),
                  child: const Column(
                    children: [
                      RadioListTile<String>(value: 'description', title: Text(S.produceAiLabelDesc)),
                      RadioListTile<String>(value: 'channel', title: Text(S.produceAiLabelChannel)),
                      RadioListTile<String>(value: 'setting', title: Text(S.produceAiLabelSetting)),
                    ],
                  ),
                ),
                if (method == 'channel') const Text(S.prod15),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(S.cancel)),
            FilledButton(
              key: const Key('upload-confirm'),
              onPressed: () => Navigator.pop(c, true),
              child: const Text(S.prod16),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final st = await runWithProgress(
        context,
        S.produceUpload,
        (cancel, _) => ps.uploadPrivate(p.id, userConfirmed: true, aiLabelMethod: method),
      );
      if (!mounted || st == null) return;
      final msg = st == ProductionStatus.uploadedPrivate ? S.produceUploaded : S.produceDeferred;
      if (st == ProductionStatus.uploadedPrivate) {
        celebrate(context, msg);
      } else {
        toast(context, msg);
      }
      if (u.settings.ttsEnabled) await u.env.speaker.speak(msg);
    } on ProductionBlocked catch (e) {
      if (mounted) toast(context, e.message);
    } on AppFailure catch (e) {
      if (mounted) await showFailure(context, e, onRetry: () => _upload(p));
    }
    if (mounted) setState(() {});
  }
}

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.user});
  final UserContext user;
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final list = productionOf(u).reviewList();
    return Scaffold(
      appBar: pageBar(context, S.produceReviewList),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTokens.gapL),
          children: [
            const Text(S.prod17),
            const SizedBox(height: AppTokens.gapM),
            if (list.isEmpty) const EmptyState(icon: 'party', message: S.prodReviewEmpty),
            for (var i = 0; i < list.length; i++)
              Appear(
                index: i,
                child: productionTile(
                  context,
                  u,
                  list[i],
                  key: Key('review-${list[i].id}'),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ProductionDetailScreen(user: u, id: list[i].id),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
