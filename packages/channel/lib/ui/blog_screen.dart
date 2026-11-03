import 'package:flutter/material.dart';

import '../app/services.dart';
import '../core/strings.dart';
import '../features/blog/blog_service.dart';
import '../features/edits/edit_service.dart';
import '../features/production/production_service.dart' show ProductionBlocked;
import 'channels_screen.dart' show editStyleDialog;
import 'common.dart';

BlogService blogOf(UserContext u) => u.extensions['blog']! as BlogService;

class BlogScreen extends StatefulWidget {
  const BlogScreen({super.key, required this.user});
  final UserContext user;
  @override
  State<BlogScreen> createState() => _BlogScreenState();
}

class _BlogScreenState extends State<BlogScreen> {
  UserContext get u => widget.user;
  BlogService get bs => blogOf(u);

  Future<void> _connectBlogger() async {
    try {
      final r = await runWithProgress(context, S.blogAddBlogger, (cancel, p) async {
        final sites = await bs.connectBlogger();
        for (final s in sites) {
          await bs.syncPosts(s.id, cancel: cancel, progress: p);
        }
        return sites;
      });
      if (mounted && r != null) toast(context, S.blog1(r.length));
    } catch (e) {
      if (mounted) await showFailure(context, e, onRetry: _connectBlogger);
    }
    if (mounted) setState(() {});
  }

  Future<void> _addTistory() async {
    final name = TextEditingController();
    final url = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(S.blogAddTistory),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('tistory-name'),
              controller: name,
              decoration: const InputDecoration(labelText: S.blogTistoryName),
            ),
            const SizedBox(height: AppTokens.gapM),
            TextField(
              controller: url,
              decoration: const InputDecoration(labelText: S.blogTistoryUrl),
            ),
            const SizedBox(height: AppTokens.gapM),
            const Text(S.blogTistoryCopyHint),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(S.cancel)),
          FilledButton(
            key: const Key('tistory-ok'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text(S.save),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      bs.addTistory(name.text, url.text);
    } catch (e) {
      if (mounted) await showFailure(context, e);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sites = bs.sites();
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppTokens.pagePad, AppTokens.gapS, AppTokens.pagePad, AppTokens.bottomSpace),
      children: [
        TipBanner(text: S.blogTip, seen: u.settings.tipSeen('blog'), onSeen: () => u.settings.markTipSeen('blog')),
        ButtonWrap(
          children: [
            BigButton(
              key: const Key('add-blogger'),
              label: S.blogAddBlogger,
              icon: Icons.add_link,
              onPressed: _connectBlogger,
            ),
            BigButton(
              key: const Key('add-tistory'),
              label: S.blogAddTistory,
              icon: Icons.add,
              primary: false,
              onPressed: _addTistory,
            ),
          ],
        ),
        const SizedBox(height: AppTokens.gapM),
        if (sites.isEmpty)
          EmptyState(icon: 'blog', message: S.blogEmptyHow, actionLabel: S.blogAddBlogger, onAction: _connectBlogger),
        for (var i = 0; i < sites.length; i++)
          Appear(
            index: i,
            child: ListCard(
              key: Key('site-${sites[i].id}'),
              icon: sites[i].isTistory ? 'memo' : 'blog',
              title: sites[i].title,
              subtitle: sites[i].isTistory ? S.blog2 : S.blog3(bs.postTotal(sites[i].id)),
              status: sites[i].isTistory ? null : Status.done,
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BlogDetailScreen(user: u, siteId: sites[i].id),
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

class BlogDetailScreen extends StatefulWidget {
  const BlogDetailScreen({super.key, required this.user, required this.siteId});
  final UserContext user;
  final int siteId;
  @override
  State<BlogDetailScreen> createState() => _BlogDetailScreenState();
}

class _BlogDetailScreenState extends State<BlogDetailScreen> {
  UserContext get u => widget.user;
  BlogService get bs => blogOf(u);
  final busy = Busy();
  int _limit = 30;

  @override
  Widget build(BuildContext context) {
    final s = bs.site(widget.siteId);
    if (s == null) return Scaffold(appBar: pageBar(context, S.navBlog), body: const EmptyHint(S.empty));
    final style = s.style;
    final drafts = bs.drafts(s.id);
    final edits = u.editLog.list(targetType: 'post', parentId: 'blog${s.id}', limit: 50);
    final posts = bs.posts(s.id, limit: _limit);
    return Scaffold(
      appBar: pageBar(context, s.title),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTokens.gapL),
          children: [
            if (s.isTistory) const Text(S.blogTistoryCopyHint),
            const Text(S.blogPerDay),
            const SizedBox(height: AppTokens.gapM),
            ButtonWrap(
              children: [
                BigButton(
                  key: const Key('blog-new'),
                  label: S.blogNewPost,
                  icon: Icons.post_add,
                  onPressed: () => busy.run(() => _new(s)),
                ),
                if (!s.isTistory) ...[
                  BigButton(
                    key: const Key('blog-edits'),
                    label: S.blogRunEdits,
                    icon: Icons.auto_fix_high,
                    primary: false,
                    onPressed: () => busy.run(() => _edits(s)),
                  ),
                  BigButton(
                    label: S.channelSync,
                    icon: Icons.refresh,
                    primary: false,
                    onPressed: () => busy.run(() => _sync(s)),
                  ),
                ],
                BigButton(
                  label: S.delete,
                  icon: Icons.link_off,
                  danger: true,
                  onPressed: () => busy.run(() => _remove(s)),
                ),
              ],
            ),
            SectionCard(
              title: S.blog4,
              icon: Icons.palette,
              trailing: style == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: S.edit,
                      onPressed: () async {
                        final r = await editStyleDialog(context, style);
                        if (r != null) bs.saveStyle(s.id, r);
                        if (mounted) setState(() {});
                      },
                    ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(style == null ? S.styleEmpty : style.describe()),
                  const SizedBox(height: AppTokens.gapS),
                  BigButton(
                    label: S.styleAnalyze,
                    primary: false,
                    onPressed: () => busy.run(() async {
                      await bs.analyze(s.id);
                      if (mounted) setState(() {});
                    }),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: S.blog5,
              icon: Icons.drafts,
              child: Column(
                children: [if (drafts.isEmpty) const Text(S.empty), for (final d in drafts) _draftTile(s, d)],
              ),
            ),
            if (!s.isTistory)
              SectionCard(
                title: S.blog6(S.channelEdits),
                icon: Icons.history,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (edits.isEmpty) const Text(S.editsNone),
                    for (final e in edits)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${e.before.title} → ${e.after.title}'),
                        subtitle: Text(
                          '${e.day} · ${e.status == EditStatus.applied
                              ? S.editStatusApplied
                              : e.status == EditStatus.reverted
                              ? S.editStatusReverted
                              : S.editStatusFailed}',
                        ),
                        trailing: e.status == EditStatus.applied
                            ? TextButton(
                                key: Key('post-revert-${e.id}'),
                                onPressed: () => busy.run(() => _revert(e.id)),
                                child: const Text(S.editRevert),
                              )
                            : null,
                      ),
                  ],
                ),
              ),
            if (!s.isTistory)
              SectionCard(
                title: '${S.blogPosts} (${bs.postTotal(s.id)})',
                icon: Icons.article,
                child: Column(
                  children: [
                    for (final p in posts)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.title),
                        subtitle: Text(p.labels.join(', ')),
                      ),
                    if (posts.length >= _limit)
                      BigButton(label: S.loadMore, primary: false, onPressed: () => setState(() => _limit += 30)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _draftTile(BlogSite s, BlogDraftRow d) {
    final done = d.status == 'postedByUser' || d.status == 'publishedByUser';
    return StripeCard(
      status: done ? Status.done : Status.check,
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d.title, style: Theme.of(context).textTheme.titleMedium),
            StatusBadge(done ? Status.done : Status.check, done ? S.blog9 : S.blogWaiting),
            Text(switch (d.status) {
              'copyReady' => S.blog7,
              'draftOnBlogger' => S.blog8,
              _ => S.blog9,
            }),
            const SizedBox(height: AppTokens.gapS),
            ButtonWrap(
              children: [
                BigButton(
                  key: Key('copy-title-${d.id}'),
                  label: S.blogCopyTitle,
                  icon: Icons.copy,
                  primary: false,
                  onPressed: () => copyText(context, d.title),
                ),
                BigButton(
                  key: Key('copy-body-${d.id}'),
                  label: S.blogCopyBody,
                  icon: Icons.copy,
                  primary: false,
                  onPressed: () => copyText(context, BlogService.tistoryBody(d)),
                ),
                BigButton(
                  label: S.blogCopyTags,
                  icon: Icons.copy,
                  primary: false,
                  onPressed: () => copyText(context, BlogService.tistoryTags(d)),
                ),
                if (d.status == 'draftOnBlogger')
                  BigButton(
                    label: S.blog10,
                    icon: Icons.open_in_new,
                    primary: false,
                    onPressed: () => u.env.launchUrl(Uri.parse(bs.bloggerEditUrl(s, d.remotePostId))),
                  ),
                if (!done)
                  BigButton(
                    label: d.status == 'copyReady' ? S.blog11 : S.blog12,
                    icon: Icons.check,
                    onPressed: () {
                      bs.markDraftDone(d.id);
                      setState(() {});
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _new(BlogSite s) async {
    final topic = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(S.blogNewPost),
        content: TextField(
          key: const Key('blog-topic'),
          controller: topic,
          decoration: const InputDecoration(labelText: S.produceTopic),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(S.cancel)),
          FilledButton(
            key: const Key('blog-make'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text(S.produceMake),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!await confirmAiCost(context, u, calls: 1, output: 3000)) return;
    if (!mounted) return;
    try {
      await runWithProgress(context, S.blogNewPost, (c, p) => bs.newPost(s.id, topic: topic.text));
      if (mounted) toast(context, s.isTistory ? S.blogTistoryCopyHint : S.blogDraftSaved);
    } on ProductionBlocked catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) await showFailure(context, e, onRetry: () => _new(s));
    }
    if (mounted) setState(() {});
  }

  Future<void> _edits(BlogSite s) async {
    try {
      final n = await runWithProgress(context, S.blogRunEdits, (c, p) => bs.runEdits(s.id, cancel: c));
      if (mounted) toast(context, n == 0 ? S.editsNone : S.blog13(n));
    } catch (e) {
      if (mounted) await showFailure(context, e);
    }
    if (mounted) setState(() {});
  }

  Future<void> _sync(BlogSite s) async {
    try {
      await runWithProgress(context, S.channelSync, (c, p) => bs.syncPosts(s.id, cancel: c, progress: p));
    } catch (e) {
      if (mounted) await showFailure(context, e, onRetry: () => _sync(s));
    }
    if (mounted) setState(() {});
  }

  Future<void> _revert(int id, {bool force = false}) async {
    final r = await bs.revert(id, force: force);
    if (!mounted) return;
    switch (r.outcome) {
      case RevertOutcome.reverted:
      case RevertOutcome.alreadyReverted:
        toast(context, S.editReverted);
      case RevertOutcome.newerEditExists:
        toast(context, S.editRevertNewerFirst);
      case RevertOutcome.conflict:
        if (await confirm(context, S.editRevertConflict, yes: S.editRevertAnyway)) return _revert(id, force: true);
      case RevertOutcome.failed:
        await showFailure(context, r.failure ?? Exception(), onRetry: () => _revert(id, force: force));
    }
    if (mounted) setState(() {});
  }

  Future<void> _remove(BlogSite s) async {
    if (!await confirmDanger(context, S.blog14(s.title))) return;
    await bs.removeSite(s.id);
    if (mounted) Navigator.pop(context);
  }
}
