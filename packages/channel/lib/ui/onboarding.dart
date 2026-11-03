import 'package:flutter/material.dart';

import '../app/app.dart';
import '../app/services.dart';
import '../core/strings.dart';
import 'channels_screen.dart';
import 'common.dart';

/// 첫 실행 안내: 언어·글씨 → 권한 → 계정 연결(건너뛰기 가능) → 연습 모드 안내.
class OnboardingWizard extends StatefulWidget {
  const OnboardingWizard({super.key, required this.state, required this.user});
  final AppState state;
  final UserContext user;

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  int step = 0;
  bool? mic;
  bool? notify;
  bool? storage;

  UserContext get u => widget.user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.wizardTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(AppTokens.gapXl),
              children: [
                Row(
                  children: [
                    Mascot(step == 3 ? MascotMood.celebrate : MascotMood.hello, size: 72),
                    const SizedBox(width: AppTokens.gapM),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(S.wizStep(step + 1), style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: AppTokens.gapS),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(end: (step + 1) / 4),
                              duration: context.tokens.normal,
                              builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.gapXl),
                Appear(key: ValueKey(step), child: _body(context)),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.gapL),
          child: Row(
            children: [
              if (step > 0)
                Expanded(
                  child: BigButton(label: S.back, primary: false, onPressed: () => setState(() => step--)),
                ),
              if (step > 0) const SizedBox(width: AppTokens.gapM),
              Expanded(
                child: BigButton(
                  key: const Key('wizard-next'),
                  label: step == 3 ? S.wizardFinish : S.next,
                  onPressed: _next,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _next() {
    if (step < 3) {
      setState(() => step++);
      return;
    }
    u.settings.onboardingDone = true;
    widget.state.refresh();
  }

  Widget _body(BuildContext context) {
    final t = Theme.of(context).textTheme;
    switch (step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.wizardStep1, style: t.headlineSmall),
            const SizedBox(height: AppTokens.gapL),
            Text(S.wizardLanguage, style: t.titleMedium),
            RadioGroup<String>(
              groupValue: 'ko',
              onChanged: (_) {},
              child: const Column(
                children: [
                  RadioListTile<String>(value: 'ko', title: Text(S.wizardLanguageKo)),
                  RadioListTile<String>(value: 'other', title: Text(S.wizardLanguageOther), enabled: false),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.gapL),
            Text(S.settingsFontSize, style: t.titleMedium),
            const SizedBox(height: AppTokens.gapS),
            FontScalePicker(state: widget.state),
            const SizedBox(height: AppTokens.gapL),
            const Text(S.wiz1),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.wizardStep2, style: t.headlineSmall),
            const SizedBox(height: AppTokens.gapS),
            const Text(S.wizardPermIntro),
            const SizedBox(height: AppTokens.gapM),
            _perm(Icons.mic, S.permMic, S.permMicWhy, mic, () async {
              final ok = await u.env.speech.initialize();
              setState(() => mic = ok);
            }),
            _perm(Icons.notifications, S.permNotify, S.permNotifyWhy, notify, () async {
              final ok = await u.env.notifier.requestPermission();
              setState(() => notify = ok);
            }),
            // 파일은 고를 때마다 기기가 직접 물어보므로 여기서는 안내만 한다.
            _perm(Icons.folder, S.permStorage, S.permStorageWhy, storage, () async => setState(() => storage = true)),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.wizardStep3, style: t.headlineSmall),
            const SizedBox(height: AppTokens.gapS),
            const Text(S.wizardAccountIntro),
            const SizedBox(height: AppTokens.gapL),
            BigButton(
              key: const Key('wizard-connect'),
              label: S.wizardConnectNow,
              icon: Icons.link,
              onPressed: () async {
                await connectGoogleFlow(context, u);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: AppTokens.gapM),
            Text(S.wiz2(u.youtube.channels().length)),
            const SizedBox(height: AppTokens.gapM),
            BigButton(label: S.skip, primary: false, onPressed: () => setState(() => step++)),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.wizardStep4, style: t.headlineSmall),
            const SizedBox(height: AppTokens.gapM),
            const PracticeBanner(),
            const SizedBox(height: AppTokens.gapM),
            const Text(S.wizardPracticeIntro, style: TextStyle(fontSize: AppTokens.fontBody)),
          ],
        );
    }
  }

  Widget _perm(IconData icon, String name, String why, bool? state, Future<void> Function() ask) {
    final st = state == null ? null : (state ? Status.done : Status.check);
    return StripeCard(
      status: st,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon3D(switch (icon) {
                Icons.mic => 'mic',
                Icons.notifications => 'bell',
                _ => 'folder',
              }, size: AppTokens.icon3dS),
              const SizedBox(width: AppTokens.gapS),
              Expanded(child: Text(name, style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: AppTokens.gapXs),
          Text(why),
          const SizedBox(height: AppTokens.gapS),
          if (state == null)
            BigButton(label: S.permAllow, primary: false, onPressed: ask)
          else
            StatusBadge(st!, state ? S.permAllowed : S.permDenied),
        ],
      ),
    );
  }
}

class FontScalePicker extends StatelessWidget {
  const FontScalePicker({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final v = state.textScale;
    return ChoiceWrap<double>(
      options: const [(1.0, S.settingsFontSmall), (1.3, S.settingsFontLarge), (1.6, S.settingsFontHuge)],
      value: v >= 1.6 ? 1.6 : (v >= 1.3 ? 1.3 : 1.0),
      onChanged: state.setTextScale,
    );
  }
}
