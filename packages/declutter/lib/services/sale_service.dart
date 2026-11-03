import '../core/clock.dart';
import '../core/format.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/settings.dart';

/// 판매 규칙: 가격 인하 추천, 1년 경과 시 폐기 목록으로 이동.
class SaleService {
  final Repository repo;
  final Clock clock;
  SaleService(this.repo, this.clock);

  static const oneYearDays = 365;
  static const warnBeforeDays = 7;

  /// 판매 시작 (등록일 기록)
  Future<void> startSelling(Item item, {required int price}) async {
    final now = clock.now();
    item.decision = Decision.sell;
    item.decidedAt ??= now;
    item.saleStatus = SaleStatus.listing;
    item.price = price;
    item.initialPrice ??= price;
    item.listedAt ??= now;
    await repo.updateItem(item);
  }

  Future<void> setStatus(Item item, SaleStatus status, {int? soldPrice}) async {
    item.saleStatus = status;
    if (status == SaleStatus.sold) {
      item.soldAt = clock.now();
      item.soldPrice = soldPrice ?? item.price;
    } else {
      item.soldAt = null;
      item.soldPrice = null;
    }
    await repo.updateItem(item);
  }

  /// 가격 인하 추천값 (null 이면 지금은 추천 없음)
  int? suggestedDrop(Item item, UserSettings s, {DateTime? at}) {
    if (item.decision != Decision.sell || item.saleStatus != SaleStatus.listing) return null;
    final price = item.price;
    final since = item.lastPriceDropAt ?? item.listedAt;
    if (price == null || since == null) return null;
    if (elapsedDays(since, at ?? clock.now()) < s.priceDropDays) return null;
    var next = roundTo1000(price * (100 - s.priceDropPercent) / 100);
    if (next >= price) next = price - 1000;
    final floor = item.priceLow ?? 1000;
    if (next < floor) next = floor;
    if (next >= price || next <= 0) return null;
    return next;
  }

  Future<void> applyPriceDrop(Item item, int newPrice) async {
    item.price = newPrice;
    item.lastPriceDropAt = clock.now();
    item.priceDropSuggestedAt = null;
    await repo.updateItem(item);
  }

  /// 판매 등록 후 지난 날 (기기 시간이 뒤로 가도 0 미만이 되지 않음)
  int daysListed(Item item, DateTime now) => item.listedAt == null ? 0 : elapsedDays(item.listedAt!, now);

  /// 매일 한 번(앱 열 때) 실행: 가격 인하 알림, 1년 경과 미리 알림·이동.
  /// [now]는 "앱이 본 가장 늦은 시각"을 써서 시간이 앞뒤로 바뀌어도 꼬이지 않게 합니다.
  Future<SaleCheckResult> dailyCheck(int userId, UserSettings s, DateTime now) async {
    final result = SaleCheckResult();
    final selling = (await repo.items(userId, decision: Decision.sell)).where((i) => i.saleStatus != SaleStatus.sold).toList();
    for (final item in selling) {
      final days = daysListed(item, now);
      if (days >= oneYearDays) {
        item.decision = Decision.discard;
        item.movedFromSaleAt = now;
        item.decidedAt = now;
        item.saleStatus = null;
        await repo.updateItem(item);
        await repo.addNotice(
          Notice(
            userId: userId,
            kind: 'one_year_moved',
            title: '1년 동안 안 팔려 폐기 목록으로 옮겼어요',
            body: '"${item.name}"을(를) 폐기 목록으로 옮겼어요. 마음이 바뀌면 물건 화면에서 "판매로 되돌리기"를 누르세요.',
            itemId: item.id,
            createdAt: now,
          ),
        );
        result.moved.add(item);
        continue;
      }
      if (days >= oneYearDays - warnBeforeDays && item.oneYearWarnedAt == null) {
        item.oneYearWarnedAt = now;
        await repo.updateItem(item);
        await repo.addNotice(
          Notice(
            userId: userId,
            kind: 'one_year_warn',
            title: '곧 폐기 목록으로 옮겨져요',
            body: '"${item.name}"이(가) 판매 1년이 다 돼 가요. ${oneYearDays - days}일 뒤 폐기 목록으로 옮겨요. 가격을 내리거나 나눔을 해 보세요.',
            itemId: item.id,
            createdAt: now,
          ),
        );
        result.warned.add(item);
      }
      if (item.saleStatus == SaleStatus.listing) {
        final drop = suggestedDrop(item, s, at: now);
        final last = item.priceDropSuggestedAt;
        if (drop != null && (last == null || elapsedDays(last, now) >= s.priceDropDays)) {
          item.priceDropSuggestedAt = now;
          await repo.updateItem(item);
          await repo.addNotice(
            Notice(
              userId: userId,
              kind: 'price_drop',
              title: '가격을 조금 내려 볼까요?',
              body: '"${item.name}"이(가) ${daysListed(item, now)}일째 안 팔렸어요. ${won(item.price)} → ${won(drop)} 추천해요.',
              itemId: item.id,
              createdAt: now,
            ),
          );
          result.priceDrops.add(item);
        }
      }
    }
    return result;
  }

  /// 1년 이동을 되돌리기 (판매로 다시, 등록일은 새로 시작)
  Future<void> undoMoveToDiscard(Item item) async {
    final now = clock.now();
    item.decision = Decision.sell;
    item.saleStatus = SaleStatus.listing;
    item.movedFromSaleAt = null;
    item.listedAt = now;
    item.lastPriceDropAt = null;
    item.oneYearWarnedAt = null;
    await repo.updateItem(item);
  }
}

class SaleCheckResult {
  final List<Item> moved = [];
  final List<Item> warned = [];
  final List<Item> priceDrops = [];
}
