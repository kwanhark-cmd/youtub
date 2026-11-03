import 'package:flutter/material.dart';

import '../app/services.dart';
import '../core/failure.dart';
import '../core/strings.dart';
import '../features/ai/brain.dart';
import '../features/production/desc_template.dart';
import '../features/youtube/models.dart';
import '../features/youtube/youtube_service.dart';
import 'common.dart';
import 'edits_screen.dart';

/// 채널 등록: 주소 입력 + "구글로 연결". 연습 모드에서는 가짜 로그인 창.
Future<void> connectGoogleFlow(BuildContext callerContext, UserContext u) async {
  final context = alive(callerContext);
  if (context == null) return;
  final url = TextEditingController();
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text(S.channelAdd),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('channel-url'),
              controller: url,
              decoration: const InputDecoration(labelText: S.channelUrl),
            ),
            const SizedBox(height: AppTokens.gapM),
            const Text(S.channelConnectHint),
            if (u.youtube.isPracticeMode) ...[
              const SizedBox(height: AppTokens.gapM),
              const Text(S.mockLoginBody, style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(S.cancel)),
        FilledButton.icon(
          key: const Key('connect-google'),
          onPressed: () => Navigator.pop(c, true),
          icon: const Icon(Icons.login),
          label: Text(u.youtube.isPracticeMode ? S.mockLoginButton : S.channelConnectGoogle),
        ),
      ],
    ),
  );
  if (go != true) return;
  try {
    // ignore: use_build_context_synchronously — 도우미가 alive() 로 살아 있는 화면을 다시 찾는다
    final rows = await runWithProgress(context, S.channelConnectGoogle, (cancel, p) async {
      final r = await u.youtube.connectGoogle(channelUrl: url.text);
      for (var i = 0; i < r.length; i++) {
        p(i / r.length, S.chan1(r[i].title));
        try {
          await u.youtube.syncChannel(r[i].channelId, cancel: cancel);
        } catch (e) {
          u.env.logger.warn(S.chan2(e));
        }
      }
      return r;
    });
    if (rows == null) return;
    final empty = rows.where((r) => u.youtube.videoTotal(r.channelId) == 0).length;
    // ignore: use_build_context_synchronously — 도우미가 alive() 로 살아 있는 화면을 다시 찾는다
    toast(context, empty == 0 ? S.channelAdded(rows.length) : S.chanAddedSomeEmpty(rows.length, empty));
  } on NoChannelsFailure {
    // 오류가 아니라 안내: 이 계정에는 채널이 없다
    // ignore: use_build_context_synchronously — 도우미가 alive() 로 살아 있는 화면을 다시 찾는다
    final again = await confirm(context, S.chanNoChannelAccount, yes: S.chanOtherAccount, no: S.close);
    // ignore: use_build_context_synchronously — 도우미가 alive() 로 살아 있는 화면을 다시 찾는다
    if (again) await connectGoogleFlow(context, u);
  } catch (e) {
    await showFailure(
      // ignore: use_build_context_synchronously — 도우미가 alive() 로 살아 있는 화면을 다시 찾는다
      context,
      e,
      where: '구글 연결',
      onRetry: () => connectGoogleFlow(context, u),
      onReconnect: () => connectGoogleFlow(context, u),
    );
  }
}

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key, required this.user});
  final UserContext user;

  /// 채널별 확인 대기 개수 (2단계에서 연결).
  static int Function(UserContext u, String channelId)? waitingCount;
  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  UserContext get u => widget.user;

  Future<void> _add() async {
    await connectGoogleFlow(context, u);
    if (mounted) setState(() {});
  }

  Future<void> _open(String channelId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChannelDetailScreen(user: u, channelId: channelId),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chans = u.youtube.channels();
    final broken = u.youtube.brokenAccounts();
    final brokenIds = broken.map((a) => a.id).toSet();
    final waiting = ChannelsScreen.waitingCount;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppTokens.pagePad, AppTokens.gapS, AppTokens.pagePad, AppTokens.bottomSpace),
      children: [
        TipBanner(
          text: S.chanTip,
          seen: u.settings.tipSeen('channels'),
          onSeen: () => u.settings.markTipSeen('channels'),
        ),
        BigButton(key: const Key('add-channel'), label: S.channelAdd, icon: Icons.add, onPressed: _add),
        for (final a in broken)
          StripeCard(
            status: Status.problem,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const StatusBadge(Status.problem, S.dashBroken, shake: true),
                const SizedBox(height: AppTokens.gapS),
                Text('${a.label}: ${S.failureMessage(FailureKind.permissionRevoked)}'),
                const SizedBox(height: AppTokens.gapS),
                BigButton(label: S.reconnect, icon: Icons.link, onPressed: _add),
              ],
            ),
          ),
        const SizedBox(height: AppTokens.gapM),
        if (chans.isEmpty)
          EmptyState(icon: 'video', message: S.chanEmptyHow, actionLabel: S.channelAdd, onAction: _add),
        for (var i = 0; i < chans.length; i++)
          Appear(
            index: i,
            child: _channelCard(
              t,
              chans[i],
              brokenIds.contains(chans[i].accountId),
              waiting?.call(u, chans[i].channelId) ?? 0,
            ),
          ),
      ],
    );
  }

  /// 채널 카드: 왼쪽 상태 색 띠 + 큰 썸네일(160 이상) + 이름·배지 + 숫자 3개를 아이콘과 한 줄로.
  /// 테두리는 연결이 끊겼을 때만 (상태 표시).
  Widget _channelCard(AppTokens t, ChannelRow c, bool broken, int waiting) {
    final status = broken ? Status.problem : Status.done;
    final thumb = thumbFor(u, c.channelId);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    Widget stat(IconData icon, String v, String label) => Semantics(
      label: '$label $v',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: t.hueStrong(Hue.blue)),
            const SizedBox(width: AppTokens.gapXs),
            Text(
              v,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: AppTokens.fontBody + 1, color: t.text),
            ),
          ],
        ),
      ),
    );
    final thumbBox = ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
      child: Container(
        width: 160,
        height: 90,
        color: t.tileBg(Hue.blue),
        alignment: Alignment.center,
        child: thumb.isNotEmpty
            ? Image.network(
                thumb,
                width: 160,
                height: 90,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon3D('video', size: 64),
              )
            : const Icon3D('video', size: 64),
      ),
    );
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          c.title,
          style: TextStyle(fontSize: AppTokens.fontSection, fontWeight: FontWeight.w800, color: t.text),
        ),
        const SizedBox(height: AppTokens.gapS),
        Wrap(
          spacing: AppTokens.gapS,
          runSpacing: AppTokens.gapS,
          children: [
            StatusBadge(status, broken ? S.dashBroken : S.chanConnected, shake: broken),
            if (waiting > 0) StatusBadge(Status.check, S.dash5(waiting), shake: true),
          ],
        ),
      ],
    );
    // 좁은 화면·아주 큰 글씨: 썸네일 위, 내용 아래
    final narrow = MediaQuery.sizeOf(context).width / scale < 440;
    return Container(
      key: Key('channel-${c.channelId}'),
      margin: const EdgeInsets.only(bottom: AppTokens.gapL),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppTokens.radiusCard), boxShadow: t.soft()),
      child: Material(
        color: t.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          side: broken
              ? BorderSide(color: t.danger, width: 3)
              : (t.highContrast ? BorderSide(color: t.border, width: 2) : BorderSide.none),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            UiPrefs.tap();
            _open(c.channelId);
          },
          // 왼쪽 상태 색 띠는 겹쳐 그림 (높이 맞추기 계산 없이)
          child: Stack(
            children: [
              Positioned(left: 0, top: 0, bottom: 0, width: 10, child: ColoredBox(color: t.statusColor(status))),
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(AppTokens.gapL),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (narrow) ...[
                              thumbBox,
                              const SizedBox(height: AppTokens.gapM),
                              head,
                            ] else
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  thumbBox,
                                  const SizedBox(width: AppTokens.gapL),
                                  Expanded(child: head),
                                ],
                              ),
                            const SizedBox(height: AppTokens.gapM),
                            // 숫자 3개: 한 줄 (넘치면 글씨를 줄여 맞춤)
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  stat(Icons.people_alt, S.num(c.subscriberCount), S.chanStatSubs),
                                  const SizedBox(width: AppTokens.gapL),
                                  stat(Icons.play_circle_fill, S.num(c.videoCount), S.chanStatVideos),
                                  const SizedBox(width: AppTokens.gapL),
                                  stat(Icons.visibility, S.num(c.viewCount), S.chanStatViews),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(right: AppTokens.gapS),
                        child: Icon(Icons.chevron_right, color: t.textSoft, size: AppTokens.iconM),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 채널 썸네일 주소 (없으면 빈 문자열).
String thumbFor(UserContext u, String channelId) {
  final r = u.db.select('SELECT thumbnail FROM channels WHERE channel_id = ?', [channelId]);
  return r.isEmpty ? '' : (r.first['thumbnail'] as String);
}

class ChannelDetailScreen extends StatefulWidget {
  const ChannelDetailScreen({super.key, required this.user, required this.channelId});
  final UserContext user;
  final String channelId;
  @override
  State<ChannelDetailScreen> createState() => _ChannelDetailScreenState();
}

class _ChannelDetailScreenState extends State<ChannelDetailScreen> {
  UserContext get u => widget.user;
  final List<YtVideo> _videos = [];
  int _total = 0;
  final busy = Busy();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _videos
      ..clear()
      ..addAll(u.youtube.videos(widget.channelId, limit: 30));
    _total = u.youtube.videoTotal(widget.channelId);
  }

  void _more() => setState(() => _videos.addAll(u.youtube.videos(widget.channelId, offset: _videos.length, limit: 30)));

  Future<void> _sync() async {
    try {
      await runWithProgress(
        context,
        S.channelSync,
        (cancel, p) => u.youtube.syncChannel(widget.channelId, cancel: cancel, progress: p),
      );
    } catch (e) {
      if (mounted) await showFailure(context, e, onRetry: _sync, onReconnect: () => connectGoogleFlow(context, u));
    }
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final c = u.youtube.channel(widget.channelId);
    if (c == null) return Scaffold(appBar: pageBar(context, S.navChannels), body: const EmptyHint(S.empty));
    final style = StyleCard.decode(c.styleJson);
    return Scaffold(
      appBar: pageBar(context, c.title),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.pagePad,
            AppTokens.gapS,
            AppTokens.pagePad,
            AppTokens.bottomSpace,
          ),
          children: [
            Wrap(
              spacing: AppTokens.gapS,
              runSpacing: AppTokens.gapS,
              children: [
                InfoChip(Icons.people, S.subscribers(c.subscriberCount)),
                InfoChip(Icons.video_library, S.videoCount(c.videoCount)),
                InfoChip(Icons.visibility, S.views(c.viewCount)),
              ],
            ),
            const SizedBox(height: AppTokens.gapM),
            ButtonWrap(
              children: [
                BigButton(
                  key: const Key('sync'),
                  label: S.channelSync,
                  icon: Icons.refresh,
                  onPressed: () => busy.run(_sync),
                ),
                BigButton(
                  label: S.channelEdits,
                  icon: Icons.history,
                  primary: false,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EditsScreen(user: u, channelId: c.channelId),
                    ),
                  ),
                ),
                BigButton(
                  key: const Key('tpl-edit'),
                  label: S.tplTitle,
                  icon: Icons.push_pin,
                  primary: false,
                  onPressed: () {
                    final store = DescTemplateStore(u.db);
                    _editTemplate(c.channelId, store, store.get(c.channelId));
                  },
                ),
                BigButton(
                  label: S.channelDisconnect,
                  icon: Icons.link_off,
                  danger: true,
                  onPressed: () => _disconnect(c),
                ),
              ],
            ),
            SectionCard(
              title: S.channelStyle,
              icon3d: 'sparkles',
              trailing: style == null
                  ? null
                  : IconButton(tooltip: S.edit, icon: const Icon(Icons.edit), onPressed: () => _editStyle(c, style)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (style == null) const Text(S.styleEmpty) else _styleView(style),
                  const SizedBox(height: AppTokens.gapM),
                  BigButton(
                    key: const Key('analyze-style'),
                    label: S.styleAnalyze,
                    icon: Icons.auto_awesome,
                    primary: style == null,
                    onPressed: () => busy.run(() => _analyze(c)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.gapS),
            Row(
              children: [
                const Icon3D('video', size: AppTokens.icon3dS),
                const SizedBox(width: AppTokens.gapS),
                Expanded(child: Text('${S.channelVideos} ($_total)', style: Theme.of(context).textTheme.titleLarge)),
              ],
            ),
            if (_videos.isEmpty) const EmptyHint(S.chanNoVideos),
            for (var i = 0; i < _videos.length; i++) _videoTile(_videos[i], i),
            if (_videos.length < _total) BigButton(label: S.loadMore, primary: false, onPressed: _more),
          ],
        ),
      ),
    );
  }

  Future<void> _editTemplate(String channelId, DescTemplateStore store, DescTemplate tpl) async {
    final fixed = TextEditingController(text: tpl.fixed);
    final links = TextEditingController(text: tpl.links.join('\n'));
    final tags = TextEditingController(text: tpl.hashtags.map((h) => '#$h').join(' '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text(S.tplTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(S.tplHelp, style: TextStyle(color: context.tokens.textSoft)),
              const SizedBox(height: AppTokens.gapS),
              Align(
                alignment: Alignment.centerLeft,
                child: tpl.isEmpty
                    ? const StatusBadge(Status.check, S.tplNone)
                    : const StatusBadge(Status.done, S.tplOn, key: Key('tpl-preview')),
              ),
              const SizedBox(height: AppTokens.gapM),
              TextField(
                key: const Key('tpl-fixed'),
                controller: fixed,
                maxLines: 4,
                decoration: const InputDecoration(labelText: S.tplFixed),
              ),
              const SizedBox(height: AppTokens.gapM),
              TextField(
                key: const Key('tpl-links'),
                controller: links,
                maxLines: 3,
                decoration: const InputDecoration(labelText: S.tplLinks),
              ),
              const SizedBox(height: AppTokens.gapM),
              TextField(
                key: const Key('tpl-tags'),
                controller: tags,
                decoration: const InputDecoration(labelText: S.tplTags),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text(S.cancel)),
          FilledButton(key: const Key('tpl-save'), onPressed: () => Navigator.pop(d, true), child: const Text(S.save)),
        ],
      ),
    );
    if (ok != true) return;
    store.save(
      channelId,
      DescTemplate(
        fixed: fixed.text.trim(),
        links: links.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        hashtags: DescTemplate.cleanTags([tags.text]),
      ),
    );
    if (mounted) {
      celebrate(context, S.tplSaved);
      setState(() {});
    }
  }

  Widget _videoTile(YtVideo v, int i) {
    final t = context.tokens;
    final hidden = v.privacy != 'public';
    return Appear(
      index: i,
      child: StripeCard(
        status: hidden ? Status.check : null,
        onTap: () => _showVideo(v),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
              child: SizedBox(
                width: 112,
                height: 63,
                child: v.thumbnailUrl.isEmpty
                    ? ColoredBox(
                        color: t.tonal,
                        child: Icon(Icons.smart_display, color: t.onTonal, size: AppTokens.iconM),
                      )
                    : Image.network(
                        v.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: t.tonal,
                          child: Icon(Icons.smart_display, color: t.onTonal, size: AppTokens.iconM),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: AppTokens.gapM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v.title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: AppTokens.fontBody),
                  ),
                  Text(S.videoLine(v.viewCount, v.privacy, v.tags.length), style: TextStyle(color: t.textSoft)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _styleView(StyleCard s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${S.styleMood}: ${s.mood}'),
      Text('${S.styleTone}: ${s.tone}'),
      Text('${S.styleTopics}: ${s.topics.join(', ')}'),
      Text('${S.styleTitlePattern}: ${s.titlePattern}'),
      Text('${S.styleAudience}: ${s.audience}'),
      if (s.notes.isNotEmpty) Text('${S.styleNotes}: ${s.notes}'),
    ],
  );

  Future<void> _analyze(ChannelRow c) async {
    if (!await confirmAiCost(context, u, calls: 1, input: 4000, output: 800)) return;
    if (!mounted) return;
    try {
      final card = await runWithProgress(context, S.styleAnalyze, (cancel, p) async {
        if (u.youtube.videoTotal(c.channelId) == 0) {
          await u.youtube.syncChannel(c.channelId, cancel: cancel, progress: p);
        }
        return u.brain.analyzeStyle(c.title, u.youtube.videos(c.channelId, limit: 50));
      });
      if (card == null) return;
      saveStyle(u, c.channelId, card);
      if (mounted) {
        toast(context, S.styleSaved);
        setState(() {});
      }
    } catch (e) {
      if (mounted) await showFailure(context, e, onRetry: () => _analyze(c));
    }
  }

  Future<void> _editStyle(ChannelRow c, StyleCard s) async {
    final r = await editStyleDialog(context, s);
    if (r == null) return;
    saveStyle(u, c.channelId, r);
    if (mounted) setState(() {});
  }

  Future<void> _disconnect(ChannelRow c) async {
    if (!await confirmDanger(context, S.channelDisconnectConfirm(c.title), yes: S.channelDisconnect)) return;
    await u.youtube.disconnectChannel(c.channelId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _showVideo(YtVideo v) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(v.title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.views(v.viewCount)),
            const SizedBox(height: AppTokens.gapS),
            const Text(S.chan5, style: TextStyle(fontWeight: FontWeight.w800)),
            Text(v.description.isEmpty ? S.chan6 : v.description),
            const SizedBox(height: AppTokens.gapS),
            const Text(S.chan7, style: TextStyle(fontWeight: FontWeight.w800)),
            Text(v.tags.isEmpty ? S.chan6 : v.tags.join(', ')),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text(S.close))],
    ),
  );
}

void saveStyle(UserContext u, String channelId, StyleCard card) =>
    u.db.execute('UPDATE channels SET style_json = ? WHERE channel_id = ?', [card.encode(), channelId]);

/// 스타일 카드 직접 고치기 (채널·블로그 공통).
Future<StyleCard?> editStyleDialog(BuildContext context, StyleCard s) {
  final mood = TextEditingController(text: s.mood);
  final tone = TextEditingController(text: s.tone);
  final topics = TextEditingController(text: s.topics.join(', '));
  final pattern = TextEditingController(text: s.titlePattern);
  final audience = TextEditingController(text: s.audience);
  final notes = TextEditingController(text: s.notes);
  Widget f(String l, TextEditingController c, {int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      maxLines: lines,
      decoration: InputDecoration(labelText: l),
    ),
  );
  return showDialog<StyleCard>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text(S.channelStyle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            f(S.styleMood, mood),
            f(S.styleTone, tone),
            f(S.chan8(S.styleTopics), topics),
            f(S.styleTitlePattern, pattern),
            f(S.styleAudience, audience),
            f(S.styleNotes, notes, lines: 3),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text(S.cancel)),
        FilledButton(
          onPressed: () => Navigator.pop(
            c,
            StyleCard(
              mood: mood.text,
              tone: tone.text,
              topics: topics.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
              titlePattern: pattern.text,
              audience: audience.text,
              notes: notes.text,
              editedByUser: true,
            ),
          ),
          child: const Text(S.save),
        ),
      ],
    ),
  );
}
