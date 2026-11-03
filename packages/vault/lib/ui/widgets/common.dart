import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/app_controller.dart';
import '../../core/log/app_logger.dart';
import '../theme/tokens.dart';

/// 화면 어디서나 앱 상태를 꺼내 쓰기 위한 창구.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

extension AppX on BuildContext {
  AppController get app => AppScope.of(this);
  AppController get appRead => AppScope.read(this);

  /// 짧은 안내. 화면이 사라졌으면 앱 맨 위에 띄우고, 그것도 없으면 조용히 넘어간다.
  void toast(String message) {
    final ctx = dialogContext(this);
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void tapFeedback() {
    final a = appRead;
    if (a.settings.haptics) a.services.haptics.tap();
    if (a.settings.sound) SystemSound.play(SystemSoundType.click);
  }
}

/// 3D 이모지 그림(Fluent Emoji 3D, MIT). 이름은 assets/emoji3d 파일 이름.
class Emoji3D extends StatelessWidget {
  const Emoji3D(this.name, {super.key, this.size = AppTokens.tileEmoji});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image.asset(
      'assets/emoji3d/$name.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
    ),
  );
}

enum MascotMood { hello, locked, unlocked, warning, celebrate }

/// 앱 마스코트 "든든이" (assets/mascot/*.svg — 파일만 바꾸면 그림이 바뀜).
class Mascot extends StatelessWidget {
  const Mascot(this.mood, {super.key, this.size = 120});
  final MascotMood mood;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.asset(
      'assets/mascot/${mood.name}.svg',
      width: size,
      height: size,
    ),
  );
}

/// 누르면 쑥 들어가고 놓으면 튀어오르는 입체 효과.
class Press3D extends StatefulWidget {
  const Press3D({
    super.key,
    required this.child,
    required this.onTap,
    this.color,
    this.radius = AppTokens.radiusButton,
    this.raised = true,
    this.border,
    this.gradient,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;
  final bool raised;
  final BoxBorder? border;
  final Gradient? gradient;
  final String? semanticLabel;

  @override
  State<Press3D> createState() => _Press3DState();
}

class _Press3DState extends State<Press3D> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = widget.onTap != null;
    final d = context.motion(AppTokens.pressDuration);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: enabled
            ? () {
                context.tapFeedback();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: d,
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: d,
            transform: Matrix4.translationValues(0, _down ? 4 : 0, 0),
            decoration: BoxDecoration(
              color: widget.gradient == null
                  ? (widget.color ?? p.surface)
                  : null,
              gradient: widget.gradient,
              borderRadius: BorderRadius.circular(widget.radius),
              border:
                  widget.border ??
                  (p.name == 'contrast'
                      ? Border.all(color: p.border, width: 2)
                      : null),
              boxShadow: widget.raised && enabled
                  ? AppTokens.raised(p, pressed: _down)
                  : null,
            ),
            child: Opacity(opacity: enabled ? 1 : 0.5, child: widget.child),
          ),
        ),
      ),
    );
  }
}

enum ButtonKind { primary, accent, safe, caution, danger, plain }

/// 색이 있는 큰 버튼(최소 높이 56). 위험 동작은 빨강 + 흰 글자.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = ButtonKind.primary,
    this.expand = true,
    this.raised = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonKind kind;
  final bool expand;
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (bg, fg) = switch (kind) {
      ButtonKind.primary => (p.primary, p.onPrimary),
      ButtonKind.accent => (p.accent, p.onAccent),
      ButtonKind.safe => (p.safeFill, p.onSafeFill),
      ButtonKind.caution => (p.cautionFill, p.onCautionFill),
      ButtonKind.danger => (p.dangerFill, p.onDangerFill),
      ButtonKind.plain => (p.surfaceAlt, p.text),
    };
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s4,
        vertical: AppTokens.s3,
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: fg, size: AppTokens.iconSize),
            const SizedBox(width: AppTokens.s2),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: fg,
                fontSize: AppTokens.fontBody,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTokens.buttonHeight),
      child: Press3D(
        onTap: onPressed,
        color: bg,
        raised: raised,
        semanticLabel: label,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTokens.buttonHeight),
          child: Center(widthFactor: expand ? null : 1, child: content),
        ),
      ),
    );
  }
}

/// 메인 화면의 큰 입체 타일(3D 아이콘 + 이름 + 한 줄 설명).
class Tile3D extends StatelessWidget {
  const Tile3D({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.badgeKind = StatusKind.caution,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;
  final StatusKind badgeKind;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Press3D(
      onTap: onTap,
      radius: AppTokens.radiusTile,
      semanticLabel: '$title. $subtitle${badge == null ? '' : '. $badge'}',
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [p.tileTop, p.tileBottom],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateZ(-0.08),
                  child: Emoji3D(emoji),
                ),
                const Spacer(),
                if (badge != null)
                  Flexible(
                    flex: 3,
                    child: StatusBadge(badgeKind, badge!, compact: true),
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.s2),
            Text(
              title,
              style: TextStyle(
                color: p.text,
                fontSize: AppTokens.fontHeading,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppTokens.s1),
            Text(
              subtitle,
              style: TextStyle(
                color: p.textMuted,
                fontSize: AppTokens.fontSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 상태 표시: 색 + 아이콘 + 글자를 항상 함께.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.kind, this.text, {super.key, this.compact = false});
  final StatusKind kind;
  final String text;
  final bool compact;

  static IconData iconFor(StatusKind k) => switch (k) {
    StatusKind.safe => Icons.check_circle_rounded,
    StatusKind.progress => Icons.autorenew_rounded,
    StatusKind.caution => Icons.warning_amber_rounded,
    StatusKind.danger => Icons.error_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = p.onStatusFill(kind);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: p.statusFill(kind),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconFor(kind), color: fg, size: compact ? 18 : 22),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: compact ? 14 : 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 카드: 바탕색을 채우고 부드러운 그림자(테두리만 있는 상자 금지).
/// 상태가 있으면 두꺼운 상태색 테두리로 표시(만료 임박 노랑, 위험 빨강 등).
class FlatCard extends StatelessWidget {
  const FlatCard({
    super.key,
    required this.child,
    this.status,
    this.onTap,
    this.padding,
    this.color,
  });
  final Widget child;
  final StatusKind? status;
  final VoidCallback? onTap;
  final EdgeInsets? padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final BorderSide side = status != null
        ? BorderSide(color: p.status(status!), width: 3)
        : (p.name == 'contrast'
              ? BorderSide(color: p.border, width: 2)
              : BorderSide.none);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        boxShadow: AppTokens.soft(p),
      ),
      child: Material(
        color: color ?? p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          side: side,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  context.tapFeedback();
                  onTap!();
                },
          child: Padding(
            padding: padding ?? const EdgeInsets.all(AppTokens.s4),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 공통 화면 틀: 큰 제목, 같은 자리의 "뒤로"·"홈" 버튼.
class AppPage extends StatefulWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.children,
    this.showHome = true,
    this.floating,
    this.bottom,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 32),
    this.restoreId,
  });

  /// 잠긴 뒤 다시 열 때 이 화면을 되살리는 이름(입력 화면은 null).
  final String? restoreId;

  final String title;
  final List<Widget> children;
  final bool showHome;
  final Widget? floating;
  final Widget? bottom;
  final EdgeInsets padding;

  @override
  State<AppPage> createState() => _AppPageState();
}

class _AppPageState extends State<AppPage> {
  ScrollController? _scroll;

  String get _key => widget.restoreId ?? 'page:${widget.title}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.appRead;
    final route = ModalRoute.of(context);
    if (route != null && widget.restoreId != null) {
      app.registerRoute(route, widget.restoreId!);
    }
    if (_scroll == null) {
      // 보던 위치에서 시작하고, 움직일 때마다 위치를 기억한다(갱신·잠금 후에도 유지).
      _scroll = ScrollController(
        initialScrollOffset: app.scrollOffsets[_key] ?? 0,
      );
      _scroll!.addListener(() {
        if (_scroll!.hasClients) app.scrollOffsets[_key] = _scroll!.offset;
      });
    }
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final title = widget.title;
    final children = widget.children;
    final showHome = widget.showHome;
    final floating = widget.floating;
    final bottom = widget.bottom;
    final padding = widget.padding;
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: canPop ? 104 : 0,
        leading: canPop
            ? Padding(
                padding: const EdgeInsets.only(left: 8),
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: p.text,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded, size: 28),
                  label: const Text(
                    '뒤로',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              )
            : null,
        actions: [
          if (showHome && canPop)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: p.text,
                  minimumSize: const Size(48, 48),
                ),
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                icon: const Icon(Icons.home_rounded, size: 28),
                label: const Text(
                  '홈',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: floating,
      bottomNavigationBar: bottom,
      body: SafeArea(
        top: false,
        child: ListView(
          key: PageStorageKey(_key),
          controller: _scroll,
          padding: padding,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            const SizedBox(height: AppTokens.s4),
            ...children,
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppTokens.s4, bottom: AppTokens.s2),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(text, style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

const gap = SizedBox(height: AppTokens.s3);
const gapBig = SizedBox(height: AppTokens.s5);

/// 빈 화면 안내(마스코트 + 문구 + 버튼).
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.emoji, this.action});
  final String message;
  final String? emoji;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppTokens.s5),
    child: Column(
      children: [
        emoji == null
            ? const Mascot(MascotMood.hello, size: 96)
            : Emoji3D(emoji!, size: 96),
        gap,
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        if (action != null) ...[gap, action!],
      ],
    ),
  );
}

/// 위험 동작 2단계 확인. 두 번 모두 "예"를 눌러야 true.
/// 실패 단계(로그·문제 신고에 남김).
enum FailStage {
  unlock('잠금 해제'),
  biometric('생체 인증'),
  backup('백업'),
  restore('복원'),
  gmail('지메일'),
  ai('AI'),
  update('업데이트'),
  breach('유출 확인'),
  file('파일');

  const FailStage(this.label);
  final String label;
}

/// 실패 창: 원인 기록(비밀 정보 없이) + "다시 시도" + "문제 신고"(금고가 열렸을 때만).
/// 다시 시도는 창이 완전히 닫힌 뒤 실행해, 사라진 화면을 쓰지 않는다.
Future<void> showErrorDialog(
  BuildContext context, {
  required FailStage stage,
  required String message,
  Future<void> Function()? onRetry,
  String? nextActionLabel,
  VoidCallback? onNextAction,
}) async {
  log.warn('실패[${stage.label}]: $message');
  final ctx = dialogContext(context);
  if (ctx == null) return;
  final app = AppScope.read(ctx);
  final canReport = app.isUnlocked;
  final choice = await showSafeDialog<String>(
    ctx,
    (c) => AlertDialog(
      title: Row(
        children: [
          const Emoji3D('warning', size: 40),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${stage.label}에 실패했어요',
              style: Theme.of(c).textTheme.titleLarge,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Text(message, style: Theme.of(c).textTheme.bodyLarge),
      ),
      actionsOverflowDirection: VerticalDirection.up,
      actionsOverflowButtonSpacing: 8,
      actions: [
        if (canReport)
          BigButton(
            label: '문제 신고',
            kind: ButtonKind.plain,
            expand: false,
            raised: false,
            onPressed: () => Navigator.pop(c, 'report'),
          ),
        BigButton(
          label: '닫기',
          kind: ButtonKind.plain,
          expand: false,
          raised: false,
          onPressed: () => Navigator.pop(c, 'close'),
        ),
        if (nextActionLabel != null)
          BigButton(
            label: nextActionLabel,
            kind: ButtonKind.accent,
            expand: false,
            raised: false,
            onPressed: () => Navigator.pop(c, 'next'),
          ),
        if (onRetry != null)
          BigButton(
            label: '다시 시도',
            expand: false,
            raised: false,
            onPressed: () => Navigator.pop(c, 'retry'),
          ),
      ],
    ),
  );
  switch (choice) {
    case 'retry':
      await onRetry?.call();
    case 'next':
      onNextAction?.call();
    case 'report':
      final rc = rootNavigatorKey?.currentContext;
      if (rc != null && rc.mounted) await reportProblem(rc);
    default:
      break;
  }
}

/// 문제 신고: 기록을 파일로 저장(비밀번호·계정·카드 정보 없음). 금고가 열렸을 때만.
Future<void> reportProblem(BuildContext context) async {
  final app = AppScope.read(context);
  if (!app.isUnlocked) return;
  final txt = await log.exportText(appVersion: app.services.appVersion);
  final where = await app.services.files.saveText('문제신고기록.txt', txt);
  // dialogContext 가 사라진 화면이면 앱 맨 위 길잡이로 바꿔 준다(mounted 확인 포함).
  // ignore: use_build_context_synchronously
  final ctx = dialogContext(context);
  if (ctx != null && ctx.mounted) {
    ctx.toast(
      where == null
          ? '저장을 취소했어요.'
          : '기록을 저장했어요. 이 파일을 보내 주세요. (비밀번호·계정 정보는 들어 있지 않아요)',
    );
  }
}

Future<bool> confirmTwice(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final first = await confirmDialog(
    context,
    title: title,
    message: message,
    confirmLabel: '계속',
    danger: true,
  );
  if (!first || !context.mounted) return false;
  return confirmDialog(
    context,
    title: '정말 할까요?',
    message: '$message\n\n이 작업은 되돌릴 수 없어요.',
    confirmLabel: confirmLabel,
    danger: true,
  );
}

/// 앱 전체의 화면 길잡이(VaultApp 이 연결). 대화상자를 띄울 화면이 이미 사라졌을 때 대신 쓴다.
GlobalKey<NavigatorState>? rootNavigatorKey;

/// 대화상자를 띄워도 안전한 context. 원래 화면이 사라졌으면 앱 맨 위 길잡이를 쓴다.
/// (1번 앱 실제 오류: 닫힌 화면의 context 로 showDialog → Null check 오류로 앱 종료)
BuildContext? dialogContext(BuildContext context) {
  if (context.mounted) return context;
  final root = rootNavigatorKey?.currentContext;
  return (root != null && root.mounted) ? root : null;
}

/// 모든 대화상자는 이 함수로 띄운다(사라진 화면 방지).
Future<T?> showSafeDialog<T>(
  BuildContext context,
  WidgetBuilder builder,
) async {
  final ctx = dialogContext(context);
  if (ctx == null) return null;
  return showDialog<T>(context: ctx, useRootNavigator: true, builder: builder);
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '예',
  String cancelLabel = '아니요',
  bool danger = false,
}) async {
  final r = await showSafeDialog<bool>(
    context,
    (c) => AlertDialog(
      title: Text(title, style: Theme.of(c).textTheme.titleLarge),
      content: SingleChildScrollView(
        child: Text(message, style: Theme.of(c).textTheme.bodyLarge),
      ),
      actionsOverflowDirection: VerticalDirection.up,
      actionsOverflowButtonSpacing: 8,
      actions: [
        BigButton(
          label: cancelLabel,
          kind: ButtonKind.plain,
          expand: false,
          raised: false,
          onPressed: () => Navigator.pop(c, false),
        ),
        BigButton(
          label: confirmLabel,
          kind: danger ? ButtonKind.danger : ButtonKind.primary,
          expand: false,
          raised: false,
          onPressed: () => Navigator.pop(c, true),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// 처음 한 번만 보이는 말풍선 안내.
class TipBubble extends StatelessWidget {
  const TipBubble({super.key, required this.id, required this.text});
  final String id;
  final String text;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (app.tipSeen(id)) return const SizedBox.shrink();
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s3),
      child: Container(
        padding: const EdgeInsets.all(AppTokens.s3),
        decoration: BoxDecoration(
          color: p.surfaceAlt,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          border: Border.all(color: p.progress, width: 2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Emoji3D('light_bulb', size: 36),
            const SizedBox(width: AppTokens.s2),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
            ),
            IconButton(
              tooltip: '안내 닫기',
              iconSize: 28,
              onPressed: () => app.markTip(id),
              icon: Icon(Icons.close_rounded, color: p.text),
            ),
          ],
        ),
      ),
    );
  }
}

/// 30초 카운트다운 원형 표시(클립보드 자동 삭제).
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.remaining,
    required this.total,
    this.size = 56,
  });
  final int remaining;
  final int total;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final frac = total == 0 ? 0.0 : remaining / total;
    return Semantics(
      label: '$remaining초 뒤 복사한 내용이 지워져요',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(end: frac),
              duration: context.motion(const Duration(milliseconds: 900)),
              builder: (_, v, _) => CircularProgressIndicator(
                value: v,
                strokeWidth: 6,
                color: remaining <= 5 ? p.danger : p.progress,
                backgroundColor: p.surfaceAlt,
              ),
            ),
            Text(
              '$remaining',
              style: TextStyle(
                color: p.text,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 클립보드 카운트다운이 진행 중일 때 화면 아래에 뜨는 막대.
class ClipboardBanner extends StatelessWidget {
  const ClipboardBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = context.palette;
    return ValueListenableBuilder<int>(
      valueListenable: app.clipboardRemaining,
      builder: (_, left, _) {
        if (left <= 0) return const SizedBox.shrink();
        return Material(
          color: p.surface,
          elevation: 8,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.s3),
              child: Row(
                children: [
                  CountdownRing(remaining: left, total: app.clipboardSeconds),
                  const SizedBox(width: AppTokens.s3),
                  Expanded(
                    child: Text(
                      '비밀번호를 복사했어요. $left초 뒤 자동으로 지워져요.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 자물쇠가 열리고(또는 닫히고) 살짝 튀는 애니메이션. 1초 이내.
class LockAnimation extends StatefulWidget {
  const LockAnimation({super.key, required this.open, this.size = 120});
  final bool open;
  final double size;

  @override
  State<LockAnimation> createState() => _LockAnimationState();
}

class _LockAnimationState extends State<LockAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppTokens.lockAnimation,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c.duration = context.motion(AppTokens.lockAnimation);
    if (context.reduceMotion) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = Curves.easeOutBack.transform(_c.value.clamp(0, 1));
        final lift = widget.open ? t : 1 - t;
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _LockPainter(
            lift: lift,
            body: p.cautionFill,
            outline: p.text,
          ),
        );
      },
    );
  }
}

class _LockPainter extends CustomPainter {
  _LockPainter({required this.lift, required this.body, required this.outline});
  final double lift;
  final Color body, outline;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final stroke = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round;
    final shackleRect = Rect.fromLTWH(
      w * 0.28,
      w * 0.12 - lift * w * 0.12,
      w * 0.44,
      w * 0.5,
    );
    canvas.save();
    canvas.translate(w * 0.72, w * 0.45);
    canvas.rotate(-lift * math.pi / 7);
    canvas.translate(-w * 0.72, -w * 0.45);
    canvas.drawArc(shackleRect, math.pi, math.pi, false, stroke);
    canvas.drawLine(
      Offset(shackleRect.left, shackleRect.center.dy),
      Offset(shackleRect.left, w * 0.5 - lift * w * 0.08),
      stroke,
    );
    canvas.drawLine(
      Offset(shackleRect.right, shackleRect.center.dy),
      Offset(shackleRect.right, w * 0.5),
      stroke,
    );
    canvas.restore();
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.16, w * 0.45, w * 0.68, w * 0.5),
      Radius.circular(w * 0.1),
    );
    canvas.drawRRect(
      bodyRect.shift(Offset(0, w * 0.04)),
      Paint()..color = outline.withValues(alpha: 0.25),
    );
    canvas.drawRRect(bodyRect, Paint()..color = body);
    canvas.drawRRect(bodyRect, stroke..strokeWidth = w * 0.05);
    canvas.drawCircle(
      Offset(w * 0.5, w * 0.68),
      w * 0.06,
      Paint()..color = outline,
    );
  }

  @override
  bool shouldRepaint(_LockPainter old) => old.lift != lift || old.body != body;
}

/// 완료 체크 애니메이션.
class CheckBurst extends StatelessWidget {
  const CheckBurst({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: context.reduceMotion ? 1 : 0.3, end: 1),
    duration: context.motion(AppTokens.checkAnimation),
    curve: Curves.elasticOut,
    builder: (_, v, child) => Transform.scale(scale: v, child: child),
    child: Emoji3D('check_mark_button', size: size),
  );
}

/// 큰 글자 입력칸(보기/숨기기 버튼 포함 가능).
class BigField extends StatefulWidget {
  const BigField({
    super.key,
    required this.controller,
    required this.label,
    this.obscure = false,
    this.keyboard,
    this.hint,
    this.onSubmitted,
    this.maxLines = 1,
    this.autofocus = false,
    this.maxLength,
    this.inputFormatters,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final TextInputType? keyboard;
  final String? hint;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final bool autofocus;
  final int? maxLength;
  final List<dynamic>? inputFormatters;

  @override
  State<BigField> createState() => _BigFieldState();
}

class _BigFieldState extends State<BigField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TextField(
      controller: widget.controller,
      obscureText: _hidden,
      enableSuggestions: !widget.obscure,
      autocorrect: !widget.obscure,
      keyboardType: widget.keyboard,
      maxLines: widget.obscure ? 1 : widget.maxLines,
      maxLength: widget.maxLength,
      autofocus: widget.autofocus,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      inputFormatters: widget.inputFormatters?.cast(),
      style: TextStyle(
        fontSize: widget.obscure ? 22 : AppTokens.fontBody,
        color: p.text,
        letterSpacing: widget.obscure ? 1.5 : 0,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        counterText: '',
        suffixIcon: widget.obscure
            ? IconButton(
                tooltip: _hidden ? '보기' : '숨기기',
                iconSize: 28,
                onPressed: () => setState(() => _hidden = !_hidden),
                icon: Icon(
                  _hidden
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
              )
            : null,
      ),
    );
  }
}

/// 한 줄 정보(이름: 값) — 긴 값은 다음 줄로 넘어간다.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.trailing});
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: p.textMuted,
                    fontSize: AppTokens.fontSmall,
                  ),
                ),
                Text(
                  value.isEmpty ? '없음' : value,
                  style: TextStyle(
                    color: p.text,
                    fontSize: AppTokens.fontBody,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 선택 버튼 묶음(큰 칩). 화면이 좁으면 다음 줄로.
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text(
              label(v),
              style: TextStyle(
                fontSize: AppTokens.fontBody,
                color: v == selected ? p.onPrimary : p.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            selected: v == selected,
            showCheckmark: v == selected,
            checkmarkColor: p.onPrimary,
            selectedColor: p.primary,
            backgroundColor: p.surfaceAlt,
            side: BorderSide(
              color: v == selected ? p.primary : p.border,
              width: 2,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: (_) => onSelected(v),
          ),
      ],
    );
  }
}

/// 켜기/끄기 줄.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => FlatCard(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: MergeSemantics(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    ),
  );
}
