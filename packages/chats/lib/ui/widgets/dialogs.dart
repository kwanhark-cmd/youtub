import 'package:flutter/material.dart';

import '../../core/app_log.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../nav.dart';
import '../screens/problem_report_screen.dart';
import 'common.dart';

// 모든 대화상자는 띄우기 전에 살아 있는 화면 정보(liveContext)를 찾습니다.
// 실패 창을 닫은 뒤 사라진 화면으로 띄우다 앱이 죽는 문제(1번 앱 실제 오류)를 막기 위함입니다.

/// 짧은 안내 띠(상태 색 + 아이콘). 되돌리기 버튼을 붙일 수 있음.
void showNotice(BuildContext? context, String text, {StatusKind kind = StatusKind.done, String? undoLabel, VoidCallback? onUndo}) {
  final ctx = liveContext(context);
  final m = (ctx == null ? null : ScaffoldMessenger.maybeOf(ctx)) ?? messengerKey.currentState;
  if (ctx == null || m == null) {
    AppLog.warn('안내를 띄울 화면이 없음', {'kind': kind.name});
    return;
  }
  final (bg, fg, icon) = AppTheme.of(ctx).palette.status(kind);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      backgroundColor: bg,
      duration: Duration(seconds: onUndo != null ? 6 : 3),
      content: Row(
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: fg, fontSize: AppSize.textBody, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      action: onUndo == null
          ? null
          : SnackBarAction(label: undoLabel ?? '되돌리기', textColor: fg, backgroundColor: Colors.black26, onPressed: onUndo),
    ),
  );
}

class _DialogShell extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget> buttons;
  final MascotMood? mood;
  const _DialogShell({required this.title, required this.body, required this.buttons, this.mood});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSize.gapXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (mood != null) Center(child: Mascot(mood!, size: 80)),
              if (mood != null) const SizedBox(height: AppSize.gapM),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSize.gapM),
              body,
              const SizedBox(height: AppSize.gapXl),
              for (var i = 0; i < buttons.length; i++) ...[if (i > 0) const SizedBox(height: AppSize.gapM), buttons[i]],
            ],
          ),
        ),
      ),
    );
  }
}

/// 살아 있는 화면에서만 대화상자를 띄움. 화면이 없으면 null.
Future<T?> _show<T>(BuildContext? context, Widget Function(BuildContext ctx) builder) async {
  final ctx = liveContext(context);
  if (ctx == null) {
    AppLog.warn('대화상자를 띄울 화면이 없음');
    return null;
  }
  return showDialog<T>(context: ctx, useRootNavigator: true, builder: builder);
}

/// 문제 신고 화면 열기(어디서든 안전하게).
void openProblemReport(BuildContext? context, {String? extra}) {
  final nav = navigatorKey.currentState ?? (liveContext(context) == null ? null : Navigator.maybeOf(liveContext(context)!));
  nav?.push(MaterialPageRoute(builder: (_) => ProblemReportScreen(extra: extra)));
}

Future<bool> confirmOnce(
  BuildContext? context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool danger = false,
}) async {
  final r = await _show<bool>(
    context,
    (ctx) => _DialogShell(
      title: title,
      mood: danger ? MascotMood.warning : null,
      body: Text(message),
      buttons: [
        BigButton(label: confirmLabel, onPressed: () => Navigator.pop(ctx, true), kind: danger ? ButtonKind.danger : ButtonKind.accent),
        BigButton(label: '아니요, 그만둘게요', onPressed: () => Navigator.pop(ctx, false), kind: ButtonKind.primary),
      ],
    ),
  );
  return r == true;
}

/// 위험한 동작(지우기·초기화·합치기)은 두 번 확인합니다.
Future<bool> confirmTwice(BuildContext? context, {required String title, required String message, required String confirmLabel}) async {
  if (!await confirmOnce(context, title: title, message: message, confirmLabel: '네, 계속할게요', danger: true)) return false;
  // liveContext가 사라진 화면을 대신하므로 안전함
  // ignore: use_build_context_synchronously
  return confirmOnce(context, title: '한 번 더 확인할게요', message: '$message\n\n정말 $confirmLabel?', confirmLabel: confirmLabel, danger: true);
}

Future<String?> askText(
  BuildContext? context, {
  required String title,
  String? message,
  String? initial,
  String hint = '',
  String confirmLabel = '확인',
  bool obscure = false,
  TextInputType? keyboard,
  Future<String?> Function()? loadFromFile,
}) {
  final ctrl = TextEditingController(text: initial);
  return _show<String>(
    context,
    (ctx) => _DialogShell(
      title: title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message != null) ...[Text(message), const SizedBox(height: AppSize.gapM)],
          TextField(
            controller: ctrl,
            autofocus: true,
            obscureText: obscure,
            keyboardType: keyboard,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          if (loadFromFile != null) ...[
            const SizedBox(height: AppSize.gapM),
            BigButton(
              label: '파일 불러오기',
              icon: Icons.file_open_rounded,
              kind: ButtonKind.info,
              onPressed: () async {
                final v = await loadFromFile();
                if (v != null) ctrl.text = v;
              },
            ),
          ],
        ],
      ),
      buttons: [
        BigButton(label: confirmLabel, onPressed: () => Navigator.pop(ctx, ctrl.text), kind: ButtonKind.accent),
        BigButton(label: '그만두기', onPressed: () => Navigator.pop(ctx), kind: ButtonKind.primary),
      ],
    ),
  );
}

/// 여러 항목 중 하나 고르기(큰 버튼 목록).
Future<T?> pickOne<T>(BuildContext? context, {required String title, String? message, required List<(T, String)> options}) {
  return _show<T>(
    context,
    (ctx) => _DialogShell(
      title: title,
      body: message == null ? const SizedBox.shrink() : Text(message),
      buttons: [
        for (final (v, label) in options) BigButton(label: label, onPressed: () => Navigator.pop(ctx, v), kind: ButtonKind.primary),
        BigButton(label: '그만두기', onPressed: () => Navigator.pop(ctx), kind: ButtonKind.quiet),
      ],
    ),
  );
}

/// 안내 창. 경고·문제일 때는 "문제 신고" 버튼이 함께 나옵니다.
Future<void> showInfo(
  BuildContext? context, {
  required String title,
  required String message,
  MascotMood mood = MascotMood.hello,
  String? problemHint,
}) {
  final isProblem = mood == MascotMood.warning;
  return _show<void>(
    context,
    (ctx) => _DialogShell(
      title: title,
      mood: mood,
      body: Text(message),
      buttons: [
        BigButton(label: '알겠어요', onPressed: () => Navigator.pop(ctx), kind: ButtonKind.accent),
        if (isProblem)
          BigButton(
            label: '문제 신고',
            icon: Icons.flag_rounded,
            kind: ButtonKind.danger,
            onPressed: () {
              Navigator.pop(ctx);
              openProblemReport(null, extra: problemHint);
            },
          ),
      ],
    ),
  );
}

/// 실패 안내 + 다시 시도. 다시 시도는 실패 창이 닫힌 뒤 살아 있는 화면에서 실행됩니다.
Future<void> showFailure(
  BuildContext? context, {
  required String title,
  required String message,
  String stage = '',
  Object? error,
  Future<void> Function()? onRetry,
  String? problemHint,
}) async {
  AppLog.error('사용자에게 실패 안내(단계: $stage) $title', error ?? title);
  final retry = await _show<bool>(
    context,
    (ctx) => _DialogShell(
      title: title,
      mood: MascotMood.warning,
      body: Text(message),
      buttons: [
        if (onRetry != null)
          BigButton(label: '다시 시도', icon: Icons.refresh_rounded, kind: ButtonKind.accent, onPressed: () => Navigator.pop(ctx, true)),
        BigButton(label: '닫기', onPressed: () => Navigator.pop(ctx, false), kind: ButtonKind.primary),
        BigButton(
          label: '문제 신고',
          icon: Icons.flag_rounded,
          kind: ButtonKind.danger,
          onPressed: () {
            Navigator.pop(ctx, false);
            openProblemReport(null, extra: problemHint ?? stage);
          },
        ),
      ],
    ),
  );
  if (retry == true && onRetry != null) {
    try {
      await onRetry();
    } catch (e, st) {
      AppLog.error('다시 시도 실패(단계: $stage)', e, st);
      showNotice(null, '다시 해 봤지만 안 됐어요. 문제 신고로 알려 주세요.', kind: StatusKind.problem);
    }
  }
}
