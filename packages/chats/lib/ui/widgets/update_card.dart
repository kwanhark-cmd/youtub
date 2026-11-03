import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/app_info.dart';
import '../../core/cancel_token.dart';
import '../../services/app_controller.dart';
import '../../services/update_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../screens/export_guide_screen.dart';
import 'common.dart';
import 'dialogs.dart';

/// 설정 맨 위: 지금 버전 + 업데이트 확인 + 문제 신고.
class UpdateCard extends StatefulWidget {
  const UpdateCard({super.key});
  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> {
  bool checking = false;
  double? progress;
  String? status;
  CancelToken? cancel;

  AppController get c => context.read<AppController>();

  Future<void> _check() async {
    setState(() {
      checking = true;
      status = '새 버전을 확인하고 있어요…';
    });
    try {
      final info = await c.checkForUpdate();
      if (!mounted) return;
      setState(() => status = info == null ? '지금이 최신 버전이에요 (${AppInfo.version}).' : '새 버전 ${info.version}이 있어요!');
      if (info != null) await _offer(info);
    } on UpdateError catch (e) {
      if (!mounted) return;
      setState(() => status = e.kind == UpdateErrorKind.noRelease ? e.message : null);
      if (e.kind != UpdateErrorKind.noRelease) {
        await showFailure(context, title: '업데이트를 확인하지 못했어요', message: e.message, stage: '업데이트 확인', error: e, onRetry: _check);
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> _offer(UpdateInfo info) async {
    final notes = info.notes.isEmpty ? '바뀐 내용 안내가 없어요.' : info.notes;
    final ok = await confirmOnce(
      context,
      title: '새 버전 ${info.version}',
      message: '$notes\n\n"업데이트"를 누르면 먼저 내 자료를 자동으로 백업하고, 새 버전을 내려받아 설치해요. 설정과 대화는 그대로 남아요.',
      confirmLabel: '업데이트',
    );
    if (!ok || !mounted) return;
    if (info.downloadUrl == null) {
      await showInfo(context, title: '이 기기용 파일이 아직 없어요', message: const UpdateError(UpdateErrorKind.noFileForDevice).message);
      if (mounted) await openLink(context, info.pageUrl);
      return;
    }
    await _download(info);
  }

  Future<void> _download(UpdateInfo info) async {
    final token = CancelToken();
    setState(() {
      cancel = token;
      progress = 0;
      status = '내 자료를 백업하고 있어요…';
    });
    try {
      await c.backupBeforeUpdate(info.version);
      if (!mounted) return;
      setState(() => status = '새 버전을 내려받고 있어요…');
      final dir = Directory('${(await getTemporaryDirectory()).path}/ai_chat_organizer_update');
      final file = await c.updates.download(
        info,
        dir,
        cancel: token,
        onProgress: (got, total) {
          if (mounted) setState(() => progress = total == null || total == 0 ? null : got / total);
        },
      );
      if (!mounted) return;
      setState(() => status = Platform.isAndroid ? '설치 화면을 열어요. "설치"를 눌러 주세요.' : '앱을 닫고 새 버전으로 바꾼 뒤 다시 열어요…');
      await c.updates.install(file);
    } on UpdateError catch (e) {
      if (!mounted) return;
      if (token.isCancelled) {
        showNotice(context, '업데이트를 취소했어요.', kind: StatusKind.check);
      } else {
        await showFailure(
          context,
          title: '업데이트하지 못했어요',
          message: e.message,
          stage: '업데이트(${e.kind.name})',
          error: e,
          onRetry: () => _download(info),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          progress = null;
          cancel = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctl = context.watch<AppController>();
    final tt = Theme.of(context).textTheme;
    final p = AppTheme.of(context).palette;
    final badge = ctl.hasUpdateBadge;
    return SectionCard(
      title: '앱 버전',
      image: AppIcons3d.package,
      children: [
        Row(
          children: [
            Expanded(child: Text('지금 버전 ${AppInfo.version}', style: tt.titleMedium)),
            if (badge) StatusBadge(kind: StatusKind.check, text: '새 버전 ${ctl.settings.latestVersion} 있어요'),
          ],
        ),
        if (status != null) ...[const SizedBox(height: AppSize.gapS), Text(status!, style: tt.bodyLarge)],
        if (progress != null || cancel != null) ...[
          const SizedBox(height: AppSize.gapS),
          ProgressBar(value: progress, label: progress == null ? '준비 중' : '${((progress ?? 0) * 100).round()}%'),
          const SizedBox(height: AppSize.gapS),
          BigButton(label: '취소', icon: Icons.close_rounded, kind: ButtonKind.danger, onPressed: () => cancel?.cancel()),
        ],
        const SizedBox(height: AppSize.gapM),
        BigButton(
          label: checking ? '확인하는 중…' : '업데이트 확인',
          icon: Icons.system_update_rounded,
          kind: badge ? ButtonKind.accent : ButtonKind.primary,
          onPressed: checking || cancel != null ? null : _check,
        ),
        const SizedBox(height: AppSize.gapS),
        BigButton(label: '문제 신고', icon: Icons.flag_rounded, kind: ButtonKind.danger, onPressed: () => openProblemReport(context)),
        const SizedBox(height: AppSize.gapS),
        Text('새 버전을 설치해도 설정과 대화는 그대로 남아요. 자동으로 내려받지는 않아요.', style: tt.bodySmall?.copyWith(color: p.textMuted)),
      ],
    );
  }
}
