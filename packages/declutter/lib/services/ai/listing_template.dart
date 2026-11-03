import '../../data/models.dart';
import '../knowledge.dart';
import 'ai_provider.dart';

/// 판매글 기본 틀 (AI 없이도 만들 수 있게)
ListingDraft templateListing(Item item, KindInfo info, int lo, int hi) {
  final cond = item.condition.isEmpty ? '사용감 조금 있어요' : item.condition;
  final desc = item.description.isEmpty ? '' : '\n${item.description}';
  final body = StringBuffer()
    ..writeln('${item.name} 팝니다.')
    ..writeln()
    ..writeln('· 상태: $cond$desc')
    ..writeln('· 사진에 보이는 그대로입니다.')
    ..writeln(info.shippable ? '· 직거래 또는 택배 거래 가능합니다.' : '· 크기가 커서 직거래만 가능합니다.')
    ..writeln()
    ..write('편하게 연락 주세요.');
  return ListingDraft(
    title: '${item.name} 팝니다${item.condition.contains('작동') ? ' (작동 잘 됨)' : ''}',
    body: body.toString(),
    category: info.marketCategory,
    priceLow: lo,
    priceHigh: hi,
  );
}
