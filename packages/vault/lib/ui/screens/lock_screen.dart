import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/crypto/vault_crypto.dart';
import '../../core/log/app_logger.dart';
import '../../core/vault/vault.dart';
import '../../data/repository.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// 잠금 화면. 잠긴 동안에는 어떤 개인 데이터도 보여 주지 않는다(사용자 별명만).
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final pw = TextEditingController();
  ProfileInfo? selected;
  String? message;
  StatusKind messageKind = StatusKind.danger;
  bool busy = false;
  bool bio = false;
  Duration wait = Duration.zero;
  Timer? _ticker;
  bool _triedAutoBio = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _select(context.appRead.defaultProfile),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    pw.dispose();
    super.dispose();
  }

  Future<void> _select(ProfileInfo? p) async {
    if (p == null) return;
    final app = context.appRead;
    final hasBio = await app.hasBiometric(p);
    final w = await app.lockoutRemaining(p);
    if (!mounted) return;
    setState(() {
      selected = p;
      bio = hasBio;
      message = null;
    });
    _startWait(w);
    if (hasBio && !_triedAutoBio && w == Duration.zero) {
      _triedAutoBio = true;
      unawaited(_unlockBio());
    }
  }

  void _startWait(Duration w) {
    _ticker?.cancel();
    setState(() => wait = w);
    if (w <= Duration.zero) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      final next = wait - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        t.cancel();
        setState(() {
          wait = Duration.zero;
          message = null;
        });
      } else {
        setState(() => wait = next);
      }
    });
  }

  void _show(UnlockResult r) {
    switch (r) {
      case UnlockSuccess():
        pw.clear();
      case UnlockWrongSecret(:final failedAttempts, :final waitBeforeNext):
        setState(() {
          messageKind = StatusKind.danger;
          message = waitBeforeNext > Duration.zero
              ? '비밀번호가 맞지 않아요($failedAttempts번째). 안전을 위해 잠시 기다린 뒤 다시 해 주세요.'
              : '비밀번호가 맞지 않아요. 다시 입력해 주세요.';
        });
        _startWait(waitBeforeNext);
      case UnlockLockedOut(:final remaining):
        setState(() {
          messageKind = StatusKind.caution;
          message = '여러 번 틀려서 잠시 기다려야 해요.';
        });
        _startWait(remaining);
      case UnlockUnavailable(:final message):
        // 생체 인증이 안 되면 언제나 마스터 비밀번호로(안전하게 실패).
        log.info('실패[생체 인증]: $message → 마스터 비밀번호로 전환');
        setState(() {
          messageKind = StatusKind.progress;
          this.message = '$message. 마스터 비밀번호로 열어 주세요.';
        });
      case UnlockCorrupted(:final message):
        setState(() {
          messageKind = StatusKind.danger;
          this.message = message;
        });
        showErrorDialog(
          context,
          stage: FailStage.unlock,
          message: '$message\n백업 파일이 있으면 지금 복원할 수 있어요.',
          nextActionLabel: '백업 파일로 복원',
          onNextAction: _restoreFromBackup,
        );
    }
  }

  /// 금고 파일이 손상되어 열 수 없을 때: 잠금 화면에서 바로 백업으로 복원.
  Future<void> _restoreFromBackup() async {
    final app = context.appRead;
    final text = await app.services.files.openText(
      extensions: ['vaultbackup', 'json'],
    );
    if (text == null || !mounted) return;
    try {
      final info = await app.backups.inspect(text);
      if (!mounted) return;
      final c = TextEditingController();
      final pw = await showSafeDialog<String>(
        context,
        (ctx) => AlertDialog(
          title: const Text('백업의 마스터 비밀번호'),
          content: BigField(
            controller: c,
            label: '마스터 비밀번호',
            obscure: true,
            autofocus: true,
          ),
          actions: [
            BigButton(
              label: '취소',
              kind: ButtonKind.plain,
              expand: false,
              raised: false,
              onPressed: () => Navigator.pop(ctx),
            ),
            BigButton(
              label: '확인',
              expand: false,
              raised: false,
              onPressed: () => Navigator.pop(ctx, c.text),
            ),
          ],
        ),
      );
      c.dispose();
      if (pw == null || !mounted) return;
      if (!await app.backups.verifyPassword(
        info,
        pw,
        app.services.scratchDir,
      )) {
        if (mounted) {
          await showErrorDialog(
            context,
            stage: FailStage.restore,
            message: '백업의 마스터 비밀번호가 맞지 않아요.',
            onRetry: _restoreFromBackup,
          );
        }
        return;
      }
      await app.backups.restore(info, app.services.appVersion);
      await app.reloadProfiles();
      log.info('잠금 화면에서 백업 복원 완료');
      if (mounted) {
        setState(() {
          messageKind = StatusKind.safe;
          message = '복원했어요. 백업의 마스터 비밀번호로 열어 주세요.';
        });
      }
    } on BackupException catch (e) {
      if (mounted) {
        await showErrorDialog(
          context,
          stage: FailStage.restore,
          message: e.message,
          nextActionLabel: '다른 파일 고르기',
          onNextAction: _restoreFromBackup,
        );
      }
    }
  }

  Future<void> _unlock() async {
    final p = selected ?? context.appRead.defaultProfile;
    if (p == null || busy || wait > Duration.zero) return;
    if (pw.text.isEmpty) {
      setState(() => message = '마스터 비밀번호를 입력해 주세요.');
      return;
    }
    setState(() => busy = true);
    try {
      _show(await context.appRead.unlockWithPassword(p, pw.text));
    } on VaultCryptoException catch (e) {
      setState(() => message = e.reason);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _unlockBio() async {
    final p = selected ?? context.appRead.defaultProfile;
    if (p == null || busy) return;
    setState(() => busy = true);
    try {
      _show(await context.appRead.unlockWithBiometric(p));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _recovery() async {
    final p = selected ?? context.appRead.defaultProfile;
    if (p == null) return;
    final c = TextEditingController();
    final code = await showSafeDialog<String>(
      context,
      (ctx) => AlertDialog(
        title: const Text('복구 코드로 열기'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '적어 두신 25글자 복구 코드를 입력해 주세요. 띄어쓰기·하이픈(-)은 없어도 돼요.\n열고 나면 새 마스터 비밀번호를 정해야 해요.',
              ),
              gap,
              BigField(controller: c, label: '복구 코드', autofocus: true),
            ],
          ),
        ),
        actions: [
          BigButton(
            label: '취소',
            kind: ButtonKind.plain,
            expand: false,
            raised: false,
            onPressed: () => Navigator.pop(ctx),
          ),
          BigButton(
            label: '열기',
            expand: false,
            raised: false,
            onPressed: () => Navigator.pop(ctx, c.text),
          ),
        ],
      ),
    );
    c.dispose();
    if (code == null || code.trim().isEmpty || !mounted) return;
    setState(() => busy = true);
    try {
      _show(await context.appRead.unlockWithRecovery(p, code));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = Theme.of(context).textTheme;
    final waiting = wait > Duration.zero;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          children: [
            // 큰 3D 자물쇠(짧게 커지며 나타남, 0.5초 — 잠금 해제 속도와 무관)
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: context.reduceMotion ? 1 : 0.7, end: 1),
                duration: context.motion(const Duration(milliseconds: 500)),
                curve: Curves.easeOutBack,
                builder: (_, v, child) =>
                    Transform.scale(scale: v, child: child),
                child: const Emoji3D('locked', size: 132),
              ),
            ),
            gap,
            Text(
              '금고가 잠겨 있어요',
              style: t.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '정보를 보려면 본인 확인이 필요해요.',
              style: t.bodyLarge,
              textAlign: TextAlign.center,
            ),
            gapBig,
            if (app.profileList.length > 1) ...[
              Text('누구세요?', style: t.titleMedium),
              const SizedBox(height: 8),
              ChoiceChips<ProfileInfo>(
                values: app.profileList,
                selected: selected ?? app.profileList.first,
                label: (p) => p.name,
                onSelected: (p) {
                  _triedAutoBio = true;
                  _select(p);
                },
              ),
              gap,
            ] else if (selected != null) ...[
              Text(
                '${selected!.name}님의 금고',
                style: t.titleLarge,
                textAlign: TextAlign.center,
              ),
              gap,
            ],
            BigField(
              controller: pw,
              label: '마스터 비밀번호',
              obscure: true,
              onSubmitted: (_) => _unlock(),
            ),
            if (message != null || waiting) ...[
              gap,
              StatusBadge(
                waiting ? StatusKind.caution : messageKind,
                waiting
                    ? '${message ?? '잠시 기다려 주세요.'} (${wait.inSeconds}초)'
                    : message!,
              ),
            ],
            gap,
            busy
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : BigButton(
                    label: waiting ? '${wait.inSeconds}초 뒤에 다시 시도' : '열기',
                    icon: Icons.lock_open_rounded,
                    onPressed: waiting ? null : _unlock,
                  ),
            if (bio) ...[
              gap,
              BigButton(
                label: '지문·얼굴로 열기',
                icon: Icons.fingerprint_rounded,
                kind: ButtonKind.safe,
                onPressed: busy || waiting ? null : _unlockBio,
              ),
            ],
            gapBig,
            BigButton(
              label: '마스터 비밀번호를 잊었어요 (복구 코드)',
              icon: Icons.help_outline_rounded,
              kind: ButtonKind.caution,
              raised: false,
              onPressed: busy ? null : _recovery,
            ),
            gap,
            BigButton(
              label: '다른 사람 금고 새로 만들기',
              icon: Icons.person_add_alt_1_rounded,
              kind: ButtonKind.plain,
              raised: false,
              onPressed: busy ? null : () => app.beginOnboarding(),
            ),
            gap,
            Text(
              '앱 버전 ${app.services.appVersion}',
              textAlign: TextAlign.center,
              style: t.bodyMedium,
            ),
            Text(
              '글씨 크기: ${DeviceSettings.textScaleLabels[app.settings.textScaleLevel]}',
              textAlign: TextAlign.center,
              style: t.bodyMedium,
            ),
            const SizedBox(height: 8),
            BigButton(
              label: '글씨 크기 바꾸기',
              icon: Icons.format_size_rounded,
              kind: ButtonKind.plain,
              raised: false,
              onPressed: () => app.updateSettings(
                (s) => s.textScaleLevel = (s.textScaleLevel + 1) % 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
