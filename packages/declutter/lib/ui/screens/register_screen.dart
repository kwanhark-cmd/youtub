import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors.dart';
import '../../core/logger.dart';
import '../../data/models.dart';
import '../../services/image_service.dart';
import '../../services/media_picker.dart';
import '../../services/video_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'import_screen.dart';
import 'review_screen.dart';

/// 물건 등록: 사진·영상·글·가져오기
class RegisterScreen extends StatefulWidget {
  final bool autoStart;
  const RegisterScreen({super.key, this.autoStart = false});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final room = TextEditingController();
  final spot = TextEditingController();
  final desc = TextEditingController();
  bool busy = false;
  double progress = 0;
  String status = '';
  CancelToken? cancel;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    s.repo.getSetting(s.uid, 'lastRoom').then((v) => room.text = v ?? '');
    s.repo.getSetting(s.uid, 'lastSpot').then((v) => spot.text = v ?? '');
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final picker = context.read<MediaPicker>();
        picker.hasCamera ? _takePhoto() : _pickPhotos();
      });
    }
  }

  Future<void> _remember() async {
    final s = context.read<AppState>();
    await s.repo.setSetting(s.uid, 'lastRoom', room.text.trim());
    await s.repo.setSetting(s.uid, 'lastSpot', spot.text.trim());
  }

  Future<void> _takePhoto() async {
    final picker = context.read<MediaPicker>();
    try {
      final f = await picker.takePhoto();
      if (f != null) await _process([f]);
    } on PickException catch (e) {
      // 카메라 권한 거부·카메라 없음: 오류 대신 안내하고 사진 파일 고르기로 자동 대체
      log.error('[카메라] ${e.kind} ${e.detail}');
      showMessage(e.userMessage);
      await _pickPhotos();
    }
  }

  Future<void> _pickPhotos() async {
    final list = await context.read<MediaPicker>().pickPhotos();
    if (list.isNotEmpty) await _process(list);
  }

  Future<void> _video({required bool take}) async {
    final picker = context.read<MediaPicker>();
    String? path;
    try {
      path = take ? await picker.takeVideo() : await picker.pickVideo();
    } on PickException catch (e) {
      log.error('[카메라] 영상 ${e.kind} ${e.detail}');
      showMessage(e.userMessage.replaceAll('사진 파일', '영상 파일'));
      path = await picker.pickVideo();
    }
    if (path == null || !mounted) return;
    final videoPath = path;
    final s = context.read<AppState>();
    setState(() {
      busy = true;
      progress = 0;
      status = '영상에서 장면을 뽑고 있어요';
      cancel = CancelToken();
    });
    try {
      final frames = await s.video.extractFrames(
        videoPath,
        cancel: cancel,
        onProgress: (v) {
          if (mounted) setState(() => progress = v * 0.3);
        },
      );
      if (cancel!.cancelled) return _stop('취소했어요');
      if (frames.isEmpty) {
        _stop('');
        await showFailure(null, stage: '영상', message: '이 기기에서는 영상에서 장면을 뽑지 못했어요. 사진 여러 장을 골라 주세요.', altLabel: '사진 고르기', onAlt: _pickPhotos);
        return;
      }
      final files = <PickedFile>[for (final f in frames) PickedFile(f, await File(f).readAsBytes())];
      await _process(files, fromVideo: true, startProgress: 0.3);
    } catch (e, st) {
      _stop('');
      await showFailure(
        null,
        stage: '영상',
        message: '영상을 처리하지 못했어요. 다시 해 보거나 사진으로 등록해 주세요.',
        error: e,
        stack: st,
        onRetry: () => _video(take: false),
        altLabel: '사진으로 등록',
        onAlt: _pickPhotos,
      );
    }
  }

  void _stop(String msg) {
    if (!mounted) return;
    setState(() {
      busy = false;
      status = msg;
    });
  }

  /// 사진 → 줄여서 저장 → AI 인식 → 확인 화면
  Future<void> _process(List<PickedFile> files, {bool fromVideo = false, double startProgress = 0}) async {
    final s = context.read<AppState>();
    await _remember();
    setState(() {
      busy = true;
      progress = startProgress;
      cancel ??= CancelToken();
      status = 'AI가 물건을 찾고 있어요';
    });
    final batches = <DetectionBatch>[];
    String? notice;
    for (var i = 0; i < files.length; i++) {
      if (cancel?.cancelled ?? false) break;
      SavedPhoto photo;
      try {
        photo = await s.savePhoto(files[i].bytes, ext: files[i].ext);
      } catch (e, st) {
        log.error('[저장] 사진 저장 실패', e, st);
        batches.add(DetectionBatch(null, [], error: '사진을 읽지 못했어요. 다른 사진을 골라 주세요.'));
        continue;
      }
      try {
        final bytes = await s.images.readPhoto(photo.photoPath);
        final r = await s.ai.recognize(s.uid, s.user, bytes, width: photo.width, height: photo.height, hint: desc.text.trim());
        notice ??= r.message;
        for (final d in r.value) {
          d.practice = r.practice;
        }
        batches.add(DetectionBatch(photo, r.value));
      } on AiException catch (e) {
        log.error('[AI 인식] ${e.kind} ${e.detail ?? ''}');
        batches.add(DetectionBatch(photo, [DetectedItem(name: '', reason: '')], error: e.userMessage));
      } catch (e, st) {
        log.error('[AI 인식] 인식 중 오류', e, st);
        batches.add(DetectionBatch(photo, [DetectedItem(name: '')], error: '사진에서 물건을 알아보지 못했어요. 직접 이름을 적어주세요.'));
      }
      if (mounted) setState(() => progress = startProgress + (1 - startProgress) * (i + 1) / files.length);
    }
    final cancelled = cancel?.cancelled ?? false;
    _stop('');
    cancel = null;
    if (!mounted || batches.isEmpty) return;
    if (cancelled) toast(context, '취소했어요. 지금까지 찾은 것만 보여 드려요.');
    if (notice != null) toast(context, notice);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          batches: batches,
          room: room.text.trim(),
          spot: spot.text.trim(),
          description: desc.text.trim(),
          source: fromVideo ? 'video' : 'photo',
        ),
      ),
    );
    desc.clear();
  }

  Future<void> _manual() async {
    final name = await askText(context, title: '물건 이름', hint: '예: 커피 머신');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final s = context.read<AppState>();
    await _remember();
    final it = await s.addItem(name: name, room: room.text.trim(), spot: spot.text.trim(), description: desc.text.trim(), source: 'text');
    final sug = await s.ai.suggest(s.uid, s.user, it);
    it.aiSuggestion = sug.value.decision;
    it.aiReason = sug.value.reason;
    await s.saveItem(it);
    if (mounted) toast(context, '"${it.name}"을(를) 등록했어요');
    desc.clear();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final picker = context.read<MediaPicker>();
    return AppPage(
      title: '물건 등록',
      body: busy
          ? _busyView(p)
          : ListView(
              key: const PageStorageKey('register'),
              padding: const EdgeInsets.all(AppSizes.page),
              children: [
                const FirstTimeTip(id: 'register', text: '방 전체를 영상으로 천천히 찍으면 AI가 물건을 하나씩 골라내요. 애매한 물건은 사진으로 따로 찍으세요.'),
                Text('어디에 있는 물건인가요?', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: room,
                  decoration: const InputDecoration(labelText: '방 (예: 거실, 안방)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: spot,
                  decoration: const InputDecoration(labelText: '자리 (예: TV 옆 수납장)'),
                ),
                const SizedBox(height: AppSizes.gap),
                TextField(
                  controller: desc,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '설명 (예: 10년 된 커피 머신, 잘 작동함)'),
                ),
                const SizedBox(height: 8),
                BigButton(
                  label: '말로 설명하기',
                  emoji: 'mic',
                  color: p.progress,
                  onTap: () async {
                    final t = await listenOrType(context, title: '물건 설명', hint: '예: 10년 된 커피 머신, 잘 작동함', initial: desc.text);
                    if (t != null) desc.text = t;
                  },
                ),
                const SectionTitle('사진으로 등록'),
                if (picker.hasCamera) ...[BigButton(label: '사진 찍기', emoji: 'camera', color: p.accent, onTap: _takePhoto), const SizedBox(height: 8)],
                BigButton(label: picker.hasCamera ? '앨범에서 사진 고르기 (여러 장)' : '사진 파일 넣기 (여러 장)', emoji: 'folder', color: p.primary, onTap: _pickPhotos),
                const SectionTitle('영상으로 한 번에 등록'),
                if (picker.hasCamera) ...[
                  BigButton(label: '방 전체 영상 찍기', emoji: 'video', color: p.accent, onTap: () => _video(take: true)),
                  const SizedBox(height: 8),
                ],
                BigButton(label: '영상 파일 고르기', emoji: 'video', color: p.primary, onTap: () => _video(take: false)),
                const SectionTitle('그 밖의 방법'),
                BigButton(label: '이름만 적어서 등록', emoji: 'label', color: p.muted, onTap: _manual),
                const SizedBox(height: 8),
                BigButton(label: '제미나이 정리 글 가져오기', emoji: 'speech', color: p.muted, onTap: () => go(context, const ImportScreen())),
                if (status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(status)),
              ],
            ),
    );
  }

  Widget _busyView(AppPalette p) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSizes.gapLarge),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Mascot(MascotMood.thinking, size: 140),
          const SizedBox(height: AppSizes.gap),
          Text(status, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSizes.gap),
          BigProgress(progress, label: '진행률'),
          const SizedBox(height: 8),
          Text('${(progress * 100).round()}%', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: AppSizes.gap),
          BigButton(label: '취소', color: p.discard, onTap: () => setState(() => cancel?.cancel())),
        ],
      ),
    ),
  );
}
