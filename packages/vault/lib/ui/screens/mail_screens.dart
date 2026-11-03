import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../logic/dates.dart';
import '../../logic/gmail.dart';
import '../../logic/mail_analysis.dart';
import '../../logic/money.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'credits_screens.dart';
import 'subscriptions_screens.dart';

/// 결제·크레딧 메일로 자동 채우기.
/// 1) 메일 내용을 붙여 넣기 → 규칙으로 분석(무료) → 안 되면 AI(키가 있을 때, 비용 안내 후)
/// 2) 지메일 연결 시 최근 결제 메일 찾기
/// 메일 내용은 저장하지 않고, 사용자가 "추가"를 눌러야만 등록된다.
class MailImportScreen extends StatefulWidget {
  const MailImportScreen({super.key});

  @override
  State<MailImportScreen> createState() => _MailImportScreenState();
}

class _MailImportScreenState extends State<MailImportScreen> {
  final text = TextEditingController();
  bool busy = false;
  final results = <MailSuggestion>[];
  String? note;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  String _month(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  /// 이번 달 AI 사용 금액 확인 후 분석. 한도를 넘으면 실행하지 않는다.
  Future<MailSuggestion?> _ai(String relevant) async {
    final app = context.appRead;
    final prefs = app.data.prefs;
    final analyzer = ClaudeMailAnalyzer(
      apiKey: prefs.aiApiKey,
      model: prefs.aiModel,
      usdToKrw: prefs.usdToKrw,
    );
    final m = _month(app.now());
    final used = prefs.aiUsageMonth == m ? prefs.aiUsageWon : 0.0;
    final est = analyzer.estimateCostWon(relevant);
    if (used + est > prefs.aiMonthlyLimitWon) {
      throw const AiLimitExceeded();
    }
    final (s, cost) = await analyzer.analyze(relevant, app.now());
    await app.mutate((d) {
      if (d.prefs.aiUsageMonth != m) {
        d.prefs.aiUsageMonth = m;
        d.prefs.aiUsageWon = 0;
      }
      d.prefs.aiUsageWon += cost;
    });
    return s;
  }

  Future<void> _analyzePasted({bool forceAi = false}) async {
    final app = context.appRead;
    final raw = text.text;
    if (raw.trim().isEmpty) return setState(() => note = '메일 내용을 붙여 넣어 주세요.');
    setState(() {
      busy = true;
      note = null;
      results.clear();
    });
    try {
      MailSuggestion? s = forceAi
          ? null
          : analyzeWithRules('', '', raw, app.now());
      if (s == null && app.data.prefs.aiConnected) {
        final relevant = extractRelevant(raw);
        final analyzer = ClaudeMailAnalyzer(
          apiKey: '',
          model: app.data.prefs.aiModel,
          usdToKrw: app.data.prefs.usdToKrw,
        );
        final est = analyzer.estimateCostWon(relevant);
        if (!mounted) return;
        final ok = await confirmDialog(
          context,
          title: 'AI로 분석할까요?',
          message:
              '메일에서 필요한 부분만(카드 번호는 가린 채) AI에 보내 분석해요.\n예상 비용: 약 ${est.toStringAsFixed(1)}원',
          confirmLabel: '분석하기',
        );
        if (ok) s = await _ai(relevant);
      }
      setState(() {
        if (s != null) {
          results.add(s);
        } else {
          note = app.data.prefs.aiConnected
              ? '내용을 알아보지 못했어요. 직접 입력해 주세요.'
              : '내용을 알아보지 못했어요. 직접 입력하시거나, 설정에서 AI 연결을 하면 더 잘 알아봐요.';
        }
      });
    } on AiLimitExceeded {
      setState(() => note = '이번 달 AI 사용 한도에 닿았어요. 설정에서 한도를 바꾸거나 직접 입력해 주세요.');
    } on AiRequestFailed catch (e) {
      if (mounted) setState(() => note = '직접 입력도 할 수 있어요.');
      if (mounted) {
        await showErrorDialog(
          context,
          stage: FailStage.ai,
          message: '${e.message}\n직접 입력도 할 수 있어요.',
          onRetry: () => _analyzePasted(forceAi: forceAi),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _fromGmail() async {
    final app = context.appRead;
    final prefs = app.data.prefs;
    setState(() {
      busy = true;
      note = null;
      results.clear();
    });
    try {
      final oauth = GoogleOAuth(
        clientId: prefs.gmailClientId,
        clientSecret: prefs.gmailClientSecret,
      );
      final token = await oauth.accessToken(prefs.gmailRefreshToken);
      final msgs = await GmailClient(token).searchReceipts();
      final found = <MailSuggestion>[];
      for (final m in msgs) {
        final s = analyzeWithRules(m.subject, m.from, m.body, app.now());
        if (s != null) found.add(s);
      }
      setState(() {
        results.addAll(found);
        note = found.isEmpty
            ? '최근 60일 결제·크레딧 메일에서 찾은 것이 없어요.'
            : '메일 ${msgs.length}통 중 ${found.length}건을 찾았어요. 확인 후 추가해 주세요.';
      });
    } catch (e) {
      final msg = e is GmailException ? e.message : '지메일을 읽지 못했어요.';
      if (mounted) {
        setState(() {
          busy = false;
          note = '직접 입력이나 메일 붙여넣기는 계속 쓸 수 있어요.';
        });
        await showErrorDialog(
          context,
          stage: FailStage.gmail,
          message: '$msg\n직접 입력이나 메일 붙여넣기는 계속 쓸 수 있어요.',
          onRetry: _fromGmail,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _add(MailSuggestion s) {
    if (s.isCredit) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CreditEditScreen(
            preset: CreditItem(
              serviceName: s.serviceName,
              amountText: s.creditText,
              expiresAt: s.date ?? DateTime.now().add(const Duration(days: 30)),
            ),
          ),
        ),
      );
    } else {
      final next = s.date == null ? DateTime.now() : s.date!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SubscriptionEditScreen(
            preset: Subscription(
              serviceName: s.serviceName,
              amount: s.amount ?? 0,
              currency: s.currency,
              cycle: s.cycle,
              nextRenewal: next,
              cardLast4: s.cardLast4,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.isUnlocked) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final prefs = app.data.prefs;
    return AppPage(
      title: '메일로 채우기',
      restoreId: 'mail',
      children: [
        Text(
          '결제 영수증이나 크레딧 안내 메일 내용을 복사해 아래에 붙여 넣으세요. 메일 내용은 저장하지 않아요.',
          style: t.bodyLarge,
        ),
        gap,
        BigField(controller: text, label: '메일 내용 붙여넣기', maxLines: 8),
        gap,
        busy
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BigButton(
                    label: '분석하기',
                    icon: Icons.search_rounded,
                    onPressed: () => _analyzePasted(),
                  ),
                  if (prefs.aiConnected) ...[
                    gap,
                    BigButton(
                      label: 'AI로 분석하기',
                      icon: Icons.auto_awesome_rounded,
                      kind: ButtonKind.accent,
                      onPressed: () => _analyzePasted(forceAi: true),
                    ),
                  ],
                  gap,
                  BigButton(
                    label: prefs.gmailConnected
                        ? '지메일에서 최근 결제 메일 찾기'
                        : '지메일 연결은 설정에서 할 수 있어요',
                    icon: Icons.mark_email_unread_rounded,
                    kind: ButtonKind.plain,
                    onPressed: prefs.gmailConnected ? _fromGmail : null,
                  ),
                ],
              ),
        if (note != null) ...[
          gap,
          StatusBadge(
            results.isEmpty ? StatusKind.caution : StatusKind.progress,
            note!,
          ),
        ],
        if (results.isNotEmpty) SectionTitle('찾은 내용 ${results.length}건'),
        for (final s in results) ...[
          FlatCard(
            status: StatusKind.progress,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${s.serviceName} · ${s.isCredit ? '크레딧·체험판' : '구독 결제'}',
                  style: t.titleLarge,
                ),
                if (!s.isCredit && s.amount != null)
                  Text(
                    '금액: ${formatAmount(s.amount!, s.currency)} (${s.cycle.label})',
                    style: t.bodyLarge,
                  ),
                if (s.isCredit && s.creditText.isNotEmpty)
                  Text('양: ${s.creditText}', style: t.bodyLarge),
                Text(
                  '${s.isCredit ? '만료일' : '날짜'}: ${s.date == null ? '찾지 못함(직접 입력)' : formatKoreanDateFull(s.date!)}',
                  style: t.bodyLarge,
                ),
                if (s.cardLast4 != null)
                  Text('카드 끝 4자리: ${s.cardLast4}', style: t.bodyLarge),
                Text(
                  s.source == 'ai'
                      ? 'AI 분석 결과 — 맞는지 꼭 확인해 주세요'
                      : '자동 분석 결과 — 맞는지 꼭 확인해 주세요',
                  style: t.bodyMedium,
                ),
                const SizedBox(height: 8),
                BigButton(
                  label: '확인하고 추가',
                  icon: Icons.add_rounded,
                  kind: ButtonKind.safe,
                  raised: false,
                  onPressed: () => _add(s),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.s3),
        ],
      ],
    );
  }
}
