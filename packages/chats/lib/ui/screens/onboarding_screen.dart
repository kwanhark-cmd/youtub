import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_controller.dart';
import '../../services/settings.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import 'export_guide_screen.dart';

/// 첫 실행 안내: (이름) → 글씨 크기 → 권한 → 내보내기 받는 법 → 샘플로 체험
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0;
  final nameCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  bool working = false;

  bool get needsProfile => context.read<AppController>().session == null;

  List<String> get titles => [if (needsProfile) '반가워요!', '글씨 크기를 골라 주세요', '허락이 필요한 것', '대화 기록 받는 법', '이제 시작해 볼까요?'];

  Future<void> next() async {
    final c = context.read<AppController>();
    if (needsProfile && step == 0) {
      setState(() => working = true);
      final pin = pinCtrl.text.trim();
      if (pin.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(pin)) {
        setState(() => working = false);
        showNotice(context, '비밀번호는 숫자 4자리로 넣어 주세요. 비워 두면 비밀번호 없이 써요.', kind: StatusKind.check);
        return;
      }
      await c.createUser(nameCtrl.text, pin: pin.isEmpty ? null : pin);
      // 사용자 생성 뒤에는 이름 단계가 사라지므로 단계 번호를 그대로 둠
      if (mounted) setState(() => working = false);
      return;
    }
    setState(() => step++);
  }

  Future<void> finish({required bool withSamples}) async {
    final c = context.read<AppController>();
    setState(() => working = true);
    if (withSamples) await c.importSamples();
    c.updateSettings((s) => s.onboardingDone = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final tt = Theme.of(context).textTheme;
    final p = AppTheme.of(context).palette;
    final list = titles;
    final idx = step.clamp(0, list.length - 1);
    final offset = needsProfile ? 0 : 1; // 내용 단계 번호 맞추기
    final kind = idx + offset;
    Widget body = switch (kind) {
      0 => _profileStep(tt),
      1 => _fontStep(c, tt),
      2 => _permissionStep(c, tt),
      3 => _guideStep(tt),
      _ => _startStep(tt),
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSize.maxContentWidth),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      for (var i = 0; i < list.length; i++)
                        Expanded(
                          child: Container(
                            height: 10,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(color: i <= idx ? p.primary : p.surfaceAlt, borderRadius: BorderRadius.circular(5)),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${idx + 1} / ${list.length} 단계', style: tt.bodySmall),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSize.pagePadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(header: true, child: Text(list[idx], style: tt.headlineMedium)),
                        const SizedBox(height: AppSize.gapL),
                        AnimatedSwitcher(
                          duration: AppTheme.of(context).motion(context, AppMotion.normal),
                          child: KeyedSubtree(key: ValueKey(kind), child: body),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSize.pagePadding),
                  child: Row(
                    children: [
                      if (idx > 0) ...[
                        Expanded(
                          child: BigButton(
                            label: '이전',
                            icon: Icons.arrow_back_rounded,
                            kind: ButtonKind.primary,
                            onPressed: working ? null : () => setState(() => step--),
                          ),
                        ),
                        const SizedBox(width: AppSize.gapM),
                      ],
                      if (kind < 4)
                        Expanded(
                          flex: 2,
                          child: BigButton(
                            label: '다음',
                            icon: Icons.arrow_forward_rounded,
                            kind: ButtonKind.accent,
                            onPressed: working ? null : next,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileStep(TextTheme tt) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Center(child: Mascot(MascotMood.hello, size: 140)),
      const SizedBox(height: AppSize.gapL),
      Text('저는 세 AI(클로드, 챗GPT, 제미나이)와 나눈 대화를 한곳에 모아 정리해 드리는 비서예요.', style: tt.bodyLarge),
      const SizedBox(height: AppSize.gapL),
      Text('뭐라고 불러 드릴까요?', style: tt.titleMedium),
      const SizedBox(height: AppSize.gapS),
      TextField(
        controller: nameCtrl,
        decoration: const InputDecoration(hintText: '이름(비워 두면 "나")'),
      ),
      const SizedBox(height: AppSize.gapL),
      Text('비밀번호(선택)', style: tt.titleMedium),
      Text('가족과 같은 기기를 쓴다면 숫자 4자리를 넣으세요. 다른 사람 자료는 서로 보이지 않아요.', style: tt.bodySmall),
      const SizedBox(height: AppSize.gapS),
      TextField(
        controller: pinCtrl,
        keyboardType: TextInputType.number,
        obscureText: true,
        maxLength: 4,
        decoration: const InputDecoration(hintText: '비워 두어도 돼요'),
      ),
    ],
  );

  Widget _fontStep(AppController c, TextTheme tt) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('읽기 편한 크기를 누르세요. 나중에 설정에서 바꿀 수 있어요.', style: tt.bodyLarge),
      const SizedBox(height: AppSize.gapL),
      for (final f in FontSize.values) ...[
        _Choice(
          selected: c.settings.fontSize == f,
          onTap: () => c.updateSettings((s) => s.fontSize = f),
          child: Text(
            '가나다 — ${f.label}',
            style: tt.titleLarge!.copyWith(fontSize: AppSize.textTitle * f.scale / c.settings.fontSize.scale),
          ),
        ),
        const SizedBox(height: AppSize.gapM),
      ],
    ],
  );

  Widget _permissionStep(AppController c, TextTheme tt) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('허락하지 않아도 앱은 잘 동작해요.', style: tt.bodyLarge),
      const SizedBox(height: AppSize.gapL),
      SectionCard(
        title: '마이크',
        image: 'assets/icons3d/mic.png',
        children: [
          Text(
            c.voice.canListen ? '말로 검색하고 명령하려면 필요해요. 마이크 버튼을 처음 누를 때 한 번 물어봐요.' : '이 기기에서는 음성 인식을 쓸 수 없어요. 글자로 입력하면 돼요.',
            style: tt.bodyLarge,
          ),
          if (c.voice.canListen) ...[
            const SizedBox(height: AppSize.gapM),
            BigButton(
              label: '지금 마이크 허락하기',
              kind: ButtonKind.primary,
              icon: Icons.mic_rounded,
              onPressed: () async {
                await c.voice.init();
                if (!mounted) return;
                setState(() {});
                showNotice(
                  context,
                  c.voice.canListen ? '마이크를 쓸 수 있어요!' : '마이크를 쓸 수 없어요. 글자로 입력하면 돼요.',
                  kind: c.voice.canListen ? StatusKind.done : StatusKind.check,
                );
              },
            ),
          ],
        ],
      ),
      const SizedBox(height: AppSize.gapM),
      SectionCard(
        title: '파일',
        image: 'assets/icons3d/package.png',
        children: [Text('대화 기록 파일을 고를 때 그 파일만 읽어요. 원본 파일은 절대 바꾸거나 지우지 않아요.', style: tt.bodyLarge)],
      ),
      const SizedBox(height: AppSize.gapM),
      SectionCard(
        title: '알림',
        image: 'assets/icons3d/bell.png',
        children: [
          SwitchRow(
            title: '한 달에 한 번 알려 주기',
            subtitle: '앱을 열면 "오늘 할 일"에 "내보내기를 요청할 때가 됐어요"가 떠요.',
            value: c.settings.exportReminder,
            onChanged: (v) => c.updateSettings((s) => s.exportReminder = v),
          ),
        ],
      ),
    ],
  );

  Widget _guideStep(TextTheme tt) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('각 AI는 대화 기록을 "내보내기" 파일로 줘요. 그 파일을 이 앱에 넣으면 정리가 시작돼요.', style: tt.bodyLarge),
      const SizedBox(height: AppSize.gapL),
      const ExportGuideList(compact: true),
    ],
  );

  Widget _startStep(TextTheme tt) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Center(child: Mascot(MascotMood.celebrate, size: 140)),
      const SizedBox(height: AppSize.gapL),
      Text('먼저 샘플 대화로 어떻게 정리되는지 체험해 보세요. 샘플은 나중에 지울 수 있어요.', style: tt.bodyLarge),
      const SizedBox(height: AppSize.gapXl),
      BigButton(
        label: '샘플로 체험하기',
        image: 'assets/icons3d/sparkles.png',
        kind: ButtonKind.accent,
        onPressed: working ? null : () => finish(withSamples: true),
      ),
      const SizedBox(height: AppSize.gapM),
      BigButton(
        label: '바로 시작하기',
        icon: Icons.play_arrow_rounded,
        kind: ButtonKind.primary,
        onPressed: working ? null : () => finish(withSamples: false),
      ),
    ],
  );
}

class _Choice extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  const _Choice({required this.selected, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context).palette;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSize.radius),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSize.buttonHeight + 8),
          padding: const EdgeInsets.all(AppSize.gapL),
          decoration: BoxDecoration(
            color: selected ? Color.lerp(p.surface, p.primary, 0.15) : p.surface,
            borderRadius: BorderRadius.circular(AppSize.radius),
            border: Border.all(color: selected ? p.primary : p.border, width: selected ? 3 : p.borderWidth),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? p.primaryText : p.textMuted,
                size: 28,
              ),
              const SizedBox(width: AppSize.gapM),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
