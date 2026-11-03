import 'dart:typed_data';

import '../../core/format.dart';
import '../../data/models.dart';
import '../knowledge.dart';
import 'ai_provider.dart';
import 'listing_template.dart';

/// 연습 모드: 외부 연결 없이 가짜 결과를 돌려줍니다. 비용 0원.
class PracticeAi implements AiProvider {
  @override
  String get name => '연습 모드';
  @override
  bool get isPractice => true;

  static const _samples = [
    ['커피 머신', '소형 가전', '사용감 있음, 잘 작동함'],
    ['전기 주전자', '소형 가전', '물때 조금 있음'],
    ['오래된 책 묶음', '책·문구', '누렇게 바램'],
    ['나무 의자', '가구', '다리 흔들림'],
    ['겨울 패딩', '옷·신발·가방', '깨끗함'],
    ['프라이팬', '주방용품', '코팅 벗겨짐'],
    ['블루투스 스피커', '디지털 기기', '잘 작동함'],
    ['아기 장난감', '장난감·유아용품', '깨끗함'],
    ['요가 매트', '운동·취미', '거의 안 씀'],
    ['여행 기념품', '추억 물건', '먼지 쌓임'],
  ];

  @override
  Future<AiResult<List<DetectedItem>>> recognize(Uint8List jpeg, {int width = 0, int height = 0, String? hint}) async {
    var seed = jpeg.length;
    for (var i = 0; i < jpeg.length; i += 997) {
      seed = (seed * 31 + jpeg[i]) & 0x7fffffff;
    }
    final count = 1 + seed % 3;
    final out = <DetectedItem>[];
    for (var i = 0; i < count; i++) {
      final s = _samples[(seed + i * 3) % _samples.length];
      final it = Item(userId: 0, name: s[0], kind: s[1], condition: s[2], createdAt: DateTime(2000));
      final d = ruleSuggest(it);
      out.add(DetectedItem(name: s[0], kind: s[1], condition: s[2], suggestion: d, reason: '(연습) ${ruleReason(d)}'));
    }
    if (hint != null && hint.trim().isNotEmpty) {
      out.first.name = hint.trim();
    }
    return AiResult(out, 0);
  }

  @override
  Future<AiResult<Suggestion>> suggest(Item item) async {
    final d = ruleSuggest(item);
    return AiResult(Suggestion(d, '(연습) ${ruleReason(d)}'), 0);
  }

  @override
  Future<AiResult<ListingDraft>> writeListing(Item item, {Uint8List? jpeg, int width = 0, int height = 0}) async {
    final info = kindInfoFor(item.name, item.kind);
    var lo = info.priceLow;
    var hi = info.priceHigh;
    final t = '${item.condition} ${item.description}';
    if (RegExp(r'새것|미개봉').hasMatch(t)) {
      lo = (lo * 1.5).round();
      hi = (hi * 1.5).round();
    } else if (RegExp(r'사용감|낡|흠').hasMatch(t)) {
      lo = (lo * 0.6).round();
      hi = (hi * 0.7).round();
    }
    lo = roundTo1000(lo);
    hi = roundTo1000(hi < lo ? lo : hi);
    return AiResult(templateListing(item, info, lo, hi), 0);
  }
}
