import 'package:flutter/material.dart';

import '../../logic/services_catalog.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// 서비스 대표색(로고 대신 색 + 첫 글자. 실제 로고 그림은 쓰지 않음 — 상표 문제).
const _brandColors = <String, Color>{
  'claude': Color(0xFFC15F3C),
  'chatgpt': Color(0xFF0E8A6C),
  'gemini': Color(0xFF3367D6),
  'perplexity': Color(0xFF1F6F78),
  'higgsfield': Color(0xFF1F2937),
  'runway': Color(0xFF111111),
  'kling': Color(0xFF6D28D9),
  'midjourney': Color(0xFF1F1F1F),
  'figma': Color(0xFFD9381E),
  'canva': Color(0xFF00838F),
  'netflix': Color(0xFFB20710),
  'youtube': Color(0xFFCC0000),
  'disney': Color(0xFF113CCF),
  'tving': Color(0xFFD10F35),
  'coupangplay': Color(0xFF1D4ED8),
  'facebook': Color(0xFF1565C0),
  'instagram': Color(0xFFC13584),
  'x': Color(0xFF111111),
  'threads': Color(0xFF111111),
  'kakaotalk': Color(0xFFFEE500),
  'naver': Color(0xFF03A94D),
  'google': Color(0xFF3367D6),
};

const _fallbackColors = [
  Color(0xFF7C3AED),
  Color(0xFF0F766E),
  Color(0xFFB45309),
  Color(0xFF1D4ED8),
  Color(0xFFBE185D),
  Color(0xFF4D7C0F),
  Color(0xFF6B7280),
  Color(0xFF9333EA),
];

Color serviceColor(String name) {
  final k = findKnownService(name);
  final c = k == null ? null : _brandColors[k.key];
  if (c != null) return c;
  var h = 0;
  for (final r in normalizeName(name).runes) {
    h = (h * 31 + r) & 0x7fffffff;
  }
  return _fallbackColors[h % _fallbackColors.length];
}

/// 바탕색 위 글자는 흰색/검정 중 대비가 높은 쪽.
Color onColor(Color bg) =>
    contrastRatio(Colors.white, bg) >=
        contrastRatio(const Color(0xFF111111), bg)
    ? Colors.white
    : const Color(0xFF111111);

/// 서비스 아이콘(대표색 둥근 사각형 + 첫 글자).
class ServiceAvatar extends StatelessWidget {
  const ServiceAvatar(this.name, {super.key, this.size = 48});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = serviceColor(name);
    final display = findKnownService(name)?.displayName ?? name;
    final letter = display.trim().isEmpty
        ? '?'
        : display.trim().characters.first.toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        child: Text(
          letter,
          textScaler: TextScaler.noScaling, // 아이콘 안 글자는 크기 고정(넘침 방지)
          style: TextStyle(
            color: onColor(bg),
            fontSize: size * 0.48,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// 가장 중요한 숫자 하나를 크게(홈의 이번 달 구독료 등). 주요색으로 채운 카드.
class HeroNumberCard extends StatelessWidget {
  const HeroNumberCard({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    this.onTap,
  });
  final String label;
  final String value;
  final String caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: onTap != null,
      label: '$label $value. $caption',
      child: Press3D(
        onTap: onTap,
        color: p.primary,
        radius: AppTokens.radiusTile,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: p.onPrimary,
                    fontSize: AppTokens.fontHeading,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: p.onPrimary,
                      fontSize: AppTokens.fontDisplay,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  caption,
                  style: TextStyle(
                    color: p.onPrimary,
                    fontSize: AppTokens.fontBody,
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

/// 상태색으로 채운 강조 카드(오늘 할 일 등).
class StatusFillCard extends StatelessWidget {
  const StatusFillCard({
    super.key,
    required this.kind,
    required this.child,
    this.onTap,
  });
  final StatusKind kind;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.statusFill(kind),
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: p.onStatusFill(kind)),
          child: IconTheme(
            data: IconThemeData(color: p.onStatusFill(kind)),
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.s4),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 금고 건강 점수 원형.
class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.score, this.size = 120});
  final int score;
  final double size;

  static StatusKind kindFor(int score) => score >= 80
      ? StatusKind.safe
      : (score >= 50 ? StatusKind.caution : StatusKind.danger);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final kind = kindFor(score);
    return Semantics(
      label: '금고 건강 점수 $score점',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: score / 100,
                strokeWidth: size * 0.1,
                color: p.status(kind),
                backgroundColor: p.surfaceAlt,
                strokeCap: StrokeCap.round,
              ),
            ),
            ExcludeSemantics(
              child: FittedBox(
                child: Padding(
                  padding: EdgeInsets.all(size * 0.18),
                  child: Text(
                    '$score',
                    style: TextStyle(
                      color: p.text,
                      fontSize: size * 0.3,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 설정 묶음 카드(제목 + 내용). 위험 묶음은 빨강 카드.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.emoji,
    required this.title,
    required this.children,
    this.danger = false,
  });
  final String emoji;
  final String title;
  final List<Widget> children;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.cardGap),
      child: FlatCard(
        status: danger ? StatusKind.danger : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Emoji3D(emoji, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: t.titleLarge?.copyWith(
                        color: danger ? p.danger : p.text,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s3),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: AppTokens.s3),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// 연결 상태(지메일 / AI / 생체 인증)를 따로따로 보여 준다. 저장 즉시 반영.
class ConnectionStatusRow extends StatefulWidget {
  const ConnectionStatusRow({super.key});

  @override
  State<ConnectionStatusRow> createState() => _ConnectionStatusRowState();
}

class _ConnectionStatusRowState extends State<ConnectionStatusRow> {
  bool? bioAvailable;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await context.appRead.services.biometric.isAvailable();
      if (mounted) setState(() => bioAvailable = ok);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.isUnlocked) return const SizedBox.shrink();
    final prefs = app.data.prefs;
    final bioOn = app.session?.hasDeviceUnlock ?? false;
    final items = connectionStates(
      prefs.gmailConnected,
      prefs.aiConnected,
      bioOn,
      bioAvailable,
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (kind, text) in items)
          StatusBadge(kind, text, compact: true),
      ],
    );
  }
}

/// (상태, 글자) 목록 — 화면과 테스트가 같은 규칙을 쓴다.
List<(StatusKind, String)> connectionStates(
  bool gmail,
  bool ai,
  bool bioOn,
  bool? bioAvailable,
) => [
  gmail ? (StatusKind.safe, '지메일: 연결됨') : (StatusKind.progress, '지메일: 연결 안 함'),
  ai ? (StatusKind.safe, 'AI: 연결됨') : (StatusKind.progress, 'AI: 연결 안 함'),
  bioOn
      ? (StatusKind.safe, '생체 인증: 켜짐')
      : (bioAvailable == false
            ? (StatusKind.progress, '생체 인증: 이 기기 불가')
            : (StatusKind.progress, '생체 인증: 꺼짐')),
];
