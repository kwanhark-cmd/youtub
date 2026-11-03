import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/failure.dart';
import '../core/retry.dart';
import '../app/services.dart';
import '../core/strings.dart';
import 'theme.dart';
import 'widgets.dart';

export 'theme.dart';
export 'widgets.dart';

/// 크고 단순한 3D 버튼. 주요 동작은 강조색, 보조 동작은 옅은 주요색, 위험 동작은 빨강에 흰 글자.
/// 글씨가 커져도 잘리지 않게 여러 줄로 감싼다.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = true,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bg = danger ? t.danger : (primary ? t.accent : t.tonal);
    final fg = danger ? t.onDanger : (primary ? t.onAccent : t.onTonal);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      child: Press3D(
        color: bg,
        onTap: onPressed,
        semanticLabel: label,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTokens.buttonHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.gapM, horizontal: AppTokens.gapL),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: AppTokens.iconS + 2, color: fg),
                  const SizedBox(width: AppTokens.gapS + 2),
                ],
                Flexible(
                  child: ExcludeSemantics(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: TextStyle(color: fg, fontSize: AppTokens.fontButton, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 화면 위 "연습 모드" 띠 (노랑 = 확인 필요).
class PracticeBanner extends StatelessWidget {
  const PracticeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      label: S.practiceMode,
      child: Container(
        width: double.infinity,
        color: t.warning,
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.gapL, vertical: AppTokens.gapS),
        child: Row(
          children: [
            Icon(Icons.school, color: t.onStatusDark),
            const SizedBox(width: AppTokens.gapS),
            Expanded(
              child: Text(
                '${S.practiceMode} — ${S.practiceModeHint}',
                style: TextStyle(color: t.onStatusDark, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 제목이 있는 묶음 카드 (채운 카드, 테두리 없음).
/// [SettingsGroup] 안에서는 카드 없이 제목 + 내용만 (상자 안의 상자가 되지 않게).
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.icon3d,
    this.hue,
  });
  final String title;
  final Widget child;
  final IconData? icon;
  final String? icon3d;
  final Widget? trailing;

  /// 아이콘 칩 색 (영역 색)
  final Hue? hue;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final inGroup = _InGroup.of(context);
    final h = hue ?? Hue.slate;
    final head = Row(
      children: [
        if (icon3d != null) ...[
          Icon3D(icon3d!, size: inGroup ? AppTokens.iconM + 4 : AppTokens.icon3dS),
          const SizedBox(width: AppTokens.gapS + 2),
        ] else if (icon != null) ...[
          Container(
            padding: const EdgeInsets.all(AppTokens.gapS - 2),
            decoration: BoxDecoration(
              color: t.hueStrong(h),
              borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
            ),
            child: Icon(icon, color: t.onHueStrong(h)),
          ),
          const SizedBox(width: AppTokens.gapS + 2),
        ],
        Expanded(
          child: Text(
            title,
            style: inGroup ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ?trailing,
      ],
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        head,
        const SizedBox(height: AppTokens.gapM),
        child,
      ],
    );
    if (inGroup) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.gapM),
        child: body,
      );
    }
    return SoftCard(child: body);
  }
}

class _InGroup extends InheritedWidget {
  const _InGroup({required super.child});
  static bool of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<_InGroup>() != null;
  @override
  bool updateShouldNotify(_InGroup oldWidget) => false;
}

/// 설정 묶음 카드: 색 머리(큰 아이콘 + 이름) 아래에 여러 항목을 구분선으로 나눠 담는다.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.hue,
    required this.icon,
    required this.children,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final Hue hue;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = t.onTile(hue);
    return SoftCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: t.tileBg(hue),
            padding: const EdgeInsets.fromLTRB(AppTokens.gapL + 4, AppTokens.gapL, AppTokens.gapL, AppTokens.gapL),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: t.hueStrong(hue),
                    borderRadius: BorderRadius.circular(AppTokens.radius),
                    boxShadow: t.highContrast ? null : t.flat(),
                  ),
                  child: Icon(icon, color: t.onHueStrong(hue), size: AppTokens.iconM),
                ),
                const SizedBox(width: AppTokens.gapM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(fontSize: AppTokens.fontTitle - 2, fontWeight: FontWeight.w900, color: fg),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(fontSize: AppTokens.fontSmall, color: fg),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppTokens.gapL + 4, AppTokens.gapS, AppTokens.gapL + 4, AppTokens.gapL),
            child: _InGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(height: 1), children[i]],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 버튼들을 화면 폭에 맞게 줄바꿈해서 배치.
class ButtonWrap extends StatelessWidget {
  const ButtonWrap({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Wrap(spacing: AppTokens.gapM, runSpacing: AppTokens.gapM, children: children);
}

Future<bool> confirm(
  BuildContext callerContext,
  String message, {
  String yes = S.yes,
  String no = S.no,
  bool danger = false,
}) async {
  final context = alive(callerContext);
  if (context == null) return false;
  final r = await showDialog<bool>(
    context: context,
    builder: (c) {
      final t = c.tokens;
      return AlertDialog(
        icon: danger ? const Icon3D('warning', size: AppTokens.icon3dM) : null,
        content: SingleChildScrollView(
          child: Text(message, style: const TextStyle(fontSize: AppTokens.fontBody + 1)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(no)),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: t.danger, foregroundColor: t.onDanger) : null,
            onPressed: () => Navigator.pop(c, true),
            child: Text(yes),
          ),
        ],
      );
    },
  );
  return r ?? false;
}

/// 위험한 동작(삭제·초기화·전체 되돌리기)은 두 번 확인한다.
Future<bool> confirmDanger(BuildContext context, String first, {String yes = S.delete}) async {
  if (!await confirm(context, first, yes: S.next, no: S.cancel, danger: true)) return false;
  // ignore: use_build_context_synchronously — alive() 가 살아 있는 화면을 다시 찾는다
  return confirm(context, S.uiDangerSecond, yes: yes, no: S.cancel, danger: true);
}

void toast(BuildContext callerContext, String message) {
  final context = alive(callerContext);
  if (context == null) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: AppTokens.fontBody)),
        duration: const Duration(seconds: 4),
      ),
    );
}

/// 오류를 쉬운 말로 보여 주고, 다음 행동 버튼(다시 시도 / 다시 연결 / 설정 열기)과
/// "문제 신고 파일 만들기" 버튼을 준다. 창을 띄울 때마다 원인과 단계([where])를 로그에 남긴다.
/// 다음 행동은 창이 닫힌 뒤 살아 있는 화면에서 실행된다 (사라진 화면으로 창을 띄우지 않음).
Future<void> showFailure(
  BuildContext callerContext,
  Object error, {
  VoidCallback? onRetry,
  VoidCallback? onReconnect,
  VoidCallback? onSettings,
  String where = '',
}) async {
  final f = toFailure(error);
  UiHooks.logError?.call('실패 창${where.isEmpty ? '' : ' [$where]'}: ${f.kind.name} ${f.detail}');
  final context = alive(callerContext);
  if (context == null) return;
  if (f.kind == FailureKind.cancelled) {
    toast(context, S.progressCancelled);
    return;
  }
  VoidCallback? action;
  switch (f.nextAction) {
    case NextAction.retry:
      action = onRetry;
    case NextAction.reconnect:
      action = onReconnect;
    case NextAction.checkSettings:
      action = onSettings;
    case NextAction.tryTomorrow:
    case NextAction.none:
      action = null;
  }
  VoidCallback? after;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Mascot(MascotMood.warning, size: 72),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.userMessage, style: const TextStyle(fontSize: AppTokens.fontBody + 1)),
          if (UiHooks.makeReport != null) ...[
            const SizedBox(height: AppTokens.gapM),
            TextButton.icon(
              key: const Key('report-from-error'),
              icon: const Icon(Icons.bug_report),
              label: const Text(S.reportFromError),
              onPressed: () async {
                final path = await UiHooks.makeReport!();
                if (c.mounted) Navigator.pop(c);
                // ignore: use_build_context_synchronously — alive() 가 살아 있는 화면을 다시 찾는다
                if (path != null) toast(context, S.reportMade(path));
              },
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text(S.close)),
        if (action != null)
          FilledButton(
            key: const Key('failure-action'),
            onPressed: () {
              after = action;
              Navigator.pop(c);
            },
            child: Text(S.nextActionLabel(f.nextAction)),
          ),
      ],
    ),
  );
  // 창이 완전히 닫힌 뒤 실행 (그 사이 화면이 바뀌어도 각 기능이 살아 있는 화면을 찾아 씀)
  after?.call();
}

/// 긴 작업을 진행률 + 취소 버튼과 함께 실행. 화면은 멈추지 않는다.
Future<T?> runWithProgress<T>(
  BuildContext callerContext,
  String title,
  Future<T> Function(CancelToken cancel, void Function(double, String) progress) task,
) async {
  final context = alive(callerContext);
  if (context == null) return null;
  final cancel = CancelToken();
  final p = ValueNotifier<(double, String)>((0, S.working));
  BuildContext? dialogContext;
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) {
      dialogContext = c;
      return AlertDialog(
        title: Text(title),
        content: ValueListenableBuilder<(double, String)>(
          valueListenable: p,
          builder: (_, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Mascot(MascotMood.working, size: 72),
              const SizedBox(height: AppTokens.gapM),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
                child: LinearProgressIndicator(value: v.$1 <= 0 ? null : v.$1, minHeight: 14),
              ),
              const SizedBox(height: AppTokens.gapM),
              Text(v.$2, style: const TextStyle(fontSize: AppTokens.fontBody)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancel.cancel();
              p.value = (p.value.$1, S.progressCancelled);
            },
            child: const Text(S.progressCancel),
          ),
        ],
      );
    },
  );
  try {
    return await task(cancel, (f, m) => p.value = (f, m));
  } finally {
    // 진행 창 자신의 context 로 닫는다 (원래 화면이 사라져도 창이 남지 않게)
    final dc = dialogContext;
    if (dc != null && dc.mounted) {
      Navigator.of(dc).pop();
    } else if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    await dialog;
    p.dispose();
  }
}

Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  // ignore: use_build_context_synchronously — alive() 가 살아 있는 화면을 다시 찾는다
  toast(context, S.copied);
}

/// 간단한 빈 화면 안내 (시작 버튼이 필요하면 EmptyState 를 쓴다).
class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => EmptyState(message: text);
}

/// 화면 하나가 그리다 오류가 나도 앱 전체가 죽지 않게.
Widget friendlyErrorWidget(FlutterErrorDetails d) => const Material(
  child: Center(
    child: Padding(
      padding: EdgeInsets.all(AppTokens.gapXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Mascot(MascotMood.warning, size: 96),
          SizedBox(height: AppTokens.gapM),
          Text(
            S.errorScreen,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppTokens.fontBody + 1),
          ),
        ],
      ),
    ),
  ),
);

/// 여러 번 눌러도 한 번만 실행되게.
class Busy {
  bool _busy = false;
  Future<void> run(Future<void> Function() f) async {
    if (_busy) return;
    _busy = true;
    try {
      await f();
    } finally {
      _busy = false;
    }
  }
}

/// 숫자 입력 칸.
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.decimal = false,
  });
  final String label;
  final num value;
  final ValueChanged<num> onChanged;
  final bool decimal;
  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController c = TextEditingController(text: '${widget.value}');
  Timer? _t;
  @override
  void dispose() {
    _t?.cancel();
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: c,
    keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
    decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder()),
    onChanged: (v) {
      final n = widget.decimal ? double.tryParse(v) : int.tryParse(v);
      if (n != null) widget.onChanged(n);
    },
  );
}

/// AI 를 쓰는 작업 전에 예상 비용을 보여 주고 확인한다. 연습 모드(비용 0)면 묻지 않는다.
Future<bool> confirmAiCost(
  BuildContext context,
  UserContext u, {
  int calls = 1,
  int input = 3000,
  int output = 1200,
}) async {
  if (u.ai.isPracticeMode || calls <= 0) return true;
  final one = u.ai.estimateCost('x' * (input ~/ 2), 'x' * (input ~/ 2), expectedOutput: output);
  final est = one * calls;
  return confirm(
    context,
    S.aiCostConfirm(
      est.toStringAsFixed(3),
      u.ai.monthCostUsd.toStringAsFixed(2),
      u.settings.monthlyCostLimitUsd.toStringAsFixed(0),
    ),
    yes: S.next,
    no: S.cancel,
  );
}
