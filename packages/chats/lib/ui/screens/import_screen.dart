import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../parsers/parser_common.dart';
import '../../services/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/file_actions.dart';
import '../widgets/page.dart';
import 'export_guide_screen.dart';
import 'topics_screen.dart';

bool get isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// 내보내기 파일 넣기: 끌어다 놓기·파일 고르기·(안드로이드) 공유하기
class ImportScreen extends StatefulWidget {
  final String? initialPath;
  const ImportScreen({super.key, this.initialPath});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool dragging = false;
  String? lastName;
  Uint8List? lastBytes;

  AppController get c => context.read<AppController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      c.clearJob();
      if (widget.initialPath != null) _importPath(widget.initialPath!);
    });
  }

  Future<void> _importPath(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      await _importBytes(File(path).uri.pathSegments.last, bytes);
    } catch (_) {
      if (mounted) showNotice(context, '파일을 열 수 없어요.', kind: StatusKind.problem);
    }
  }

  Future<void> _importBytes(String name, Uint8List bytes, {AiSource? hint}) async {
    if (c.busy) {
      showNotice(context, '다른 작업이 끝나면 다시 넣어 주세요.', kind: StatusKind.check);
      return;
    }
    setState(() {
      lastName = name;
      lastBytes = bytes;
    });
    await c.importBytes(name, bytes, hint: hint);
  }

  Future<void> _pick() async {
    final f = await pickOneFile(context);
    if (f == null) return;
    await _importBytes(f.$1, f.$2);
  }

  /// "어느 AI 파일인지 골라 주세요"에서 고른 AI로 다시 읽기.
  Future<void> _retryWithHint(AiSource src) async {
    if (!mounted || lastBytes == null) return;
    await _importBytes(lastName ?? '파일', lastBytes!, hint: src);
  }

  @override
  Widget build(BuildContext context) {
    final ctl = context.watch<AppController>();
    final p = AppTheme.of(context).palette;
    final tt = Theme.of(context).textTheme;
    final job = ctl.job?.kind == JobKind.importing ? ctl.job : null;

    Widget dropZone = Container(
      padding: const EdgeInsets.all(AppSize.gapXl),
      decoration: BoxDecoration(
        color: dragging ? Color.lerp(p.surface, p.info, 0.2) : p.surface,
        borderRadius: BorderRadius.circular(AppSize.radiusCard),
        border: Border.all(color: dragging ? p.info : p.border, width: dragging ? 3 : 2),
      ),
      child: Column(
        children: [
          Image.asset(AppIcons3d.inbox, width: 96, height: 96, excludeFromSemantics: true),
          const SizedBox(height: AppSize.gapM),
          Text(
            isDesktop ? '받은 파일(.zip, .json, .html)을 여기에 끌어다 놓으세요' : '받은 파일(.zip, .json, .html)을 골라 주세요',
            style: tt.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSize.gapS),
          Text(
            Platform.isAndroid ? '다른 앱에서 "공유하기 → AI 대화 기록 정리 비서"로 보내도 돼요.' : '압축을 풀지 않고 그대로 넣어도 돼요.',
            style: tt.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSize.gapL),
          BigButton(label: '파일 고르기', icon: Icons.folder_open_rounded, kind: ButtonKind.accent, onPressed: ctl.busy ? null : _pick),
        ],
      ),
    );
    if (isDesktop) {
      dropZone = DropTarget(
        onDragEntered: (_) => setState(() => dragging = true),
        onDragExited: (_) => setState(() => dragging = false),
        onDragDone: (d) async {
          setState(() => dragging = false);
          for (final f in d.files) {
            await _importBytes(f.name, await f.readAsBytes());
          }
        },
        child: dropZone,
      );
    }

    return AppPage(
      title: '대화 넣기',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          dropZone,
          const SizedBox(height: AppSize.gapL),
          if (job != null && job.state != JobState.running) ...[
            _ResultCard(job: job, onRetryWithHint: _retryWithHint),
            const SizedBox(height: AppSize.gapL),
          ],
          BigButton(
            label: '각 AI에서 파일 받는 법',
            image: AppIcons3d.books,
            kind: ButtonKind.primary,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExportGuideScreen())),
          ),
          const SizedBox(height: AppSize.gapM),
          BigButton(
            label: '샘플 대화로 해보기',
            image: AppIcons3d.sparkles,
            kind: ButtonKind.quiet,
            onPressed: ctl.busy ? null : () => ctl.importSamples(),
          ),
          const SizedBox(height: AppSize.gapL),
          SectionCard(
            title: '알아 두세요',
            image: AppIcons3d.lock,
            children: [
              Text(
                '• 넣은 파일은 읽기만 해요. 원본 파일은 바꾸거나 지우지 않아요.\n'
                '• 대화 내용은 이 기기 안에 암호로 잠가 저장해요.\n'
                '• 같은 파일을 다시 넣어도 겹치지 않고 새 대화만 더해져요.',
                style: tt.bodyLarge,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final Job job;
  final void Function(AiSource) onRetryWithHint;
  const _ResultCard({required this.job, required this.onRetryWithHint});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final s = job.importSummary;
    final ok = job.state == JobState.done;
    final failed = job.state == JobState.failed;
    return SectionCard(
      children: [
        Row(
          children: [
            Mascot(ok ? MascotMood.celebrate : (failed ? MascotMood.warning : MascotMood.done), size: 72),
            const SizedBox(width: AppSize.gapM),
            Expanded(child: Text(job.message ?? '', style: tt.titleMedium)),
            if (ok) const CheckPop(),
          ],
        ),
        if (s != null) ...[
          const SizedBox(height: AppSize.gapM),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusBadge(kind: StatusKind.done, text: '새 대화 ${s.added}개'),
              if (s.updated > 0) StatusBadge(kind: StatusKind.progress, text: '이어진 대화 ${s.updated}개 갱신'),
              if (s.unchanged > 0) StatusBadge(kind: StatusKind.done, text: '이미 있던 대화 ${s.unchanged}개'),
              if (s.skipped > 0) StatusBadge(kind: StatusKind.check, text: '읽지 못한 항목 ${s.skipped}개'),
            ],
          ),
          for (final n in s.notices) ...[const SizedBox(height: AppSize.gapS), StatusBadge(kind: StatusKind.check, text: n)],
          if (s.saved > 0) ...[
            const SizedBox(height: AppSize.gapM),
            BigButton(
              label: '주제별로 보기',
              image: AppIcons3d.folder,
              kind: ButtonKind.success,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TopicsScreen())),
            ),
          ],
        ],
        if (failed) ...[
          const SizedBox(height: AppSize.gapM),
          if (job.unreadable == UnreadableKind.unknown) ...[
            Text('어느 AI 파일인지 골라 주세요', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSize.gapS),
            for (final a in AiSource.values) ...[
              BigButton(
                label: '${a.label} 파일이에요',
                icon: SourceBadge.iconOf(a),
                kind: ButtonKind.primary,
                onPressed: () => onRetryWithHint(a),
              ),
              const SizedBox(height: AppSize.gapS),
            ],
          ],
          if (job.unreadable == UnreadableKind.expiredLink || job.unreadable == UnreadableKind.empty || job.emptyFile) ...[
            BigButton(
              label: '내보내기 다시 받는 법',
              image: AppIcons3d.books,
              kind: ButtonKind.accent,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExportGuideScreen())),
            ),
            const SizedBox(height: AppSize.gapS),
          ],
          BigButton(
            label: '문제 신고',
            icon: Icons.flag_rounded,
            kind: ButtonKind.danger,
            onPressed: () => openProblemReport(context, extra: '단계: ${job.stage ?? '-'} / ${job.problemHint ?? ''}'),
          ),
        ],
      ],
    );
  }
}
