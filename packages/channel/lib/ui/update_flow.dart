// 이 파일의 context 는 모두 alive() 로 다시 확인한 것만 쓴다 (사라진 화면이면 앱 전체 화면).
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';

import '../app/services.dart';
import '../core/strings.dart';
import '../features/update/update_service.dart';
import 'common.dart';

/// 설정 → "업데이트 확인". 사용자가 누를 때만 확인하고, "설치"를 눌러야만 내려받는다.
Future<void> checkUpdateFlow(BuildContext callerContext, UserContext u) async {
  final env = u.env;
  ReleaseInfo? info;
  try {
    info = await runWithProgress<ReleaseInfo?>(callerContext, S.updChecking, (_, _) => env.updates.check());
  } catch (e) {
    final c = alive(callerContext);
    if (c != null) await showFailure(c, e, where: '업데이트 확인', onRetry: () => checkUpdateFlow(c, u));
    return;
  }
  final c = alive(callerContext);
  if (c == null) return;
  if (info == null) {
    toast(c, S.updLatest(UpdateService.parse(env.appVersion).join('.')));
    return;
  }
  final release = info;
  final asset = UpdateService.assetFor(release, env.osName);
  final canInstall = asset != null && env.installUpdate != null;
  final go = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      key: const Key('update-dialog'),
      title: Text(S.updNew(release.version)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Mascot(MascotMood.celebrate, size: 64),
            const SizedBox(height: AppTokens.gapS),
            const Text(
              S.updKeepsData,
              style: TextStyle(fontSize: AppTokens.fontBody, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppTokens.gapS),
            if (release.notes.trim().isNotEmpty) Text(release.notes.trim()),
            if (!canInstall) ...[const SizedBox(height: AppTokens.gapS), const Text(S.updManual)],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text(S.updLater)),
        FilledButton(
          key: const Key('update-install'),
          onPressed: () => Navigator.pop(d, true),
          child: Text(canInstall ? S.updInstall : S.updOpenPage),
        ),
      ],
    ),
  );
  if (go != true) return;
  if (!canInstall) {
    await env.launchUrl(Uri.parse(release.pageUrl));
    return;
  }
  final c2 = alive(callerContext);
  if (c2 == null) return;
  try {
    final file = await runWithProgress(c2, S.updInstalling, (cancel, progress) async {
      progress(0, S.updBackingUp);
      final dir = backupAllForUpdate(
        baseDir: env.baseDir,
        documentsDir: env.documentsDir,
        fromVersion: env.appVersion.split('+').first,
        now: env.now(),
        openDbCopy: {env.accounts.userDbPath(u.user.id): u.db.copyTo, env.accounts.usersDbPath: env.accounts.db.copyTo},
      );
      env.logger.info('업데이트 전 백업 완료');
      u.lastUpdateBackup = dir;
      progress(0.01, S.updDownloading);
      return env.updates.download(
        asset,
        '${env.documentsDir}/updates',
        onProgress: (f) => progress(f, '${S.updDownloading} ${(f * 100).round()}%'),
      );
    });
    if (file == null) return;
    await env.installUpdate!(file);
    final c3 = alive(callerContext);
    if (c3 != null) toast(c3, S.updStarted);
  } catch (e) {
    final c3 = alive(callerContext);
    if (c3 != null) await showFailure(c3, e, where: '업데이트 설치', onRetry: () => checkUpdateFlow(c3, u));
  }
}
