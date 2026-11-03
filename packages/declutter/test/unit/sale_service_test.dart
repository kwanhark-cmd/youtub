import 'package:binugi/core/clock.dart';
import 'package:binugi/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  test('가격 인하 추천: 14일 지나면 10% 내림, 1000원 단위, 시세 최저값 아래로는 안 내림', () async {
    final clock = FakeClock(DateTime(2026, 1, 1, 9));
    final (s, _) = await makeState(clock: clock);
    final it = await s.addItem(name: '커피 머신');
    it.priceLow = 20000;
    await s.sales.startSelling(it, price: 30000);
    expect(s.sales.suggestedDrop(it, s.user, at: clock.now()), isNull);
    clock.advance(const Duration(days: 14));
    expect(s.sales.suggestedDrop(it, s.user, at: clock.now()), 27000);
    await s.sales.applyPriceDrop(it, 27000);
    clock.advance(const Duration(days: 14));
    expect(s.sales.suggestedDrop(it, s.user, at: clock.now()), 24000);
    await s.sales.applyPriceDrop(it, 24000);
    clock.advance(const Duration(days: 14));
    expect(s.sales.suggestedDrop(it, s.user, at: clock.now()), 22000);
    await s.sales.applyPriceDrop(it, 22000);
    clock.advance(const Duration(days: 14));
    expect(s.sales.suggestedDrop(it, s.user, at: clock.now()), 20000);
    await s.sales.applyPriceDrop(it, 20000);
    clock.advance(const Duration(days: 14));
    expect(s.sales.suggestedDrop(it, s.user, at: clock.now()), isNull, reason: '최저값에 도달하면 더 추천하지 않음');
  });

  test('판매완료·예약이면 인하 추천 없음', () async {
    final clock = FakeClock(DateTime(2026, 1, 1, 9));
    final (s, _) = await makeState(clock: clock);
    final it = await s.addItem(name: '의자');
    await s.sales.startSelling(it, price: 10000);
    clock.advance(const Duration(days: 30));
    await s.sales.setStatus(it, SaleStatus.reserved);
    expect(s.sales.suggestedDrop(it, s.user, at: clock.now()), isNull);
    await s.sales.setStatus(it, SaleStatus.sold, soldPrice: 9000);
    expect(it.soldPrice, 9000);
    expect(s.sales.suggestedDrop(it, s.user, at: clock.now()), isNull);
  });

  test('1년 경과: 7일 전 미리 알림, 365일에 폐기로 이동 + 알림, 되돌리기', () async {
    final clock = FakeClock(DateTime(2026, 1, 1, 9));
    final (s, _) = await makeState(clock: clock);
    final it = await s.addItem(name: '스탠드');
    await s.sales.startSelling(it, price: 15000);

    clock.advance(const Duration(days: 357));
    await s.runDailyChecks();
    expect(s.lastCheck!.warned, isEmpty);

    clock.advance(const Duration(days: 1)); // 358일
    await s.runDailyChecks();
    expect(s.lastCheck!.warned.map((e) => e.id), [it.id]);
    expect((await s.repo.notices(s.uid)).any((n) => n.kind == 'one_year_warn'), isTrue);

    clock.advance(const Duration(days: 1));
    await s.runDailyChecks();
    expect(s.lastCheck!.warned, isEmpty, reason: '미리 알림은 한 번만');

    clock.advance(const Duration(days: 6)); // 365일
    await s.runDailyChecks();
    final moved = await s.repo.item(s.uid, it.id!);
    expect(moved!.decision, Decision.discard);
    expect(moved.movedFromSaleAt, isNotNull);
    expect((await s.repo.notices(s.uid)).any((n) => n.kind == 'one_year_moved'), isTrue);

    await s.sales.undoMoveToDiscard(moved);
    final back = await s.repo.item(s.uid, it.id!);
    expect(back!.decision, Decision.sell);
    expect(back.saleStatus, SaleStatus.listing);
  });

  test('기기 시간이 뒤로 가도 날짜 계산이 꼬이지 않음', () async {
    final clock = FakeClock(DateTime(2026, 1, 1, 9));
    final (s, _) = await makeState(clock: clock);
    final it = await s.addItem(name: '선풍기');
    await s.sales.startSelling(it, price: 20000);
    clock.advance(const Duration(days: 200));
    await s.runDailyChecks();
    // 시간이 1년 전으로 돌아감
    clock.current = DateTime(2025, 1, 1);
    await s.runDailyChecks();
    expect(s.now.isAfter(DateTime(2026, 7, 1)), isTrue, reason: '앱이 본 가장 늦은 시각을 사용');
    expect(s.sales.daysListed(it, s.now), greaterThanOrEqualTo(200));
    expect(elapsedDays(DateTime(2026, 1, 1), DateTime(2025, 1, 1)), 0, reason: '음수가 되지 않음');
    final again = await s.repo.item(s.uid, it.id!);
    expect(again!.decision, Decision.sell, reason: '엉뚱하게 폐기로 옮겨지지 않음');
  });

  test('가격 인하 알림은 주기마다 한 번', () async {
    final clock = FakeClock(DateTime(2026, 1, 1, 9));
    final (s, _) = await makeState(clock: clock);
    final it = await s.addItem(name: '전기 주전자');
    await s.sales.startSelling(it, price: 20000);
    clock.advance(const Duration(days: 15));
    await s.runDailyChecks();
    expect(s.lastCheck!.priceDrops.length, 1);
    clock.advance(const Duration(days: 1));
    await s.runDailyChecks();
    expect(s.lastCheck!.priceDrops, isEmpty);
  });
}
