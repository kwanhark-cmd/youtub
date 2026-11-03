import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../logic/cleanup.dart';
import '../../logic/dates.dart';
import '../../logic/money.dart';
import '../../logic/services_catalog.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'accounts_screens.dart';
import 'mail_screens.dart';

StatusKind subStatus(Subscription s, DateTime now) {
  final left = daysUntil(upcomingRenewal(s, now), now);
  if (s.isPaused) return StatusKind.safe;
  if (s.isCancelCandidate && left <= s.remindDaysBefore) {
    return StatusKind.danger;
  }
  if (left <= s.remindDaysBefore) return StatusKind.caution;
  return StatusKind.progress;
}

class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.isUnlocked) return const SizedBox.shrink();
    final d = app.data;
    final now = app.now();
    final t = Theme.of(context).textTheme;
    final sum = summarize(d);
    final timeline = renewalsInMonth(d, now);
    final subs = [...d.subscriptions]
      ..sort((a, b) {
        final sa = subStatus(a, now).index, sb = subStatus(b, now).index;
        if (sa != sb) return sb.compareTo(sa); // 위험·임박 먼저
        return upcomingRenewal(a, now).compareTo(upcomingRenewal(b, now));
      });

    return AppPage(
      title: '구독 결제',
      restoreId: 'subs',
      bottom: const ClipboardBanner(),
      children: [
        const TipBubble(
          id: 'subs',
          text: '구독을 추가하면 월·연간 총액과 결제일을 자동으로 계산해 드려요. 결제 메일을 붙여 넣어도 돼요.',
        ),
        HeroNumberCard(
          label: '이번 달 구독료',
          value: formatWon(sum.monthly),
          caption: '1년이면 ${formatWon(sum.yearly)} · 구독 ${sum.activeCount}개',
        ),
        if (d.subscriptions.any((s) => s.currency == Currency.usd))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '달러 요금은 1달러 = ${d.prefs.usdToKrw}원으로 계산했어요(설정에서 변경).',
              style: t.bodyMedium,
            ),
          ),
        gap,
        Row(
          children: [
            Expanded(
              child: BigButton(
                label: '구독 추가',
                icon: Icons.add_rounded,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SubscriptionEditScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BigButton(
                label: '메일로 채우기',
                icon: Icons.mail_rounded,
                kind: ButtonKind.accent,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MailImportScreen()),
                ),
              ),
            ),
          ],
        ),
        SectionTitle('이번 달 결제 예정 (${now.month}월)'),
        if (timeline.isEmpty)
          Text('이번 달에 남은 결제가 없어요.', style: t.bodyLarge)
        else
          FlatCard(
            child: Column(
              children: [
                for (final (day, s) in timeline)
                  _TimelineRow(day: day, sub: s, now: now),
              ],
            ),
          ),
        SectionTitle('내 구독 ${d.subscriptions.length}개'),
        if (subs.isEmpty)
          EmptyState(
            emoji: 'credit_card',
            message: '아직 등록된 구독이 없어요.\n직접 넣거나 결제 메일로 채워 보세요.',
            action: BigButton(
              label: '첫 구독 넣기',
              icon: Icons.add_rounded,
              kind: ButtonKind.safe,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SubscriptionEditScreen(),
                ),
              ),
            ),
          )
        else
          for (final s in subs) ...[
            SubscriptionCard(sub: s, now: now),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.day, required this.sub, required this.now});
  final DateTime day;
  final Subscription sub;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final past = day.isBefore(DateTime(now.year, now.month, now.day));
    final left = daysUntil(day, now);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: past
                  ? p.surfaceAlt
                  : (left <= 3 ? p.cautionFill : p.progressFill),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${day.day}일',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: past
                    ? p.textMuted
                    : (left <= 3 ? p.onCautionFill : p.onProgressFill),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${sub.serviceName}${past ? ' (결제됨)' : ''}',
                  style: TextStyle(
                    fontSize: AppTokens.fontBody,
                    color: past ? p.textMuted : p.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  formatAmount(sub.amount, sub.currency),
                  style: TextStyle(
                    fontSize: AppTokens.fontBody,
                    color: past ? p.textMuted : p.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SubscriptionCard extends StatelessWidget {
  const SubscriptionCard({super.key, required this.sub, required this.now});
  final Subscription sub;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    final next = upcomingRenewal(sub, now);
    final left = daysUntil(next, now);
    final st = subStatus(sub, now);
    return FlatCard(
      status: st == StatusKind.progress ? null : st,
      padding: EdgeInsets.zero,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SubscriptionDetailScreen(id: sub.id)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 왼쪽 서비스 색 띠
            Container(width: 8, color: serviceColor(sub.serviceName)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.s4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ServiceAvatar(sub.serviceName, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sub.serviceName, style: t.titleLarge),
                          Text(
                            '${formatAmount(sub.amount, sub.currency)} · ${sub.cycle.label}'
                            '${sub.cardLast4 == null ? '' : ' · 카드 끝 ${sub.cardLast4}'}',
                            style: t.bodyLarge?.copyWith(color: p.textMuted),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              if (sub.isPaused)
                                const StatusBadge(
                                  StatusKind.safe,
                                  '일시 중지',
                                  compact: true,
                                )
                              else
                                StatusBadge(
                                  st,
                                  '다음 결제 ${formatKoreanDate(next)} · ${relativeDays(left)}',
                                  compact: true,
                                ),
                              if (sub.isCancelCandidate)
                                const StatusBadge(
                                  StatusKind.danger,
                                  '해지 후보',
                                  compact: true,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SubscriptionDetailScreen extends StatelessWidget {
  const SubscriptionDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.isUnlocked) return const SizedBox.shrink();
    final d = app.data;
    final s = d.subscriptions.where((e) => e.id == id).firstOrNull;
    if (s == null) {
      return const AppPage(title: '구독', children: [Text('삭제된 구독이에요.')]);
    }
    final now = app.now();
    final t = Theme.of(context).textTheme;
    final next = upcomingRenewal(s, now);
    final known = findKnownService(s.serviceName);
    final account = guessAccountFor(d, s);
    final cancelUrl = (s.cancelUrl?.isNotEmpty ?? false)
        ? s.cancelUrl
        : known?.manageUrl;

    return AppPage(
      title: s.serviceName,
      restoreId: 'sub:$id',
      children: [
        FlatCard(
          status: subStatus(s, now) == StatusKind.progress
              ? null
              : subStatus(s, now),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow(
                '요금',
                '${formatAmount(s.amount, s.currency)} (${s.cycle.label})',
              ),
              InfoRow('한 달 기준', formatWon(monthlyWon(s, d.prefs.usdToKrw))),
              InfoRow(
                '다음 결제일',
                '${formatKoreanDateFull(next)} (${relativeDays(daysUntil(next, now))})',
              ),
              InfoRow(
                '결제 카드',
                s.cardLast4 == null ? '' : '끝 4자리 ${s.cardLast4}',
              ),
              InfoRow('분류', s.category),
              InfoRow(
                '마지막 사용',
                s.lastUsedAt == null
                    ? '기록 없음'
                    : formatKoreanDateFull(s.lastUsedAt!),
              ),
              InfoRow('결제 전 알림', '${s.remindDaysBefore}일 전'),
              if (s.memo.isNotEmpty) InfoRow('메모', s.memo),
            ],
          ),
        ),
        gap,
        BigButton(
          label: account == null ? '이 구독의 로그인 계정 등록' : '이 구독의 로그인 계정 보기',
          icon: Icons.key_rounded,
          kind: ButtonKind.accent,
          onPressed: () async {
            if (account != null) {
              if (s.accountId != account.id) {
                await app.mutate((_) => s.accountId = account.id);
              }
              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AccountDetailScreen(id: account.id),
                  ),
                );
              }
            } else {
              final created = await Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      AccountEditScreen(presetService: s.serviceName),
                ),
              );
              if (created != null) {
                await app.mutate((_) => s.accountId = created);
              }
            }
          },
        ),
        gap,
        BigButton(
          label: '오늘 썼어요 (사용일 기록)',
          icon: Icons.today_rounded,
          kind: ButtonKind.safe,
          onPressed: () async {
            await app.mutate((_) => s.lastUsedAt = now);
            if (context.mounted) context.toast('오늘 사용한 것으로 기록했어요.');
          },
        ),
        gap,
        BigButton(
          label: s.isCancelCandidate ? '해지 후보에서 빼기' : '해지 후보에 넣기',
          icon: Icons.flag_rounded,
          kind: ButtonKind.caution,
          onPressed: () =>
              app.mutate((_) => s.isCancelCandidate = !s.isCancelCandidate),
        ),
        gap,
        BigButton(
          label: '수정',
          icon: Icons.edit_rounded,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SubscriptionEditScreen(existing: s),
            ),
          ),
        ),
        SectionTitle('해지 방법'),
        FlatCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                known?.cancelSteps ??
                    '서비스 사이트에 로그인 → 설정(또는 계정) → 결제·구독 → 구독 취소',
                style: t.bodyLarge,
              ),
              const SizedBox(height: 6),
              Text(
                '해지는 직접 하셔야 해요. 앱은 해지하지 않아요. 주소가 바뀌었을 수 있어요.',
                style: t.bodyMedium,
              ),
              if (cancelUrl != null) ...[
                gap,
                BigButton(
                  label: '해지·결제 관리 페이지 열기',
                  icon: Icons.open_in_new_rounded,
                  kind: ButtonKind.plain,
                  onPressed: () async {
                    final ok = await app.services.launcher.open(
                      Uri.parse(cancelUrl),
                    );
                    if (!ok && context.mounted) context.toast('페이지를 열지 못했어요.');
                  },
                ),
              ],
            ],
          ),
        ),
        gapBig,
        BigButton(
          label: '이 구독 삭제',
          icon: Icons.delete_rounded,
          kind: ButtonKind.danger,
          onPressed: () async {
            final ok = await confirmTwice(
              context,
              title: '구독 삭제',
              message: '"${s.serviceName}" 구독 기록을 지울까요? (실제 서비스 해지는 되지 않아요)',
              confirmLabel: '삭제',
            );
            if (!ok) return;
            await app.mutate(
              (d) => d.subscriptions.removeWhere((e) => e.id == s.id),
            );
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ],
    );
  }
}

const subscriptionCategories = ['AI', '디자인', '영상', '음악', '업무', '쇼핑', '기타'];

class SubscriptionEditScreen extends StatefulWidget {
  const SubscriptionEditScreen({super.key, this.existing, this.preset});
  final Subscription? existing;
  final Subscription? preset;

  @override
  State<SubscriptionEditScreen> createState() => _SubscriptionEditScreenState();
}

class _SubscriptionEditScreenState extends State<SubscriptionEditScreen> {
  late final Subscription? src = widget.existing ?? widget.preset;
  late final name = TextEditingController(text: src?.serviceName ?? '');
  late final amount = TextEditingController(
    text: src == null
        ? ''
        : (src!.currency == Currency.usd
              ? (src!.amount / 100).toStringAsFixed(2)
              : '${src!.amount}'),
  );
  late final card = TextEditingController(text: src?.cardLast4 ?? '');
  late final memo = TextEditingController(text: src?.memo ?? '');
  late final cancelUrl = TextEditingController(text: src?.cancelUrl ?? '');
  late Currency currency = src?.currency ?? Currency.krw;
  late BillingCycle cycle = src?.cycle ?? BillingCycle.monthly;
  late String category = src?.category ?? '기타';
  late DateTime renewal =
      src?.nextRenewal ?? DateTime.now().add(const Duration(days: 30));
  late int remind = src?.remindDaysBefore ?? 3;
  late bool paused = src?.isPaused ?? false;
  String? error;

  @override
  void dispose() {
    for (final c in [name, amount, card, memo, cancelUrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final app = context.appRead;
    final n = name.text.trim();
    final raw = amount.text.replaceAll(',', '').trim();
    final value = double.tryParse(raw);
    if (n.isEmpty) return setState(() => error = '서비스 이름을 적어 주세요.');
    if (value == null || value < 0) {
      return setState(() => error = '요금을 숫자로 적어 주세요.');
    }
    final amt = currency == Currency.usd
        ? (value * 100).round()
        : value.round();
    final last4 = card.text.trim().isEmpty
        ? null
        : sanitizeCardLast4(card.text);
    if (card.text.trim().isNotEmpty &&
        (last4 == null ||
            card.text.replaceAll(RegExp(r'\D'), '').length != 4)) {
      return setState(() => error = '카드는 끝 4자리 숫자만 적어 주세요.');
    }
    final known = findKnownService(n);
    await app.mutate((d) {
      final e = widget.existing;
      if (e != null) {
        e
          ..serviceName = n
          ..amount = amt
          ..currency = currency
          ..cycle = cycle
          ..category = category
          ..nextRenewal = renewal
          ..card = last4
          ..remindDaysBefore = remind
          ..isPaused = paused
          ..memo = memo.text.trim()
          ..cancelUrl = cancelUrl.text.trim().isEmpty
              ? null
              : cancelUrl.text.trim();
      } else {
        d.subscriptions.add(
          Subscription(
            serviceName: known?.displayName ?? n,
            amount: amt,
            currency: currency,
            cycle: cycle,
            category:
                category == '기타' && (known?.group?.startsWith('AI') ?? false)
                ? 'AI'
                : category,
            nextRenewal: renewal,
            cardLast4: last4,
            remindDaysBefore: remind,
            isPaused: paused,
            memo: memo.text.trim(),
            cancelUrl: cancelUrl.text.trim().isEmpty
                ? null
                : cancelUrl.text.trim(),
          ),
        );
      }
    });
    if (mounted) {
      context.toast('저장했어요.');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppPage(
      title: widget.existing == null ? '구독 추가' : '구독 수정',
      children: [
        BigField(controller: name, label: '서비스 이름', hint: '예: Claude, 넷플릭스'),
        gap,
        Text('돈 단위', style: t.titleMedium),
        const SizedBox(height: 6),
        ChoiceChips<Currency>(
          values: Currency.values,
          selected: currency,
          label: (c) => c.label,
          onSelected: (c) => setState(() => currency = c),
        ),
        gap,
        BigField(
          controller: amount,
          label: currency == Currency.usd
              ? '요금(달러, 예: 20 또는 19.99)'
              : '요금(원, 예: 29000)',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        gap,
        Text('결제 주기', style: t.titleMedium),
        const SizedBox(height: 6),
        ChoiceChips<BillingCycle>(
          values: BillingCycle.values,
          selected: cycle,
          label: (c) => c.label,
          onSelected: (c) => setState(() => cycle = c),
        ),
        gap,
        Text('다음 결제일', style: t.titleMedium),
        const SizedBox(height: 6),
        DatePickButton(
          date: renewal,
          onPicked: (d) => setState(() => renewal = d),
        ),
        gap,
        BigField(
          controller: card,
          label: '결제 카드 끝 4자리 (선택)',
          keyboard: TextInputType.number,
          maxLength: 4,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('안전을 위해 카드 번호 전체는 저장하지 않아요.', style: t.bodyMedium),
        ),
        gap,
        Text('분류', style: t.titleMedium),
        const SizedBox(height: 6),
        ChoiceChips<String>(
          values: subscriptionCategories,
          selected: category,
          label: (c) => c,
          onSelected: (c) => setState(() => category = c),
        ),
        gap,
        Text('결제 며칠 전에 알릴까요?', style: t.titleMedium),
        const SizedBox(height: 6),
        ChoiceChips<int>(
          values: const [1, 3, 7],
          selected: remind,
          label: (v) => '$v일 전',
          onSelected: (v) => setState(() => remind = v),
        ),
        gap,
        SwitchRow(
          title: '일시 중지',
          subtitle: '합계와 알림에서 빼요',
          value: paused,
          onChanged: (v) => setState(() => paused = v),
        ),
        gap,
        BigField(
          controller: cancelUrl,
          label: '해지·결제 관리 주소 (선택)',
          keyboard: TextInputType.url,
        ),
        gap,
        BigField(controller: memo, label: '메모 (선택)', maxLines: 3),
        if (error != null) ...[gap, StatusBadge(StatusKind.danger, error!)],
        gapBig,
        BigButton(
          label: '저장',
          icon: Icons.save_rounded,
          kind: ButtonKind.safe,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// 큰 날짜 선택 버튼.
class DatePickButton extends StatelessWidget {
  const DatePickButton({super.key, required this.date, required this.onPicked});
  final DateTime date;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) => BigButton(
    label: formatKoreanDateFull(date),
    icon: Icons.calendar_month_rounded,
    kind: ButtonKind.plain,
    onPressed: () async {
      final d = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: '날짜 고르기',
        cancelText: '취소',
        confirmText: '확인',
      );
      if (d != null) onPicked(d);
    },
  );
}
