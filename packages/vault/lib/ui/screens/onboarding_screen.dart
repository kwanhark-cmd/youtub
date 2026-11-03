import 'package:flutter/material.dart';

import '../../core/crypto/password_tools.dart';
import '../../core/crypto/recovery_code.dart';
import '../../data/repository.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'recovery_code_view.dart';

/// 첫 실행 마법사: 글씨 크기 → 마스터 비밀번호 → 복구 코드 보관 확인 → 생체 인증 → 권한.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0;
  final name = TextEditingController(text: '나');
  final pw = TextEditingController();
  final pw2 = TextEditingController();
  String? error;
  bool busy = false;
  String? recoveryCode;
  bool wroteDown = false;
  bool? bioAvailable;
  bool notifAsked = false, micAsked = false;

  static const steps = ['글씨 크기', '마스터 비밀번호', '복구 코드', '지문·얼굴', '알림·마이크'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.appRead;
      if (!app.onboarding) app.beginOnboarding();
    });
  }

  @override
  void dispose() {
    name.dispose();
    pw.dispose();
    pw2.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final app = context.appRead;
    final n = name.text.trim();
    final s = PasswordTools.strength(pw.text);
    setState(() => error = null);
    if (n.isEmpty) return setState(() => error = '이름(별명)을 적어 주세요.');
    if (pw.text.length < 8) {
      return setState(() => error = '마스터 비밀번호는 8글자 이상으로 정해 주세요.');
    }
    if (s.score < 2) return setState(() => error = '너무 쉬운 비밀번호예요. ${s.hint}');
    if (pw.text != pw2.text) {
      return setState(() => error = '두 번 입력한 비밀번호가 달라요.');
    }
    setState(() => busy = true);
    try {
      final code = await app.createProfile(n, pw.text);
      pw.clear();
      pw2.clear();
      final bio = await app.services.biometric.isAvailable();
      setState(() {
        recoveryCode = code;
        bioAvailable = bio;
        step = 2;
      });
    } catch (e) {
      setState(() => error = '금고를 만들지 못했어요. 저장 공간을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _finish() async {
    final app = context.appRead;
    recoveryCode = null;
    app.endOnboarding();
  }

  void _cancelAddUser() {
    context.appRead.endOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = context.palette;
    final addingUser = app.profileList.isNotEmpty && step < 2;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${step + 1}/${steps.length} 단계 · ${steps[step]}',
                    style: TextStyle(
                      color: p.textMuted,
                      fontSize: AppTokens.fontSmall,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (addingUser)
                  TextButton(
                    onPressed: _cancelAddUser,
                    child: const Text('취소', style: TextStyle(fontSize: 18)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (step + 1) / steps.length,
                minHeight: 10,
                color: p.primary,
                backgroundColor: p.surfaceAlt,
              ),
            ),
            gapBig,
            AnimatedSwitcher(
              duration: context.motion(AppTokens.transition),
              child: KeyedSubtree(
                key: ValueKey(step),
                child: _stepBody(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody(BuildContext context) {
    final app = context.app;
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    switch (step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: Mascot(MascotMood.hello, size: 140)),
            gap,
            Text('반가워요!', style: t.headlineMedium, textAlign: TextAlign.center),
            gap,
            Text(
              '구독 결제, 크레딧 만료일, 여러 계정과 비밀번호를 한곳에 안전하게 모아 드려요.\n먼저 보기 편한 글씨 크기를 골라 주세요.',
              style: t.bodyLarge,
              textAlign: TextAlign.center,
            ),
            gapBig,
            ChoiceChips<int>(
              values: const [0, 1, 2],
              selected: app.settings.textScaleLevel,
              label: (i) => DeviceSettings.textScaleLabels[i],
              onSelected: (i) =>
                  app.updateSettings((s) => s.textScaleLevel = i),
            ),
            gap,
            FlatCard(
              child: Text(
                '이 글씨 크기로 보여요. 나중에 설정에서 바꿀 수 있어요.',
                style: t.bodyLarge,
              ),
            ),
            gapBig,
            BigButton(
              label: '다음',
              icon: Icons.arrow_forward_rounded,
              onPressed: () => setState(() => step = 1),
            ),
          ],
        );
      case 1:
        final s = PasswordTools.strength(pw.text);
        final kind = s.score >= 3
            ? StatusKind.safe
            : (s.score == 2 ? StatusKind.caution : StatusKind.danger);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: Emoji3D('key', size: 96)),
            gap,
            Text('마스터 비밀번호 정하기', style: t.headlineMedium),
            gap,
            Text(
              '앱을 여는 단 하나의 비밀번호예요. 이 비밀번호로 모든 정보가 암호화돼요.',
              style: t.bodyLarge,
            ),
            gap,
            FlatCard(
              status: StatusKind.danger,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Emoji3D('warning', size: 40),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '이 비밀번호를 잊으면 누구도(만든 사람도) 되찾아 드릴 수 없어요. '
                      '꼭 종이에 적어 안전한 곳에 보관해 주세요.',
                      style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            gap,
            BigField(controller: name, label: '내 이름(별명)', hint: '예: 엄마, 홍길동'),
            gap,
            BigField(
              controller: pw,
              label: '마스터 비밀번호(8글자 이상)',
              obscure: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            if (pw.text.isNotEmpty)
              Row(
                children: [
                  StatusBadge(kind, '강도: ${s.label}'),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.hint, style: t.bodyMedium)),
                ],
              ),
            gap,
            BigField(
              controller: pw2,
              label: '한 번 더 입력',
              obscure: true,
              onSubmitted: (_) => _create(),
            ),
            if (error != null) ...[gap, StatusBadge(StatusKind.danger, error!)],
            gapBig,
            busy
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : BigButton(
                    label: '금고 만들기',
                    icon: Icons.lock_rounded,
                    onPressed: _create,
                  ),
            gap,
            if (!busy)
              BigButton(
                label: '이전',
                kind: ButtonKind.plain,
                onPressed: () => setState(() => step = 0),
              ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: Emoji3D('old_key', size: 96)),
            gap,
            Text('복구 코드 보관하기', style: t.headlineMedium),
            gap,
            Text(
              '마스터 비밀번호를 잊었을 때 딱 한 번 쓸 수 있는 긴 코드예요. '
              '종이에 적거나 인쇄해서 안전한 곳에 두세요. 이 화면이 지나면 다시 볼 수 없어요.',
              style: t.bodyLarge,
            ),
            gap,
            RecoveryCodeView(code: recoveryCode ?? ''),
            gap,
            CheckboxListTile(
              value: wroteDown,
              onChanged: (v) => setState(() => wroteDown = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('복구 코드를 적어 두었습니다', style: t.titleMedium),
              contentPadding: EdgeInsets.zero,
            ),
            gap,
            BigButton(
              label: '다음',
              icon: Icons.arrow_forward_rounded,
              onPressed: wroteDown ? () => setState(() => step = 3) : null,
            ),
            if (!wroteDown)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '"적어 두었습니다"에 체크해야 다음으로 갈 수 있어요.',
                  style: t.bodyMedium,
                ),
              ),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: Emoji3D('shield', size: 96)),
            gap,
            Text('지문·얼굴로 열기', style: t.headlineMedium),
            gap,
            Text(
              bioAvailable == true
                  ? '켜 두면 매번 비밀번호를 치지 않고 지문이나 얼굴로 열 수 있어요. 안 될 때는 언제든 마스터 비밀번호로 열면 돼요.'
                  : '이 기기에서는 지문·얼굴 인증을 쓸 수 없어요. 마스터 비밀번호로 열면 돼요.',
              style: t.bodyLarge,
            ),
            gapBig,
            if (bioAvailable == true)
              BigButton(
                label: '켜기',
                kind: ButtonKind.safe,
                icon: Icons.fingerprint_rounded,
                onPressed: () async {
                  final ok = await app.services.biometric.authenticate(
                    '지문·얼굴 등록을 확인해요',
                  );
                  if (!ok) {
                    if (context.mounted) {
                      context.toast('확인하지 못했어요. 나중에 설정에서 켤 수 있어요.');
                    }
                  } else {
                    await app.setBiometric(true);
                    if (context.mounted) context.toast('지문·얼굴로 열기를 켰어요.');
                  }
                  setState(() => step = 4);
                },
              ),
            gap,
            BigButton(
              label: bioAvailable == true ? '나중에 하기' : '다음',
              kind: bioAvailable == true
                  ? ButtonKind.plain
                  : ButtonKind.primary,
              onPressed: () => setState(() => step = 4),
            ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: Emoji3D('bell', size: 96)),
            gap,
            Text('알림과 마이크', style: t.headlineMedium),
            gap,
            Text(
              '알림: 크레딧 만료 7일 전·1일 전, 구독 결제 며칠 전에 알려 드려요. 알림에는 개인 정보가 보이지 않아요.\n'
              '마이크: "이번 달 구독료 얼마야?"처럼 말로 물어볼 수 있어요.',
              style: t.bodyLarge,
            ),
            gapBig,
            BigButton(
              label: notifAsked ? '알림 허용 요청함 ✓' : '알림 허용하기',
              icon: Icons.notifications_active_rounded,
              kind: ButtonKind.accent,
              onPressed: notifAsked
                  ? null
                  : () async {
                      await app.services.notifications.requestPermission();
                      setState(() => notifAsked = true);
                    },
            ),
            gap,
            BigButton(
              label: micAsked ? '마이크 허용 요청함 ✓' : '마이크 허용하기',
              icon: Icons.mic_rounded,
              kind: ButtonKind.accent,
              onPressed: micAsked
                  ? null
                  : () async {
                      final ok = await app.services.speech.isAvailable();
                      setState(() => micAsked = true);
                      if (!ok && context.mounted) {
                        context.toast('이 기기에서는 음성 인식을 쓸 수 없어요. 글자로 물어보시면 돼요.');
                      }
                    },
            ),
            gapBig,
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: p.surfaceAlt,
                borderRadius: BorderRadius.circular(AppTokens.radiusCard),
              ),
              child: Row(
                children: [
                  const CheckBurst(size: 64),
                  const Mascot(MascotMood.celebrate, size: 64),
                  const SizedBox(width: 12),
                  Expanded(child: Text('준비가 끝났어요!', style: t.titleLarge)),
                ],
              ),
            ),
            gap,
            BigButton(
              label: '시작하기',
              icon: Icons.check_rounded,
              kind: ButtonKind.safe,
              onPressed: _finish,
            ),
          ],
        );
    }
  }
}

/// 복구 코드 형식 검사용(화면에서 입력 도움).
bool looksLikeRecoveryCode(String s) => RecoveryCode.isWellFormed(s);
