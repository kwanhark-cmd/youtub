import 'dart:math';

/// 금고 안에 들어가는 데이터. 모두 암호화된 상태로만 디스크에 저장된다.

String newId([Random? r]) {
  final rnd = r ?? Random.secure();
  return List.generate(
    16,
    (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
String? _iso(DateTime? d) => d?.toIso8601String();

/// 카드 번호는 끝 4자리만. 숫자만 남기고 마지막 4자리를 취한다. 4자리가 안 되면 null.
String? sanitizeCardLast4(String? input) {
  if (input == null) return null;
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) return null;
  return digits.substring(digits.length - 4);
}

enum BillingCycle {
  weekly('매주'),
  monthly('매달'),
  yearly('매년');

  const BillingCycle(this.label);
  final String label;

  static BillingCycle parse(Object? v) => BillingCycle.values.firstWhere(
    (e) => e.name == v,
    orElse: () => BillingCycle.monthly,
  );
}

enum Currency {
  krw('원'),
  usd('달러');

  const Currency(this.label);
  final String label;

  static Currency parse(Object? v) => Currency.values.firstWhere(
    (e) => e.name == v,
    orElse: () => Currency.krw,
  );
}

class Subscription {
  Subscription({
    String? id,
    required this.serviceName,
    this.category = '기타',
    required this.amount,
    this.currency = Currency.krw,
    this.cycle = BillingCycle.monthly,
    required this.nextRenewal,
    String? cardLast4,
    this.accountId,
    this.lastUsedAt,
    this.isCancelCandidate = false,
    this.isPaused = false,
    this.remindDaysBefore = 3,
    this.cancelUrl,
    this.memo = '',
    DateTime? createdAt,
  }) : id = id ?? newId(),
       cardLast4 = sanitizeCardLast4(cardLast4),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  String serviceName;
  String category;

  /// 원화는 원 단위, 달러는 센트 단위(정수)로 저장해 계산 오차를 없앤다.
  int amount;
  Currency currency;
  BillingCycle cycle;
  DateTime nextRenewal;
  String? cardLast4;
  String? accountId;
  DateTime? lastUsedAt;
  bool isCancelCandidate;
  bool isPaused;
  int remindDaysBefore;
  String? cancelUrl;
  String memo;
  final DateTime createdAt;

  set card(String? v) => cardLast4 = sanitizeCardLast4(v);

  Map<String, Object?> toJson() => {
    'id': id,
    'serviceName': serviceName,
    'category': category,
    'amount': amount,
    'currency': currency.name,
    'cycle': cycle.name,
    'nextRenewal': _iso(nextRenewal),
    'cardLast4': cardLast4,
    'accountId': accountId,
    'lastUsedAt': _iso(lastUsedAt),
    'isCancelCandidate': isCancelCandidate,
    'isPaused': isPaused,
    'remindDaysBefore': remindDaysBefore,
    'cancelUrl': cancelUrl,
    'memo': memo,
    'createdAt': _iso(createdAt),
  };

  static Subscription fromJson(Map<String, Object?> j) => Subscription(
    id: j['id'] as String?,
    serviceName: (j['serviceName'] as String?) ?? '이름 없음',
    category: (j['category'] as String?) ?? '기타',
    amount: (j['amount'] as num?)?.toInt() ?? 0,
    currency: Currency.parse(j['currency']),
    cycle: BillingCycle.parse(j['cycle']),
    nextRenewal: _date(j['nextRenewal']) ?? DateTime.now(),
    cardLast4: j['cardLast4'] as String?,
    accountId: j['accountId'] as String?,
    lastUsedAt: _date(j['lastUsedAt']),
    isCancelCandidate: (j['isCancelCandidate'] as bool?) ?? false,
    isPaused: (j['isPaused'] as bool?) ?? false,
    remindDaysBefore: (j['remindDaysBefore'] as num?)?.toInt() ?? 3,
    cancelUrl: j['cancelUrl'] as String?,
    memo: (j['memo'] as String?) ?? '',
    createdAt: _date(j['createdAt']),
  );
}

enum CreditKind {
  freeCredit('무료 크레딧'),
  bonusCredit('보너스 크레딧'),
  trial('체험판'),
  other('기타');

  const CreditKind(this.label);
  final String label;

  static CreditKind parse(Object? v) => CreditKind.values.firstWhere(
    (e) => e.name == v,
    orElse: () => CreditKind.other,
  );
}

class CreditItem {
  CreditItem({
    String? id,
    required this.serviceName,
    this.kind = CreditKind.freeCredit,
    this.amountText = '',
    required this.expiresAt,
    this.memo = '',
    this.done = false,
    this.snoozeUntil,
    DateTime? createdAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? DateTime.now();

  /// "다시 알림": 이 날짜부터 다시 알린다(만료 14일이 지나도 한 번 더).
  DateTime? snoozeUntil;

  final String id;
  String serviceName;
  CreditKind kind;
  String amountText;
  DateTime expiresAt;
  String memo;

  /// 다 썼거나 정리했으면 true(알림 안 함).
  bool done;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'serviceName': serviceName,
    'kind': kind.name,
    'amountText': amountText,
    'expiresAt': _iso(expiresAt),
    'memo': memo,
    'done': done,
    'createdAt': _iso(createdAt),
    if (snoozeUntil != null) 'snoozeUntil': _iso(snoozeUntil),
  };

  static CreditItem fromJson(Map<String, Object?> j) => CreditItem(
    id: j['id'] as String?,
    serviceName: (j['serviceName'] as String?) ?? '이름 없음',
    kind: CreditKind.parse(j['kind']),
    amountText: (j['amountText'] as String?) ?? '',
    expiresAt: _date(j['expiresAt']) ?? DateTime.now(),
    memo: (j['memo'] as String?) ?? '',
    done: (j['done'] as bool?) ?? false,
    snoozeUntil: _date(j['snoozeUntil']),
    createdAt: _date(j['createdAt']),
  );
}

class Account {
  Account({
    String? id,
    required this.serviceName,
    this.category = '기타',
    this.loginId = '',
    this.signupEmail = '',
    this.password,
    this.passwordChangedAt,
    this.purpose = '',
    this.loginUrl = '',
    this.twoFactor = false,
    this.memo = '',
    DateTime? createdAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  String serviceName;
  String category;
  String loginId;
  String signupEmail;

  /// 비밀번호. 금고 안에서만 존재하며 음성·로그·알림에는 절대 쓰지 않는다.
  String? password;
  DateTime? passwordChangedAt;

  /// 연결된 채널·용도(예: "유튜브 채널 운영용").
  String purpose;
  String loginUrl;
  bool twoFactor;
  String memo;
  final DateTime createdAt;

  bool get hasPassword => (password ?? '').isNotEmpty;

  Map<String, Object?> toJson() => {
    'id': id,
    'serviceName': serviceName,
    'category': category,
    'loginId': loginId,
    'signupEmail': signupEmail,
    'password': password,
    'passwordChangedAt': _iso(passwordChangedAt),
    'purpose': purpose,
    'loginUrl': loginUrl,
    'twoFactor': twoFactor,
    'memo': memo,
    'createdAt': _iso(createdAt),
  };

  static Account fromJson(Map<String, Object?> j) => Account(
    id: j['id'] as String?,
    serviceName: (j['serviceName'] as String?) ?? '이름 없음',
    category: (j['category'] as String?) ?? '기타',
    loginId: (j['loginId'] as String?) ?? '',
    signupEmail: (j['signupEmail'] as String?) ?? '',
    password: j['password'] as String?,
    passwordChangedAt: _date(j['passwordChangedAt']),
    purpose: (j['purpose'] as String?) ?? '',
    loginUrl: (j['loginUrl'] as String?) ?? '',
    twoFactor: (j['twoFactor'] as bool?) ?? false,
    memo: (j['memo'] as String?) ?? '',
    createdAt: _date(j['createdAt']),
  );
}

/// 사용자별 설정(금고 안에 암호화되어 저장): AI 키, 지메일 연결 등 민감한 값.
class UserPrefs {
  UserPrefs({
    this.displayName = '',
    this.aiApiKey = '',
    this.aiModel = 'claude-opus-5-5',
    this.aiMonthlyLimitWon = 3000,
    this.aiUsageMonth = '',
    this.aiUsageWon = 0,
    this.gmailClientId = '',
    this.gmailClientSecret = '',
    this.gmailRefreshToken = '',
    this.usdToKrw = 1400,
    this.breachCheckEnabled = false,
    this.unusedDays = 45,
  });

  String displayName;
  String aiApiKey;
  String aiModel;
  int aiMonthlyLimitWon;
  String aiUsageMonth;
  double aiUsageWon;
  String gmailClientId;
  String gmailClientSecret;
  String gmailRefreshToken;
  int usdToKrw;
  bool breachCheckEnabled;
  int unusedDays;

  bool get gmailConnected => gmailRefreshToken.isNotEmpty;
  bool get aiConnected => aiApiKey.isNotEmpty;

  Map<String, Object?> toJson() => {
    'displayName': displayName,
    'aiApiKey': aiApiKey,
    'aiModel': aiModel,
    'aiMonthlyLimitWon': aiMonthlyLimitWon,
    'aiUsageMonth': aiUsageMonth,
    'aiUsageWon': aiUsageWon,
    'gmailClientId': gmailClientId,
    'gmailClientSecret': gmailClientSecret,
    'gmailRefreshToken': gmailRefreshToken,
    'usdToKrw': usdToKrw,
    'breachCheckEnabled': breachCheckEnabled,
    'unusedDays': unusedDays,
  };

  static UserPrefs fromJson(Map<String, Object?> j) => UserPrefs(
    displayName: (j['displayName'] as String?) ?? '',
    aiApiKey: (j['aiApiKey'] as String?) ?? '',
    aiModel: (j['aiModel'] as String?) ?? 'claude-opus-5-5',
    aiMonthlyLimitWon: (j['aiMonthlyLimitWon'] as num?)?.toInt() ?? 3000,
    aiUsageMonth: (j['aiUsageMonth'] as String?) ?? '',
    aiUsageWon: (j['aiUsageWon'] as num?)?.toDouble() ?? 0,
    gmailClientId: (j['gmailClientId'] as String?) ?? '',
    gmailClientSecret: (j['gmailClientSecret'] as String?) ?? '',
    gmailRefreshToken: (j['gmailRefreshToken'] as String?) ?? '',
    usdToKrw: (j['usdToKrw'] as num?)?.toInt() ?? 1400,
    breachCheckEnabled: (j['breachCheckEnabled'] as bool?) ?? false,
    unusedDays: (j['unusedDays'] as num?)?.toInt() ?? 45,
  );
}

class VaultData {
  VaultData({
    List<Subscription>? subscriptions,
    List<CreditItem>? credits,
    List<Account>? accounts,
    UserPrefs? prefs,
    Set<String>? seenAlerts,
  }) : subscriptions = subscriptions ?? [],
       credits = credits ?? [],
       accounts = accounts ?? [],
       prefs = prefs ?? UserPrefs(),
       seenAlerts = seenAlerts ?? {};

  /// 데이터 구조 버전. 바꿀 때마다 올리고 migrations.dart 에 변환을 추가한다.
  static const schemaVersion = 2;

  final List<Subscription> subscriptions;
  final List<CreditItem> credits;
  final List<Account> accounts;
  final UserPrefs prefs;

  /// 이미 보여 준 알림 키(밀린 알림 계산용).
  final Set<String> seenAlerts;

  Account? accountById(String? id) {
    if (id == null) return null;
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'subscriptions': subscriptions.map((e) => e.toJson()).toList(),
    'credits': credits.map((e) => e.toJson()).toList(),
    'accounts': accounts.map((e) => e.toJson()).toList(),
    'prefs': prefs.toJson(),
    'seenAlerts': seenAlerts.toList()..sort(),
  };

  static List<Map<String, Object?>> _list(Object? v) => v is List
      ? v.whereType<Map>().map((m) => Map<String, Object?>.from(m)).toList()
      : [];

  /// 이미 최신 버전으로 변환된 JSON 을 읽는다.
  static VaultData fromJson(Map<String, Object?> j) => VaultData(
    subscriptions: _list(j['subscriptions'])
        .map(Subscription.fromJson)
        .toList(),
    credits: _list(j['credits']).map(CreditItem.fromJson).toList(),
    accounts: _list(j['accounts']).map(Account.fromJson).toList(),
    prefs: j['prefs'] is Map
        ? UserPrefs.fromJson(Map<String, Object?>.from(j['prefs'] as Map))
        : UserPrefs(),
    seenAlerts: (j['seenAlerts'] is List)
        ? (j['seenAlerts'] as List).whereType<String>().toSet()
        : {},
  );
}
