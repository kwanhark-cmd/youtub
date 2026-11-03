import 'package:binugi/core/clock.dart';
import 'package:binugi/data/models.dart';
import 'package:binugi/services/voice_commands.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// 지시서의 흐름 점검 (연습 모드):
/// 사진 등록 → 음성 설명 → 분류 추천 → 확정 → 판매글 복사 → 가격 인하 알림 → 1년 경과 시 폐기 이동 → 현황
void main() {
  test('전체 흐름 (날짜를 가짜로 바꿔 1년 경과 확인)', () async {
    final clock = FakeClock(DateTime(2026, 1, 1, 9));
    final (s, _) = await makeState(clock: clock);

    // 1) 사진 등록 (카메라 대신 사진 파일)
    final photo = await s.savePhoto(fakeJpeg(seed: 7));
    // 2) 음성 설명 (마이크 대신 글자 입력)
    const said = '10년 된 커피 머신, 잘 작동함';
    final found = await s.ai.recognize(s.uid, s.user, await s.images.readPhoto(photo.photoPath), width: photo.width, height: photo.height, hint: said);
    expect(found.practice, isTrue);
    final d = found.value.first;
    final item = await s.addItem(
      name: '커피 머신',
      kind: d.kind,
      condition: d.condition,
      description: said,
      photo: photo,
      suggestion: d.suggestion,
      reason: d.reason,
    );

    // 3) 분류 추천
    final sug = await s.ai.suggest(s.uid, s.user, item);
    expect(sug.value.decision, Decision.sell, reason: '"잘 작동함" → 판매 추천');

    // 4) 확정 (음성 "이건 판매", 확인 후 실행)
    final cmd = parseVoiceCommand('이건 판매');
    expect(cmd.needsConfirm, isTrue);
    await s.decide(item, cmd.decision!);
    expect(s.stats!.sell, 1);

    // 5) 판매글 작성·복사할 글
    final listing = await s.ai.writeListing(s.uid, s.user, item);
    item
      ..listingTitle = listing.value.title
      ..listingBody = listing.value.body
      ..priceLow = listing.value.priceLow
      ..priceHigh = listing.value.priceHigh;
    await s.sales.startSelling(item, price: listing.value.priceHigh);
    expect(item.listingBody, contains('커피 머신'));

    // 6) 가격 인하 알림 (15일 뒤)
    clock.advance(const Duration(days: 15));
    await s.runDailyChecks();
    expect(s.lastCheck!.priceDrops, hasLength(1));
    expect(s.unread.any((n) => n.kind == 'price_drop'), isTrue);

    // 7) 1년 경과 → 폐기 이동 (+미리 알림)
    clock.advance(const Duration(days: 345)); // 360일
    await s.runDailyChecks();
    expect(s.unread.any((n) => n.kind == 'one_year_warn'), isTrue);
    clock.advance(const Duration(days: 5)); // 365일
    await s.runDailyChecks();
    final after = await s.repo.item(s.uid, item.id!);
    expect(after!.decision, Decision.discard);

    // 8) 현황
    expect(s.stats!.discard, 1);
    expect(s.stats!.sell, 0);
    expect(s.progressSpeech(), contains('전체 물건은 1개'));
    await s.markDiscardDone(after);
    expect(s.stats!.discarded, 1);
    expect(s.stats!.emptiedRatio, 1);
  });

  test('판매 완료 수입 합계', () async {
    final (s, _) = await makeState();
    for (final (n, price) in [('의자', 10000), ('책상', 25000)]) {
      final it = await s.addItem(name: n);
      await s.sales.startSelling(it, price: price);
      await s.sales.setStatus(it, SaleStatus.sold);
    }
    await s.refresh();
    expect(s.stats!.income, 35000);
    expect(s.stats!.sold, 2);
  });
}
