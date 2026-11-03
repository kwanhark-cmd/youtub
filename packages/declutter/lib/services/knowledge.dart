import '../data/models.dart';

/// 물건 종류별 기본 지식: 판매 카테고리, 대략 중고 시세, 분리수거 방법.
/// 연습 모드와 AI가 연결되지 않았을 때 사용합니다.
class KindInfo {
  final String kind;
  final List<String> keywords;
  final String marketCategory; // 당근마켓·번개장터 카테고리 이름
  final int priceLow;
  final int priceHigh;
  final String disposal; // 분리수거 방법
  final bool bulky; // 대형폐기물 여부
  final int bulkyFeeLow; // 대형폐기물 예상 수수료
  final int bulkyFeeHigh;
  final bool shippable; // 택배 가능
  const KindInfo({
    required this.kind,
    required this.keywords,
    required this.marketCategory,
    required this.priceLow,
    required this.priceHigh,
    required this.disposal,
    this.bulky = false,
    this.bulkyFeeLow = 0,
    this.bulkyFeeHigh = 0,
    this.shippable = true,
  });
}

const kinds = <KindInfo>[
  KindInfo(
    kind: '소형 가전',
    keywords: ['커피', '머신', '주전자', '포트', '토스터', '믹서', '드라이기', '선풍기', '전자레인지', '밥솥', '청소기', '다리미', '가습기', '에어프라이어', '전기'],
    marketCategory: '생활가전',
    priceLow: 10000,
    priceHigh: 60000,
    disposal: '작은 전자제품은 주민센터·아파트의 "소형 폐가전 수거함"에 넣거나, 5개 이상이면 폐가전 무상 방문수거(전화·인터넷 신청)를 이용하세요.',
  ),
  KindInfo(
    kind: '대형 가전',
    keywords: ['냉장고', '세탁기', '에어컨', 'TV', '티비', '텔레비전', '건조기', '김치냉장고', '식기세척기'],
    marketCategory: '생활가전',
    priceLow: 50000,
    priceHigh: 300000,
    disposal: '대형 가전은 "폐가전제품 무상 방문수거 서비스"로 무료 수거가 됩니다. 인터넷이나 전화로 신청하세요.',
    shippable: false,
  ),
  KindInfo(
    kind: '가구',
    keywords: ['의자', '책상', '소파', '침대', '매트리스', '옷장', '서랍', '장롱', '식탁', '책장', '선반', '테이블', '협탁'],
    marketCategory: '가구/인테리어',
    priceLow: 10000,
    priceHigh: 150000,
    disposal: '가구는 대형폐기물입니다. 구청에 신고하고 수수료를 낸 뒤 스티커(신고번호)를 붙여 지정 장소에 내놓으세요.',
    bulky: true,
    bulkyFeeLow: 3000,
    bulkyFeeHigh: 30000,
    shippable: false,
  ),
  KindInfo(
    kind: '옷·신발·가방',
    keywords: ['옷', '셔츠', '바지', '치마', '코트', '패딩', '신발', '운동화', '구두', '가방', '모자', '원피스', '자켓'],
    marketCategory: '의류',
    priceLow: 3000,
    priceHigh: 30000,
    disposal: '깨끗한 옷·신발·가방은 의류수거함에 넣으세요. 찢어지거나 더러운 것은 종량제 봉투에 버립니다.',
  ),
  KindInfo(
    kind: '책·문구',
    keywords: ['책', '잡지', '앨범', '노트', '문제집', '교재', '만화', '공책'],
    marketCategory: '도서',
    priceLow: 1000,
    priceHigh: 15000,
    disposal: '책은 비닐 표지·스프링을 떼고 종이류로 묶어 분리배출하세요.',
  ),
  KindInfo(
    kind: '주방용품',
    keywords: ['냄비', '프라이팬', '그릇', '접시', '컵', '수저', '칼', '도마', '텀블러', '머그', '컵', '용기', '찻잔'],
    marketCategory: '생활/주방',
    priceLow: 2000,
    priceHigh: 30000,
    disposal: '금속 냄비·프라이팬은 고철류, 유리그릇은 유리류로 배출하세요. 깨진 유리·도자기는 신문지에 싸서 "불연성 마대"에 버립니다.',
  ),
  KindInfo(
    kind: '디지털 기기',
    keywords: ['휴대폰', '핸드폰', '스마트폰', '노트북', '태블릿', '컴퓨터', '모니터', '카메라', '이어폰', '키보드', '마우스', '게임기', '스피커'],
    marketCategory: '디지털기기',
    priceLow: 20000,
    priceHigh: 300000,
    disposal: '휴대폰·노트북은 개인정보를 꼭 지운 뒤 주민센터 수거함이나 폐가전 무상 수거를 이용하세요.',
  ),
  KindInfo(
    kind: '장난감·유아용품',
    keywords: ['장난감', '인형', '블록', '레고', '유모차', '카시트', '아기', '보행기'],
    marketCategory: '유아동',
    priceLow: 3000,
    priceHigh: 50000,
    disposal: '플라스틱 장난감은 재질이 섞여 있으면 종량제 봉투에, 큰 것(유모차 등)은 대형폐기물로 신고하세요.',
  ),
  KindInfo(
    kind: '운동·취미',
    keywords: ['자전거', '운동', '아령', '요가', '골프', '캠핑', '텐트', '악기', '기타', '낚시', '러닝머신'],
    marketCategory: '스포츠/레저',
    priceLow: 5000,
    priceHigh: 100000,
    disposal: '자전거·러닝머신 같은 큰 물건은 대형폐기물로 신고하세요. 작은 운동용품은 재질에 따라 분리배출합니다.',
    bulky: true,
    bulkyFeeLow: 2000,
    bulkyFeeHigh: 15000,
  ),
  KindInfo(
    kind: '추억 물건',
    keywords: ['편지', '사진', '상장', '트로피', '기념품', '선물', '일기', '졸업'],
    marketCategory: '기타 중고물품',
    priceLow: 0,
    priceHigh: 5000,
    disposal: '사진과 사연을 앱에 남긴 뒤 버리세요("디지털로 남기고 버리기"). 종이는 종이류, 나머지는 재질에 따라 배출합니다.',
  ),
];

const _etc = KindInfo(
  kind: '기타',
  keywords: [],
  marketCategory: '기타 중고물품',
  priceLow: 1000,
  priceHigh: 20000,
  disposal: '재질(종이·플라스틱·금속·유리)을 확인해 분리배출하고, 섞여 있으면 종량제 봉투에 버리세요. 크면 대형폐기물로 신고합니다.',
);

KindInfo kindInfoFor(String name, [String kind = '']) {
  final text = '$name $kind';
  for (final k in kinds) {
    if (k.kind == kind) return k;
  }
  for (final k in kinds) {
    if (k.keywords.any(text.contains)) return k;
  }
  return _etc;
}

/// 고장·파손 같은 말이 있으면 폐기 쪽, 잘 작동·새것이면 판매 쪽
Decision ruleSuggest(Item item) {
  final t = '${item.name} ${item.condition} ${item.description} ${item.story}';
  if (RegExp(r'매일|자주|요즘 씀|지금 씀|쓰고 있').hasMatch(t)) return Decision.use;
  if (RegExp(r'고장|파손|깨짐|깨졌|찢어|낡|녹슬|곰팡이|안 됨|안됨|작동 안').hasMatch(t)) return Decision.discard;
  if (RegExp(r'새것|미개봉|잘 작동|깨끗|거의 안 씀|한 번도').hasMatch(t)) return Decision.sell;
  final info = kindInfoFor(item.name, item.kind);
  if (info.kind == '추억 물건') return Decision.discard;
  return info.priceHigh >= 10000 ? Decision.sell : Decision.discard;
}

String ruleReason(Decision d) => switch (d) {
  Decision.use => '자주 쓰는 물건으로 보여요. 지금 쓰는 것으로 두세요.',
  Decision.sell => '아직 쓸 만해 보여요. 팔면 다른 사람이 잘 쓸 수 있어요.',
  Decision.discard => '팔기 어렵거나 오래돼 보여요. 비우는 것을 추천해요.',
};

/// 애매할 때 결정을 돕는 짧은 질문 (예라고 하면 해당 분류 쪽으로)
class HelpQuestion {
  final String text;
  final Decision ifYes;
  final Decision ifNo;
  const HelpQuestion(this.text, this.ifYes, this.ifNo);
}

const helpQuestions = [
  HelpQuestion('최근 1년 안에 이 물건을 쓴 적이 있나요?', Decision.use, Decision.sell),
  HelpQuestion('지금 똑같은 것을 다시 살 건가요?', Decision.use, Decision.sell),
  HelpQuestion('고장 나거나 낡지 않고 깨끗한가요?', Decision.sell, Decision.discard),
];

/// 질문 답(예=true)으로 결정. 가장 많이 나온 쪽.
Decision decideFromAnswers(List<bool> answers) {
  final votes = <Decision, int>{};
  for (var i = 0; i < answers.length && i < helpQuestions.length; i++) {
    final q = helpQuestions[i];
    final d = answers[i] ? q.ifYes : q.ifNo;
    votes[d] = (votes[d] ?? 0) + 1;
  }
  // 첫 질문(1년 안에 씀)에 "예"면 지금 쓰는 것이 우선
  if (answers.isNotEmpty && answers[0] && (votes[Decision.use] ?? 0) >= 1 && answers.length > 1 && answers[1]) {
    return Decision.use;
  }
  if (answers.length >= 3 && !answers[2]) return Decision.discard;
  final sorted = votes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return sorted.isEmpty ? Decision.sell : sorted.first.key;
}
