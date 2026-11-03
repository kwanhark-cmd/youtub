import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors.dart';
import '../../core/logger.dart';
import '../../services/update_service.dart';
import '../../services/video_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'common.dart';

/// 설정 맨 위: 지금 버전 + "업데이트 확인"
class UpdateCard extends StatefulWidget {
  const UpdateCard({super.key});
  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> {
  bool checking = false;

  Future<void> _check() async {
    final s = context.read<AppState>();
    setState(() => checking = true);
    try {
      final info = await s.checkUpdateNow();
      if (!mounted) return;
      if (info == null) {
        toast(context, '지금이 최신 버전이에요 ($appVersion)');
      } else {
        await showUpdateDialog(context, info);
      }
    } catch (e, st) {
      if (mounted) setState(() => checking = false);
      await showFailure(null, stage: '업데이트', message: '업데이트를 확인하지 못했어요. 인터넷 연결을 확인해 주세요.', error: e, stack: st, onRetry: _check);
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.palette;
    return Panel(
      fill: s.hasUpdate ? p.attention.withValues(alpha: 0.35) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Emoji3D('package', size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('앱 버전 $appVersion', style: Theme.of(context).textTheme.titleMedium),
                    Text(s.hasUpdate ? '새 버전 ${s.global.latestVersion}이(가) 나왔어요' : '물건·사진·설정은 업데이트해도 그대로 남아요', style: const TextStyle(fontSize: 15)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          BigButton(
            label: checking ? '확인하는 중…' : (s.hasUpdate ? '새 버전 설치하기' : '업데이트 확인'),
            emoji: 'sparkle',
            color: s.hasUpdate ? p.sell : p.primary,
            onTap: checking ? null : (s.hasUpdate && s.update != null ? () => showUpdateDialog(context, s.update!) : _check),
          ),
        ],
      ),
    );
  }
}

/// 새 버전 안내 → 사용자가 누르면 자동 백업 후 내려받아 설치
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
  final ok = await confirmOnce(
    context,
    title: '새 버전 ${info.version}',
    message: '${info.notes.isEmpty ? '새 버전이 나왔어요.' : info.notes}\n\n설치해도 물건·사진·설정은 그대로 남아요. 설치 전에 자동으로 백업해 둘게요.',
    okLabel: '내려받아 설치',
  );
  if (!ok || !context.mounted) return;
  if (info.assetUrl == null) {
    toast(context, '이 기기용 설치 파일이 아직 없어요. 잠시 뒤 다시 확인해 주세요.');
    return;
  }
  final s = context.read<AppState>();
  final progress = ValueNotifier<double>(0);
  final cancel = CancelToken();
  final nav = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('새 버전 내려받는 중'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BigProgress(v, label: '내려받기'),
              const SizedBox(height: 8),
              Text('${(v * 100).round()}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        actions: [BigButton(label: '취소', expand: false, color: ctx.palette.discard, onTap: cancel.cancel)],
      ),
    ),
  );
  try {
    await s.backup.createSafetyBackup('업데이트설치', appVersion: appVersion);
    final file = await s.updates.download(info, onProgress: (v) => progress.value = v, cancel: cancel);
    if (nav.mounted) nav.pop();
    final quit = await s.updates.install(file);
    if (quit) {
      log.info('업데이트 설치를 위해 앱을 닫습니다');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      exit(0);
    }
  } on UserFacingException catch (e) {
    if (nav.mounted) nav.pop();
    await showFailure(null, stage: '업데이트', message: e.message);
  } catch (e, st) {
    if (nav.mounted) nav.pop();
    await showFailure(null, stage: '업데이트', message: '업데이트를 설치하지 못했어요. 다시 해 보거나 문제 신고로 기록을 보내 주세요.', error: e, stack: st);
  }
}
