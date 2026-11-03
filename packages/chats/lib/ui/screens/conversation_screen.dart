import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../../core/app_log.dart';
import '../../models/models.dart';
import '../../services/app_controller.dart';
import '../../services/export_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../voice/voice_command.dart';
import '../widgets/common.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/dialogs.dart';
import '../widgets/file_actions.dart';
import '../widgets/page.dart';
import '../widgets/voice_input.dart';
import 'export_guide_screen.dart';
import 'search_screen.dart';

/// 대화 한 개 전체 보기. 긴 대화는 나눠서 보여줍니다.
class ConversationScreen extends StatefulWidget {
  final int id;
  final List<String> highlight;
  final int focusMessage;

  /// 넓은 화면에서 목록 옆 칸에 넣을 때(뒤로·홈 버튼 없이)
  final bool embedded;
  final VoidCallback? onClosed;
  const ConversationScreen({
    super.key,
    required this.id,
    this.highlight = const [],
    this.focusMessage = 0,
    this.embedded = false,
    this.onClosed,
  });
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  static const pageSize = 30;
  List<Message>? messages;
  List<Note> notes = [];
  List<ConversationSummary> related = [];
  int start = 0;
  int end = 0;
  bool failed = false;

  AppController get c => context.read<AppController>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = c.session!;
    try {
      final msgs = await s.store.messages(widget.id);
      final ns = await s.store.notes(widget.id);
      start = (widget.focusMessage - 3).clamp(0, msgs.isEmpty ? 0 : msgs.length - 1);
      end = (start + pageSize).clamp(0, msgs.length);
      final topicIds = s.topics.topicsOf(widget.id).map((t) => t.id).toList();
      final rel = await s.search.related(widget.id, topicIds: topicIds);
      if (!mounted) return;
      setState(() {
        messages = msgs;
        notes = ns;
        related = rel;
      });
    } catch (e, st) {
      AppLog.error('대화 열기 실패', e, st);
      if (mounted) setState(() => failed = true);
    }
  }

  Future<void> _reloadNotes() async {
    final ns = await c.session!.store.notes(widget.id);
    if (mounted) setState(() => notes = ns);
  }

  Future<void> _addNote({String? text, bool byVoice = false}) async {
    final t = text ?? await askText(context, title: '메모 남기기', message: '떠오른 생각을 적어 두세요. 이 대화에 붙어요.', hint: '메모', confirmLabel: '저장');
    if (t == null || t.trim().isEmpty) return;
    await c.session!.store.addNote(widget.id, t.trim(), byVoice: byVoice);
    await _reloadNotes();
    if (mounted) showNotice(context, '메모를 남겼어요.');
  }

  /// 말로 남기는 메모: 말한 그대로 이 대화에 붙습니다.
  Future<void> _voiceNote() async {
    showNotice(context, '듣고 있어요. 떠오른 생각을 말씀하세요.', kind: StatusKind.progress);
    await c.voice.listen(
      onResult: (text, done) {
        if (done && text.trim().isNotEmpty && mounted) _addNote(text: text.trim(), byVoice: true);
      },
      onError: (msg) {
        if (mounted) showNotice(context, msg, kind: StatusKind.check);
      },
    );
  }

  Future<void> _changeTopic({String? name}) async {
    final s = c.session!;
    String? target = name;
    if (target == null) {
      final topics = s.topics.all();
      final picked = await pickOne<String>(
        context,
        title: '어느 주제로 옮길까요?',
        options: [for (final t in topics) (t.name, t.name), ('__new__', '+ 새 주제 만들기')],
      );
      if (picked == null || !mounted) return;
      target = picked == '__new__' ? await askText(context, title: '새 주제 이름', hint: '예: 앱 만들기', confirmLabel: '만들기') : picked;
    }
    if (target == null || target.trim().isEmpty) return;
    final before = s.topics.topicsOf(widget.id);
    final id = s.topics.byName(target)?.id ?? s.topics.create(target);
    await s.classifier.userMove(widget.id, id);
    c.touch();
    if (!mounted) return;
    showNotice(
      context,
      '"$target" 주제로 옮겼어요. 다음 정리 때도 기억할게요.',
      onUndo: () {
        for (final t in before) {
          s.topics.setOrigin(widget.id, t.id, 'user');
        }
        if (!before.any((t) => t.id == id)) s.topics.setOrigin(widget.id, id, 'removed');
        c.touch();
      },
    );
  }

  Future<void> _removeTopic(Topic t) async {
    final s = c.session!;
    s.topics.setOrigin(widget.id, t.id, 'removed');
    c.touch();
    showNotice(
      context,
      '"${t.name}" 주제에서 뺐어요.',
      onUndo: () {
        s.topics.setOrigin(widget.id, t.id, 'user');
        c.touch();
      },
    );
  }

  Future<void> _addTag() async {
    final t = await askText(context, title: '태그 붙이기', hint: '예: 중요, 다시 보기', confirmLabel: '붙이기');
    if (t == null || t.trim().isEmpty) return;
    c.session!.store.addTag(widget.id, t.trim().replaceAll('#', ''));
    c.touch();
  }

  Future<void> _export(ConversationSummary conv, ExportFormat fmt) async {
    if (!mounted) return;
    final msgs = messages ?? const [];
    final name = '${ExportService.safeFileName(conv.title)}.${fmt.ext}';
    try {
      final Uint8List bytes;
      String mime;
      switch (fmt) {
        case ExportFormat.markdown:
          bytes = Uint8List.fromList(utf8.encode(ExportService.markdown(conv, msgs, notes: notes)));
          mime = 'text/markdown';
        case ExportFormat.text:
          bytes = Uint8List.fromList(utf8.encode(ExportService.plainText(conv, msgs, notes: notes)));
          mime = 'text/plain';
        case ExportFormat.pdf:
          bytes = await ExportService.pdf(
            conv,
            msgs,
            regularFont: await rootBundle.load('assets/fonts/NanumGothic-Regular.ttf'),
            boldFont: await rootBundle.load('assets/fonts/NanumGothic-Bold.ttf'),
            notes: notes,
          );
          mime = 'application/pdf';
      }
      if (mounted) await saveBytes(context, name, bytes, mime: mime);
    } catch (e, st) {
      AppLog.error('내보내기 실패', e, st);
      if (mounted) showNotice(context, '문서를 만들지 못했어요.', kind: StatusKind.problem);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmTwice(
      context,
      title: '이 대화를 앱에서 지울까요?',
      message: '앱 안의 기록만 지워요. 받아 둔 내보내기 파일은 그대로 남아서, 다시 넣으면 돌아와요.',
      confirmLabel: '지울게요',
    );
    if (!ok || !mounted) return;
    c.session!.store.deleteFromApp(widget.id);
    c.touch();
    if (widget.embedded) {
      widget.onClosed?.call();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _command(String text) async {
    final cmd = VoiceCommandParser.parse(text);
    final s = c.session!;
    switch (cmd) {
      case MoveToTopicCommand(:final topic):
        await _changeTopic(name: topic);
      case AddNoteCommand(text: final t):
        await _addNote(text: t, byVoice: true);
      case ReadAloudCommand():
        await _readAll();
      case StopReadingCommand():
        await c.voice.stopSpeaking();
      case StarCommand():
        final conv = s.store.get(widget.id);
        if (conv != null) {
          s.store.setStarred(widget.id, !conv.starred);
          c.touch();
        }
      case DeleteConversationCommand():
        await _delete();
      case MergeTopicsCommand(:final from, :final into):
        final a = s.topics.byName(from);
        final b = s.topics.byName(into);
        if (a == null || b == null) {
          showNotice(context, '"${a == null ? from : into}" 주제를 찾지 못했어요.', kind: StatusKind.check);
          return;
        }
        if (await confirmTwice(
          context,
          title: '주제를 합칠까요?',
          message: '"${a.name}"의 대화를 모두 "${b.name}"(으)로 옮기고 "${a.name}"은 없어져요.',
          confirmLabel: '합칠게요',
        )) {
          s.topics.merge(a.id, b.id);
          c.touch();
        }
      case ClassifyRecentCommand(:final todayOnly):
        await c.classify(todayOnly ? c.todayImportedIds() : c.allIds(), useAi: false);
      case GoHomeCommand():
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      case SearchCommand(text: final t):
        if (mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => SearchScreen(initialQuery: t)));
    }
  }

  Future<void> _readAll() async {
    final conv = c.session!.store.get(widget.id);
    final msgs = messages ?? const [];
    final buf = StringBuffer('${conv?.title ?? ''}. ');
    if (conv?.summary != null) buf.write('요약: ${conv!.summary}. ');
    for (final m in msgs.skip(start).take(6)) {
      buf.write('${m.role == Role.user ? '내 질문' : '답변'}: ${m.text}. ');
      if (buf.length > 3000) break;
    }
    await readAloud(context, c, buf.toString());
  }

  @override
  Widget build(BuildContext context) {
    final ctl = context.watch<AppController>();
    final s = ctl.session!;
    final conv = s.store.get(widget.id);
    final p = AppTheme.of(context).palette;
    final tt = Theme.of(context).textTheme;
    if (conv == null) {
      return const AppPage(
        title: '대화',
        body: EmptyState(mood: MascotMood.warning, title: '대화를 찾을 수 없어요', message: '지워졌을 수 있어요.'),
      );
    }
    final topics = s.topics.topicsOf(widget.id);
    final tags = s.store.tagsOf(widget.id);
    final msgs = messages;
    final starButton = [
      IconButton(
        tooltip: conv.starred ? '별표 빼기' : '별표 달기',
        iconSize: 34,
        onPressed: () {
          s.store.setStarred(conv.id, !conv.starred);
          ctl.touch();
        },
        icon: Opacity(opacity: conv.starred ? 1 : 0.35, child: Image.asset(AppIcons3d.star, width: 34, height: 34)),
      ),
    ];
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SourceBadge(conv.source),
            Text(dateTimeText.format(conv.createdAt), style: tt.bodySmall),
            Text('메시지 ${conv.messageCount}개', style: tt.bodySmall),
          ],
        ),
        if (conv.summary != null) ...[
          const SizedBox(height: AppSize.gapS),
          Container(
            padding: const EdgeInsets.all(AppSize.gapM),
            decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(AppSize.radius)),
            child: Text('요약: ${conv.summary}', style: tt.bodyLarge),
          ),
        ],
        const SizedBox(height: AppSize.gapM),
        // 주제·태그
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('주제', style: tt.titleMedium),
            for (final t in topics)
              InputChip(label: Text(t.name), onDeleted: () => _removeTopic(t), deleteButtonTooltipMessage: '이 주제에서 빼기'),
            ActionChip(avatar: const Icon(Icons.drive_file_move_rounded), label: const Text('주제 바꾸기'), onPressed: _changeTopic),
          ],
        ),
        const SizedBox(height: AppSize.gapS),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('태그', style: tt.titleMedium),
            for (final t in tags)
              InputChip(
                label: Text('#$t'),
                onDeleted: () {
                  s.store.removeTag(conv.id, t);
                  ctl.touch();
                },
                deleteButtonTooltipMessage: '태그 빼기',
              ),
            ActionChip(avatar: const Icon(Icons.sell_rounded), label: const Text('태그 붙이기'), onPressed: _addTag),
          ],
        ),
        const SizedBox(height: AppSize.gapM),
        Wrap(
          spacing: AppSize.gapS,
          runSpacing: AppSize.gapS,
          children: [
            BigButton(label: '읽어주기', image: AppIcons3d.speaker, expand: false, onPressed: _readAll),
            BigButton(
              label: '그만 읽기',
              icon: Icons.stop_rounded,
              expand: false,
              kind: ButtonKind.quiet,
              onPressed: () => ctl.voice.stopSpeaking(),
            ),
            BigButton(label: '메모 남기기', image: AppIcons3d.memo, expand: false, kind: ButtonKind.accent, onPressed: _addNote),
            if (ctl.voice.canListen)
              BigButton(label: '말로 메모', image: AppIcons3d.mic, expand: false, kind: ButtonKind.accent, onPressed: _voiceNote),
            if (conv.link != null)
              BigButton(
                label: '원본으로 가기',
                icon: Icons.open_in_new_rounded,
                expand: false,
                kind: ButtonKind.primary,
                onPressed: () => openLink(context, conv.link!),
              ),
          ],
        ),
        const SizedBox(height: AppSize.gapM),
        Text('이 대화 내보내기', style: tt.titleMedium),
        const SizedBox(height: AppSize.gapS),
        Wrap(
          spacing: AppSize.gapS,
          runSpacing: AppSize.gapS,
          children: [
            BigButton(
              label: '마크다운',
              icon: Icons.description_rounded,
              expand: false,
              kind: ButtonKind.info,
              onPressed: () => _export(conv, ExportFormat.markdown),
            ),
            BigButton(
              label: 'PDF',
              icon: Icons.picture_as_pdf_rounded,
              expand: false,
              kind: ButtonKind.info,
              onPressed: () => _export(conv, ExportFormat.pdf),
            ),
            BigButton(
              label: '텍스트',
              icon: Icons.text_snippet_rounded,
              expand: false,
              kind: ButtonKind.info,
              onPressed: () => _export(conv, ExportFormat.text),
            ),
          ],
        ),
        if (conv.link == null) ...[
          const SizedBox(height: AppSize.gapS),
          const StatusBadge(kind: StatusKind.check, text: '제미나이 기록은 원래 대화로 가는 링크가 없어서 날짜와 제목만 보여드려요.'),
        ],
        const SizedBox(height: AppSize.gapL),
        const TipBubble(id: 'conversation-voice', text: '말로 명령할 수 있어요: "앱 만들기 주제로 옮겨", "메모 다음 주에 다시 보기", "읽어 줘"'),
        VoiceTextField(hint: '말이나 글로 명령하기', submitLabel: '실행', onSubmit: _command),
        const SizedBox(height: AppSize.gapL),
        if (notes.isNotEmpty) ...[
          SectionCard(
            title: '내 메모',
            image: AppIcons3d.memo,
            children: [
              for (final n in notes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(n.byVoice ? Icons.mic_rounded : Icons.edit_note_rounded, color: p.textMuted),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${n.text}\n${dateTimeText.format(n.createdAt)}', style: tt.bodyLarge)),
                      IconButton(
                        tooltip: '메모 지우기',
                        icon: Icon(Icons.delete_rounded, color: p.danger),
                        onPressed: () async {
                          if (await confirmOnce(context, title: '메모를 지울까요?', message: n.text, confirmLabel: '지울게요', danger: true)) {
                            s.store.deleteNote(n.id);
                            await _reloadNotes();
                          }
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSize.gapL),
        ],
        Text('대화 내용', style: tt.titleLarge),
        const SizedBox(height: AppSize.gapS),
        if (failed)
          const EmptyState(mood: MascotMood.warning, title: '내용을 열지 못했어요', message: '설정 > 문제 신고로 알려 주세요.')
        else if (msgs == null)
          const Center(
            child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
          )
        else if (msgs.isEmpty)
          const EmptyState(mood: MascotMood.warning, title: '내용이 비어 있어요', message: '내보내기 파일에 이 대화의 내용이 없었어요.')
        else ...[
          if (start > 0)
            BigButton(
              label: '앞부분 더 보기 ($start개)',
              icon: Icons.expand_less_rounded,
              kind: ButtonKind.quiet,
              onPressed: () => setState(() => start = (start - pageSize).clamp(0, start)),
            ),
          const SizedBox(height: AppSize.gapS),
          for (var i = start; i < end; i++) _Bubble(m: msgs[i], source: conv.source, highlight: widget.highlight),
          if (end < msgs.length)
            BigButton(
              label: '더 보기 (${msgs.length - end}개 남음)',
              icon: Icons.expand_more_rounded,
              kind: ButtonKind.primary,
              onPressed: () => setState(() => end = (end + pageSize).clamp(0, msgs.length)),
            ),
        ],
        if (related.isNotEmpty) ...[
          const SizedBox(height: AppSize.gapXl),
          SectionCard(
            title: '이 주제와 관련된 지난 대화',
            image: AppIcons3d.books,
            children: [
              for (final r in related) ...[
                ConversationTile(
                  c: r,
                  onOpen: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConversationScreen(id: r.id))),
                ),
                const SizedBox(height: AppSize.gapS),
              ],
            ],
          ),
        ],
        const SizedBox(height: AppSize.gapXl),
        BigButton(label: '이 대화를 앱에서 지우기', icon: Icons.delete_forever_rounded, kind: ButtonKind.danger, onPressed: _delete),
      ],
    );
    if (!widget.embedded) return AppPage(title: conv.title, actions: starButton, body: body);
    // 넓은 화면의 오른쪽 칸
    return Material(
      color: p.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSize.pagePadding, AppSize.gapM, AppSize.gapS, 0),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(conv.title, style: tt.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ),
                ...starButton,
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              key: PageStorageKey<String>('conv-${widget.id}'),
              padding: const EdgeInsets.fromLTRB(AppSize.pagePadding, AppSize.gapS, AppSize.pagePadding, AppSize.gapXxl),
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Message m;
  final AiSource source;
  final List<String> highlight;
  const _Bubble({required this.m, required this.source, required this.highlight});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context).palette;
    final tt = Theme.of(context).textTheme;
    final mine = m.role == Role.user;
    final text = m.text.length > 20000 ? '${m.text.substring(0, 20000)}\n…(너무 길어서 일부만 보여드려요. 내보내기로 전체를 볼 수 있어요)' : m.text;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSize.gapM),
        constraints: const BoxConstraints(maxWidth: 640),
        padding: const EdgeInsets.all(AppSize.gapM),
        decoration: BoxDecoration(
          color: mine ? Color.lerp(p.surface, p.primary, 0.12) : p.surface,
          borderRadius: BorderRadius.circular(AppSize.radius),
          border: Border.all(color: mine ? p.primary : p.border, width: p.borderWidth),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mine ? '나' : source.label, style: tt.labelMedium!.copyWith(color: mine ? p.primaryText : p.text)),
            const SizedBox(height: 4),
            SelectionArea(
              child: HighlightText(text, words: highlight, style: tt.bodyLarge),
            ),
            for (final a in m.attachments)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.attach_file_rounded, size: 20, color: p.textMuted),
                    const SizedBox(width: 4),
                    Flexible(child: Text('첨부: $a (내용은 내보내기 파일에 없어요)', style: tt.bodySmall)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
