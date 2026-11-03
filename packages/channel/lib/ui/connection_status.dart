import 'package:flutter/material.dart';

import '../app/services.dart';
import '../core/strings.dart';
import 'common.dart';

/// 구글 연결·인공지능 연결 상태를 따로 보여 주는 카드 (홈·설정).
/// 저장하는 즉시 다시 그려져 상태가 바로 바뀐다. 둘 다 안 되어 있으면 연습 모드 안내를 함께 보여 준다.
class ConnectionStatusCard extends StatelessWidget {
  const ConnectionStatusCard({super.key, required this.user, this.onOpenSettings});
  final UserContext user;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final g = user.googleConnected;
    final a = user.aiConnected;
    final aiOver = user.ai.hasKey && user.ai.overLimit;
    return Container(
      key: const Key('connection-status-card'),
      padding: const EdgeInsets.all(AppTokens.gapL),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        boxShadow: t.flat(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.connTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTokens.gapS),
          Wrap(
            spacing: AppTokens.gapS,
            runSpacing: AppTokens.gapS,
            children: [
              StatusBadge(
                g ? Status.done : Status.check,
                g ? S.connGoogleOn : S.connGoogleOff,
                key: const Key('status-google'),
              ),
              StatusBadge(
                a ? Status.done : (aiOver ? Status.problem : Status.check),
                a ? S.connAiOn : (aiOver ? S.connAiOver : S.connAiOff),
                key: const Key('status-ai'),
              ),
            ],
          ),
          if (!g && !a) ...[
            const SizedBox(height: AppTokens.gapS),
            Text('${S.practiceMode} — ${S.connPracticeHint}', style: TextStyle(color: t.textSoft)),
          ],
          if ((!g || !a) && onOpenSettings != null) ...[
            const SizedBox(height: AppTokens.gapS),
            BigButton(
              key: const Key('status-open-settings'),
              label: S.connHowTo,
              icon: Icons.link,
              primary: false,
              onPressed: onOpenSettings,
            ),
          ],
        ],
      ),
    );
  }
}

/// 홈 인사 아래에 들어가는 작은 연결 상태 표시 (두 배지 + 둘 다 안 되어 있으면 연습 모드 한 줄).
class ConnectionBadges extends StatelessWidget {
  const ConnectionBadges({super.key, required this.user, this.onTap});
  final UserContext user;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = user.googleConnected;
    final a = user.aiConnected;
    final aiOver = user.ai.hasKey && user.ai.overLimit;
    return Semantics(
      button: onTap != null,
      label: S.connTitle,
      child: InkWell(
        key: const Key('connection-status'),
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppTokens.gapXs,
              runSpacing: AppTokens.gapXs,
              children: [
                StatusBadge(
                  g ? Status.done : Status.check,
                  g ? S.connGoogleOn : S.connGoogleOff,
                  key: const Key('status-google'),
                ),
                StatusBadge(
                  a ? Status.done : (aiOver ? Status.problem : Status.check),
                  a ? S.connAiOn : (aiOver ? S.connAiOver : S.connAiOff),
                  key: const Key('status-ai'),
                ),
              ],
            ),
            if (!g && !a)
              Text('${S.practiceMode} — ${S.connPracticeShort}', style: TextStyle(color: context.tokens.textSoft)),
          ],
        ),
      ),
    );
  }
}
