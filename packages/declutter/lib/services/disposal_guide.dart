import '../core/format.dart';
import '../data/models.dart';
import 'knowledge.dart';

class DisposalAdvice {
  final String howTo; // 분리수거 방법
  final bool bulky;
  final String? bulkySteps; // 대형폐기물 신고 방법
  final String? feeText;
  final List<String> giveAway; // 무료 나눔·기부
  final bool memory; // 추억 물건 → 디지털로 남기고 버리기 추천
  DisposalAdvice({required this.howTo, required this.bulky, this.bulkySteps, this.feeText, required this.giveAway, required this.memory});
}

const sidoList = [
  '서울특별시',
  '부산광역시',
  '대구광역시',
  '인천광역시',
  '광주광역시',
  '대전광역시',
  '울산광역시',
  '세종특별자치시',
  '경기도',
  '강원특별자치도',
  '충청북도',
  '충청남도',
  '전북특별자치도',
  '전라남도',
  '경상북도',
  '경상남도',
  '제주특별자치도',
];

/// 물건별 폐기 방법 안내. 지역마다 다르므로 항상 구청 확인을 권합니다.
DisposalAdvice disposalAdviceFor(Item item, {String region = ''}) {
  final info = kindInfoFor(item.name, item.kind);
  final where = region.trim().isEmpty ? '사는 곳의 구청(시청·군청)' : '$region청';
  final bulky = info.bulky || RegExp(r'매트리스|소파|침대|장롱|옷장|자전거|러닝머신|책상|식탁').hasMatch(item.name);
  String? steps;
  String? fee;
  if (bulky) {
    steps =
        '1. $where 홈페이지(또는 주민센터)에서 "대형폐기물 배출 신고"를 해요.\n'
        '2. 물건 종류와 크기를 고르고 수수료를 내요.\n'
        '3. 받은 신고번호(스티커)를 물건에 붙여요.\n'
        '4. 정해진 날, 정해진 곳에 내놓아요.';
    final lo = info.bulkyFeeLow == 0 ? 3000 : info.bulkyFeeLow;
    final hi = info.bulkyFeeHigh == 0 ? 20000 : info.bulkyFeeHigh;
    fee = '예상 수수료: ${wonRange(lo, hi)} 정도 (지역·크기마다 달라요. 꼭 $where에 확인하세요)';
  }
  final give = <String>[
    '당근마켓 "나눔"으로 0원에 올리기 (글은 판매 도우미에서 복사)',
    if (info.kind == '옷·신발·가방' || info.kind == '장난감·유아용품' || info.kind == '책·문구' || info.kind == '주방용품' || info.kind == '소형 가전')
      '아름다운가게·굿윌스토어 같은 기부 가게에 기증하기 (받는 물건은 가게에 먼저 물어보세요)',
    if (info.kind == '책·문구') '동네 도서관·작은도서관에 기증 가능한지 물어보기',
    '주변 이웃·가족에게 필요한지 먼저 물어보기',
  ];
  return DisposalAdvice(
    howTo: info.disposal,
    bulky: bulky,
    bulkySteps: steps,
    feeText: fee,
    giveAway: give,
    memory: info.kind == '추억 물건' || item.story.trim().isNotEmpty,
  );
}
