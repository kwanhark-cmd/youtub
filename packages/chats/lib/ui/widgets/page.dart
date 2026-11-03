import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../shell.dart';
import 'common.dart';

/// 모든 화면의 공통 틀: 큰 제목, 같은 자리의 "뒤로"(왼쪽)와 "홈"(오른쪽) 버튼.
class AppPage extends StatelessWidget {
  final String title;
  final Widget body;
  final bool isHome;
  final List<Widget> actions;
  final Widget? bottom;
  final bool scroll;

  const AppPage({
    super.key,
    required this.title,
    required this.body,
    this.isHome = false,
    this.actions = const [],
    this.bottom,
    this.scroll = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context).palette;
    final canPop = Navigator.of(context).canPop();
    Widget content = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: scroll ? AppSize.maxContentWidth : double.infinity), // 나눈 화면(목록+본문)은 창 전체
        child: scroll
            ? SingleChildScrollView(
                key: PageStorageKey<String>('page-$title'),
                padding: const EdgeInsets.fromLTRB(AppSize.pagePadding, AppSize.gapS, AppSize.pagePadding, AppSize.gapXxl),
                child: body,
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSize.pagePadding),
                child: body,
              ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: canPop ? 76 : 0,
        leading: canPop
            ? Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _NavButton(icon: Icons.arrow_back_rounded, label: '뒤로', onTap: () => Navigator.of(context).maybePop()),
              )
            : null,
        title: Semantics(header: true, child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis)),
        actions: [
          ...actions,
          if (!isHome)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _NavButton(icon: Icons.home_rounded, label: '홈', onTap: ShellNav.goHome),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const JobBanner(),
            Expanded(child: content),
            if (bottom != null)
              Container(
                color: p.background,
                padding: const EdgeInsets.fromLTRB(AppSize.pagePadding, AppSize.gapS, AppSize.pagePadding, AppSize.gapM),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: AppSize.maxContentWidth),
                    child: bottom!,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _NavButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context).palette;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: p.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSize.radiusSmall)),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSize.radiusSmall),
            onTap: onTap,
            child: SizedBox(
              width: 60,
              height: 52,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: p.onPrimary, size: 24),
                  Text(
                    label,
                    style: TextStyle(color: p.onPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                    textScaler: TextScaler.noScaling,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 화면 위쪽의 작업 진행 띠(가져오기·분류 중). 취소 버튼 포함.
class JobBanner extends StatelessWidget {
  const JobBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final job = c.job;
    if (job == null || job.state != JobState.running) return const SizedBox.shrink();
    final p = AppTheme.of(context).palette;
    final label = job.total > 0 ? '${job.message ?? ''} (${job.done}/${job.total})' : (job.message ?? '');
    return Container(
      width: double.infinity,
      color: Color.lerp(p.surface, p.info, 0.15),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          const Mascot(MascotMood.working, size: 44),
          const SizedBox(width: 10),
          Expanded(
            child: ProgressBar(value: job.progress, label: label),
          ),
          const SizedBox(width: 10),
          BigButton(label: '취소', onPressed: c.cancelJob, kind: ButtonKind.danger, expand: false, icon: Icons.close_rounded),
        ],
      ),
    );
  }
}
