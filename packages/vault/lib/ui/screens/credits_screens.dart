import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../logic/dates.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'mail_screens.dart';
import 'subscriptions_screens.dart' show DatePickButton;

StatusKind creditStatus(CreditItem c, DateTime now) {
  if (c.done) return StatusKind.safe;
  final left = daysUntil(c.expiresAt, now);
  if (left <= 1) return StatusKind.danger;
  if (left <= 7) return StatusKind.caution;
  return StatusKind.progress;
}

/// 무료·보너스 크레딧, 체험판 만료일 목록. 임박한 것(노랑·빨강)이 맨 위.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.isUnlocked) return const SizedBox.shrink();
    final d = app.data;
    final now = app.now();
    final t = Theme.of(context).textTheme;
    final active = d.credits.where((c) => !c.done).toList()
      ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
    final done = d.credits.where((c) => c.done).toList();
    return AppPage(
      title: '만료 알림',
      restoreId: 'credits',
      children: [
        const TipBubble(
          id: 'credits',
          text: '무료 크레딧이나 체험판 마감일을 적어 두면 7일 전, 1일 전에 알려 드려요.',
        ),
        Row(
          children: [
            Expanded(
              child: BigButton(
                label: '마감일 추가',
                icon: Icons.add_alarm_rounded,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreditEditScreen()),
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
        SectionTitle('남은 항목 ${active.length}개'),
        if (active.isEmpty)
          EmptyState(
            emoji: 'hourglass_not_done',
            message: '등록된 크레딧·체험판이 없어요.\n무료 크레딧이나 체험판 마감일을 넣어 두면 미리 알려 드려요.',
            action: BigButton(
              label: '첫 마감일 넣기',
              icon: Icons.add_alarm_rounded,
              kind: ButtonKind.safe,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreditEditScreen()),
              ),
            ),
          )
        else
          for (final c in active) ...[
            _CreditCard(c: c, now: now),
            const SizedBox(height: 10),
          ],
        if (done.isNotEmpty) ...[
          SectionTitle('정리한 항목 ${done.length}개'),
          for (final c in done) ...[
            _CreditCard(c: c, now: now),
            const SizedBox(height: 10),
          ],
        ],
        gap,
        Text(
          '알림이 절전 모드 때문에 늦게 올 수 있어요. 앱을 열면 놓친 알림을 먼저 보여 드려요.',
          style: t.bodyMedium,
        ),
      ],
    );
  }
}

class _CreditCard extends StatelessWidget {
  const _CreditCard({required this.c, required this.now});
  final CreditItem c;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final left = daysUntil(c.expiresAt, now);
    final st = creditStatus(c, now);
    final snoozed = c.snoozeUntil != null && daysUntil(c.snoozeUntil!, now) > 0;
    final label = c.done
        ? '정리함'
        : (left < 0
              ? '만료됨'
              : '${formatKoreanDate(c.expiresAt)} · ${relativeDays(left)}');
    return FlatCard(
      status: st == StatusKind.progress ? null : st,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CreditEditScreen(existing: c)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ServiceAvatar(c.serviceName, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.serviceName, style: t.titleLarge),
                    Text(
                      [
                        c.kind.label,
                        if (c.amountText.isNotEmpty) c.amountText,
                      ].join(' · '),
                      style: t.bodyLarge,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StatusBadge(st, label, compact: true),
          if (snoozed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${formatKoreanDate(c.snoozeUntil!)}에 다시 알려 드려요',
                style: t.bodyMedium,
              ),
            )
          else if (!c.done && left <= 7) ...[
            const SizedBox(height: 10),
            BigButton(
              label: '내일 다시 알림',
              icon: Icons.snooze_rounded,
              kind: ButtonKind.plain,
              raised: false,
              onPressed: () async {
                final tomorrow = DateTime(now.year, now.month, now.day + 1);
                await context.appRead.mutate((_) => c.snoozeUntil = tomorrow);
                if (context.mounted) context.toast('내일 다시 알려 드릴게요.');
              },
            ),
          ],
        ],
      ),
    );
  }
}

class CreditEditScreen extends StatefulWidget {
  const CreditEditScreen({super.key, this.existing, this.preset});
  final CreditItem? existing;
  final CreditItem? preset;

  @override
  State<CreditEditScreen> createState() => _CreditEditScreenState();
}

class _CreditEditScreenState extends State<CreditEditScreen> {
  late final CreditItem? src = widget.existing ?? widget.preset;
  late final name = TextEditingController(text: src?.serviceName ?? '');
  late final amount = TextEditingController(text: src?.amountText ?? '');
  late final memo = TextEditingController(text: src?.memo ?? '');
  late CreditKind kind = src?.kind ?? CreditKind.freeCredit;
  late DateTime expires =
      src?.expiresAt ?? DateTime.now().add(const Duration(days: 14));
  late bool done = src?.done ?? false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    memo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = name.text.trim();
    if (n.isEmpty) return setState(() => error = '서비스 이름을 적어 주세요.');
    await context.appRead.mutate((d) {
      final e = widget.existing;
      if (e != null) {
        e
          ..serviceName = n
          ..kind = kind
          ..amountText = amount.text.trim()
          ..expiresAt = expires
          ..memo = memo.text.trim()
          ..done = done;
      } else {
        d.credits.add(
          CreditItem(
            serviceName: n,
            kind: kind,
            amountText: amount.text.trim(),
            expiresAt: expires,
            memo: memo.text.trim(),
          ),
        );
      }
    });
    if (mounted) {
      context.toast('저장했어요. 7일 전·1일 전에 알려 드릴게요.');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppPage(
      title: widget.existing == null ? '마감일 추가' : '마감일 수정',
      children: [
        BigField(controller: name, label: '서비스 이름', hint: '예: 힉스필드'),
        gap,
        Text('종류', style: t.titleMedium),
        const SizedBox(height: 6),
        ChoiceChips<CreditKind>(
          values: CreditKind.values,
          selected: kind,
          label: (k) => k.label,
          onSelected: (k) => setState(() => kind = k),
        ),
        gap,
        BigField(controller: amount, label: '양 (선택, 예: 300 크레딧)'),
        gap,
        Text('끝나는 날', style: t.titleMedium),
        const SizedBox(height: 6),
        DatePickButton(
          date: expires,
          onPicked: (d) => setState(() => expires = d),
        ),
        gap,
        BigField(controller: memo, label: '메모 (선택)', maxLines: 3),
        if (widget.existing != null) ...[
          gap,
          SwitchRow(
            title: '다 썼어요 / 정리했어요',
            subtitle: '켜면 더 이상 알리지 않아요',
            value: done,
            onChanged: (v) => setState(() => done = v),
          ),
        ],
        if (error != null) ...[gap, StatusBadge(StatusKind.danger, error!)],
        gapBig,
        BigButton(
          label: '저장',
          icon: Icons.save_rounded,
          kind: ButtonKind.safe,
          onPressed: _save,
        ),
        if (widget.existing != null) ...[
          gapBig,
          BigButton(
            label: '삭제',
            icon: Icons.delete_rounded,
            kind: ButtonKind.danger,
            onPressed: () async {
              final ok = await confirmTwice(
                context,
                title: '삭제',
                message: '"${widget.existing!.serviceName}" 마감일을 지울까요?',
                confirmLabel: '삭제',
              );
              if (!ok || !context.mounted) return;
              await context.appRead.mutate(
                (d) =>
                    d.credits.removeWhere((e) => e.id == widget.existing!.id),
              );
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ],
    );
  }
}
