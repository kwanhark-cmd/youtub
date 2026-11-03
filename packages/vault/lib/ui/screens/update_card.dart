import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/log/app_logger.dart';
import '../../logic/update_check.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// 설정 맨 위 "업데이트 확인". 금고가 열린 상태에서만 보인다(설정 화면 자체가 잠금 해제 후).
/// 자동으로 내려받지 않는다: 확인 → 사용자가 누르면 자동 백업 → 내려받기 → 해시 확인 → 설치.
class UpdateCard extends StatefulWidget {
  const UpdateCard({super.key, this.client});

  /// 테스트용 가짜 서버.
  final http.Client? client;

  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> {
  bool busy = false;
  double? progress;
  String? message;
  StatusKind kind = StatusKind.progress;
  ReleaseInfo? release;

  UpdateChecker get _checker => UpdateChecker(client: widget.client);

  Future<void> _check() async {
    final app = context.appRead;
    setState(() {
      busy = true;
      message = null;
      release = null;
    });
    try {
      final r = await _checker.latest();
      if (!mounted) return;
      if (compareVersions(r.version, app.services.appVersion) > 0) {
        setState(() {
          release = r;
          kind = StatusKind.caution;
          message = '새 버전 ${r.version} 이 있어요.';
        });
      } else {
        setState(() {
          kind = StatusKind.safe;
          message = '지금 최신 버전(${app.services.appVersion})이에요.';
        });
      }
    } on UpdateException catch (e) {
      log.warn('업데이트 확인 실패: ${e.message}');
      if (mounted) {
        setState(() {
          kind = StatusKind.danger;
          message = e.message;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _install() async {
    final app = context.appRead;
    final r = release;
    if (r == null) return;
    final asset = r.assetFor(app.services.installer.os);
    if (asset == null) {
      setState(() {
        kind = StatusKind.caution;
        message = '이 기기용 설치 파일이 아직 없어요. 다음 버전을 기다려 주세요.';
      });
      return;
    }
    final ok = await confirmDialog(
      context,
      title: '새 버전 설치',
      message:
          '설치 전에 꼭 확인해 주세요:\n'
          '• 복구 코드가 종이에 적혀 있나요?\n'
          '• 설치는 덮어쓰기예요. 금고는 그대로 남고 같은 마스터 비밀번호로 열려요.\n\n'
          '지금 금고를 자동으로 백업한 뒤 내려받을게요.',
      confirmLabel: '백업하고 내려받기',
    );
    if (!ok || !mounted) return;
    setState(() {
      busy = true;
      progress = 0;
      message = '금고를 백업하는 중…';
      kind = StatusKind.progress;
    });
    try {
      await app.backupBeforeUpdate(r.version);
      if (!mounted) return;
      setState(() => message = '내려받는 중…');
      final dir = await app.services.installer.downloadDir();
      final file = await _checker.download(
        r,
        asset,
        dir,
        onProgress: (v) {
          if (mounted) setState(() => progress = v);
        },
      );
      if (!mounted) return;
      setState(() => message = '파일 확인 완료(해시 일치). 설치를 시작해요.');
      final msg = await app.services.installer.install(file);
      log.info('업데이트 설치 시작');
      if (mounted) {
        setState(() {
          kind = StatusKind.safe;
          message = msg;
        });
      }
    } on UpdateException catch (e) {
      log.warn('업데이트 실패(내려받기·해시): ${e.message}');
      if (mounted) {
        setState(() {
          kind = StatusKind.danger;
          message = e.message;
        });
      }
    } catch (e) {
      log.error('업데이트 실패', e);
      if (mounted) {
        setState(() {
          kind = StatusKind.danger;
          message = '업데이트하지 못했어요. 금고는 그대로예요.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = Theme.of(context).textTheme;
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Emoji3D('sparkles', size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('업데이트 확인', style: t.titleLarge),
                    Text(
                      '지금 버전 ${app.services.appVersion}',
                      style: t.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (message != null) ...[gap, StatusBadge(kind, message!)],
          if (progress != null) ...[
            gap,
            LinearProgressIndicator(value: progress, minHeight: 10),
          ],
          if (release != null && release!.notes.isNotEmpty) ...[
            gap,
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(AppTokens.s3),
              decoration: BoxDecoration(
                color: context.palette.surfaceAlt,
                borderRadius: BorderRadius.circular(AppTokens.radiusButton),
              ),
              child: SingleChildScrollView(
                child: Text(
                  release!.notes.split('### 파일 확인값').first.trim(),
                  style: t.bodyMedium,
                ),
              ),
            ),
          ],
          gap,
          if (busy)
            const Center(child: CircularProgressIndicator())
          else if (release != null)
            BigButton(
              label: '백업하고 내려받아 설치',
              icon: Icons.system_update_rounded,
              kind: ButtonKind.caution,
              onPressed: _install,
            )
          else
            BigButton(
              label: '새 버전 확인하기',
              icon: Icons.update_rounded,
              kind: ButtonKind.primary,
              onPressed: _check,
            ),
        ],
      ),
    );
  }
}
