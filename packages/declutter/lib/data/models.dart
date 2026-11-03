/// 분류는 딱 세 가지. 보관·보류는 의도적으로 없습니다.
enum Decision { use, sell, discard }

extension DecisionInfo on Decision {
  String get label => switch (this) {
    Decision.use => '지금 쓰는 것',
    Decision.sell => '판매',
    Decision.discard => '폐기',
  };
  String get emoji => switch (this) {
    Decision.use => 'use',
    Decision.sell => 'sell',
    Decision.discard => 'discard',
  };
  String get code => name;
  static Decision? parse(String? s) => switch (s) {
    'use' => Decision.use,
    'sell' => Decision.sell,
    'discard' => Decision.discard,
    _ => null,
  };
}

enum SaleStatus { listing, reserved, sold }

extension SaleStatusInfo on SaleStatus {
  String get label => switch (this) {
    SaleStatus.listing => '판매중',
    SaleStatus.reserved => '예약',
    SaleStatus.sold => '판매완료',
  };
  static SaleStatus? parse(String? s) => switch (s) {
    'listing' => SaleStatus.listing,
    'reserved' => SaleStatus.reserved,
    'sold' => SaleStatus.sold,
    _ => null,
  };
}

class AppUser {
  final int id;
  final String name;
  final DateTime createdAt;
  AppUser({required this.id, required this.name, required this.createdAt});
  factory AppUser.fromMap(Map<String, Object?> m) =>
      AppUser(id: m['id'] as int, name: m['name'] as String, createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int));
}

DateTime? _dt(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);
int? _ms(DateTime? d) => d?.millisecondsSinceEpoch;

class Item {
  int? id;
  int userId;
  String name;
  String kind; // 종류
  String condition; // 상태
  String room; // 어느 방
  String spot; // 어느 자리
  String tags; // 쉼표로 구분
  String description; // 음성/글 설명
  String story; // 얽힌 사연
  String? photoPath;
  String? thumbPath;
  String? originalPath;
  String source; // photo, video, text, gemini
  Decision? decision;
  Decision? aiSuggestion;
  String aiReason;
  DateTime createdAt; // 등록일
  DateTime? decidedAt;
  // 판매
  SaleStatus? saleStatus;
  int? priceLow;
  int? priceHigh;
  int? price;
  int? initialPrice;
  DateTime? listedAt;
  DateTime? lastPriceDropAt;
  DateTime? priceDropSuggestedAt;
  int? soldPrice;
  DateTime? soldAt;
  String listingTitle;
  String listingBody;
  String listingCategory;
  bool shipping;
  DateTime? oneYearWarnedAt;
  // 폐기
  DateTime? movedFromSaleAt;
  DateTime? discardDoneAt;
  bool digitalKeep;
  DateTime? exportedAt;
  bool isPractice; // 연습 모드 결과로 만든 물건

  Item({
    this.id,
    required this.userId,
    required this.name,
    this.kind = '',
    this.condition = '',
    this.room = '',
    this.spot = '',
    this.tags = '',
    this.description = '',
    this.story = '',
    this.photoPath,
    this.thumbPath,
    this.originalPath,
    this.source = 'photo',
    this.decision,
    this.aiSuggestion,
    this.aiReason = '',
    required this.createdAt,
    this.decidedAt,
    this.saleStatus,
    this.priceLow,
    this.priceHigh,
    this.price,
    this.initialPrice,
    this.listedAt,
    this.lastPriceDropAt,
    this.priceDropSuggestedAt,
    this.soldPrice,
    this.soldAt,
    this.listingTitle = '',
    this.listingBody = '',
    this.listingCategory = '',
    this.shipping = false,
    this.oneYearWarnedAt,
    this.movedFromSaleAt,
    this.discardDoneAt,
    this.digitalKeep = false,
    this.exportedAt,
    this.isPractice = false,
  });

  bool get isDone => (decision == Decision.sell && saleStatus == SaleStatus.sold) || (decision == Decision.discard && discardDoneAt != null);

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'user_id': userId,
    'name': name,
    'kind': kind,
    'condition': condition,
    'room': room,
    'spot': spot,
    'tags': tags,
    'description': description,
    'story': story,
    'photo_path': photoPath,
    'thumb_path': thumbPath,
    'original_path': originalPath,
    'source': source,
    'decision': decision?.code,
    'ai_suggestion': aiSuggestion?.code,
    'ai_reason': aiReason,
    'created_at': _ms(createdAt),
    'decided_at': _ms(decidedAt),
    'sale_status': saleStatus?.name,
    'price_low': priceLow,
    'price_high': priceHigh,
    'price': price,
    'initial_price': initialPrice,
    'listed_at': _ms(listedAt),
    'last_price_drop_at': _ms(lastPriceDropAt),
    'price_drop_suggested_at': _ms(priceDropSuggestedAt),
    'sold_price': soldPrice,
    'sold_at': _ms(soldAt),
    'listing_title': listingTitle,
    'listing_body': listingBody,
    'listing_category': listingCategory,
    'shipping': shipping ? 1 : 0,
    'one_year_warned_at': _ms(oneYearWarnedAt),
    'moved_from_sale_at': _ms(movedFromSaleAt),
    'discard_done_at': _ms(discardDoneAt),
    'digital_keep': digitalKeep ? 1 : 0,
    'exported_at': _ms(exportedAt),
    'is_practice': isPractice ? 1 : 0,
  };

  factory Item.fromMap(Map<String, Object?> m) => Item(
    id: m['id'] as int?,
    userId: m['user_id'] as int,
    name: (m['name'] as String?) ?? '',
    kind: (m['kind'] as String?) ?? '',
    condition: (m['condition'] as String?) ?? '',
    room: (m['room'] as String?) ?? '',
    spot: (m['spot'] as String?) ?? '',
    tags: (m['tags'] as String?) ?? '',
    description: (m['description'] as String?) ?? '',
    story: (m['story'] as String?) ?? '',
    photoPath: m['photo_path'] as String?,
    thumbPath: m['thumb_path'] as String?,
    originalPath: m['original_path'] as String?,
    source: (m['source'] as String?) ?? 'photo',
    decision: DecisionInfo.parse(m['decision'] as String?),
    aiSuggestion: DecisionInfo.parse(m['ai_suggestion'] as String?),
    aiReason: (m['ai_reason'] as String?) ?? '',
    createdAt: _dt(m['created_at'])!,
    decidedAt: _dt(m['decided_at']),
    saleStatus: SaleStatusInfo.parse(m['sale_status'] as String?),
    priceLow: m['price_low'] as int?,
    priceHigh: m['price_high'] as int?,
    price: m['price'] as int?,
    initialPrice: m['initial_price'] as int?,
    listedAt: _dt(m['listed_at']),
    lastPriceDropAt: _dt(m['last_price_drop_at']),
    priceDropSuggestedAt: _dt(m['price_drop_suggested_at']),
    soldPrice: m['sold_price'] as int?,
    soldAt: _dt(m['sold_at']),
    listingTitle: (m['listing_title'] as String?) ?? '',
    listingBody: (m['listing_body'] as String?) ?? '',
    listingCategory: (m['listing_category'] as String?) ?? '',
    shipping: (m['shipping'] as int? ?? 0) == 1,
    oneYearWarnedAt: _dt(m['one_year_warned_at']),
    movedFromSaleAt: _dt(m['moved_from_sale_at']),
    discardDoneAt: _dt(m['discard_done_at']),
    digitalKeep: (m['digital_keep'] as int? ?? 0) == 1,
    exportedAt: _dt(m['exported_at']),
    isPractice: (m['is_practice'] as int? ?? 0) == 1,
  );

  Item copy() => Item.fromMap(toMap());
}

/// 앱 안 알림 기록 (절전으로 놓친 알림도 앱을 열면 보임)
class Notice {
  final int? id;
  final int userId;
  final String kind; // daily, price_drop, one_year_warn, one_year_moved, info
  final String title;
  final String body;
  final int? itemId;
  final DateTime createdAt;
  final DateTime? readAt;
  Notice({this.id, required this.userId, required this.kind, required this.title, required this.body, this.itemId, required this.createdAt, this.readAt});
  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'user_id': userId,
    'kind': kind,
    'title': title,
    'body': body,
    'item_id': itemId,
    'created_at': createdAt.millisecondsSinceEpoch,
    'read_at': readAt?.millisecondsSinceEpoch,
  };
  factory Notice.fromMap(Map<String, Object?> m) => Notice(
    id: m['id'] as int?,
    userId: m['user_id'] as int,
    kind: m['kind'] as String,
    title: m['title'] as String,
    body: m['body'] as String,
    itemId: m['item_id'] as int?,
    createdAt: _dt(m['created_at'])!,
    readAt: _dt(m['read_at']),
  );
}

class TimelapseShot {
  final int? id;
  final int userId;
  final String spot;
  final String path;
  final DateTime takenAt;
  TimelapseShot({this.id, required this.userId, required this.spot, required this.path, required this.takenAt});
  Map<String, Object?> toMap() => {if (id != null) 'id': id, 'user_id': userId, 'spot': spot, 'path': path, 'taken_at': takenAt.millisecondsSinceEpoch};
  factory TimelapseShot.fromMap(Map<String, Object?> m) =>
      TimelapseShot(id: m['id'] as int?, userId: m['user_id'] as int, spot: m['spot'] as String, path: m['path'] as String, takenAt: _dt(m['taken_at'])!);
}

/// AI가 사진에서 찾은 물건 (확정 전)
class DetectedItem {
  String name;
  String kind;
  String condition;
  Decision? suggestion;
  String reason;
  bool selected;
  String? framePath; // 영상에서 뽑은 장면
  bool practice; // 연습 모드 결과
  final String originalName; // AI가 처음 붙인 이름
  DetectedItem({
    required this.name,
    this.kind = '',
    this.condition = '',
    this.suggestion,
    this.reason = '',
    this.selected = true,
    this.framePath,
    this.practice = false,
  }) : originalName = name;
}

class ProgressStats {
  final int total;
  final int undecided;
  final int use;
  final int sell;
  final int discard;
  final int sold;
  final int discarded;
  final int income;
  final int estimatedValue; // 판매 예정 물건 가치 합계
  ProgressStats({
    required this.total,
    required this.undecided,
    required this.use,
    required this.sell,
    required this.discard,
    required this.sold,
    required this.discarded,
    required this.income,
    required this.estimatedValue,
  });
  int get done => sold + discarded;
  double get emptiedRatio {
    final target = sell + discard;
    return target == 0 ? 0 : done / target;
  }
}
