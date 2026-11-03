import 'package:intl/intl.dart';

import '../data/models.dart';

final _won = NumberFormat('#,###', 'en_US');

String formatWon(num won) => '${_won.format(won.round())}원';

String formatAmount(int amount, Currency c) => switch (c) {
  Currency.krw => formatWon(amount),
  Currency.usd => '\$${(amount / 100).toStringAsFixed(2)}',
};

/// 구독 1건의 한 달 기준 원화 금액.
double monthlyWon(Subscription s, int usdToKrw) {
  final won = s.currency == Currency.usd
      ? s.amount / 100 * usdToKrw
      : s.amount.toDouble();
  return switch (s.cycle) {
    BillingCycle.weekly => won * 52 / 12,
    BillingCycle.monthly => won,
    BillingCycle.yearly => won / 12,
  };
}

class SpendSummary {
  const SpendSummary(this.monthly, this.yearly, this.activeCount);
  final double monthly;
  final double yearly;
  final int activeCount;
}

SpendSummary summarize(VaultData d) {
  final active = d.subscriptions.where((s) => !s.isPaused).toList();
  final m = active.fold<double>(
    0,
    (a, s) => a + monthlyWon(s, d.prefs.usdToKrw),
  );
  return SpendSummary(m, m * 12, active.length);
}
