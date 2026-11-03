import '../../core/db.dart';

/// 사용자별 설정. 사용자 자료 DB 의 settings 표에 저장된다.
/// (API 키·토큰 같은 민감 정보는 여기에 두지 않고 SecretStore 에 둔다.)
class UserSettings {
  UserSettings(this.db);
  final AppDatabase db;

  T _get<T>(String k, T def) => db.getSetting<T>(k) ?? def;
  double _getD(String k, double def) {
    final v = db.getSetting<num>(k);
    return v == null ? def : v.toDouble();
  }

  int _getI(String k, int def) {
    final v = db.getSetting<num>(k);
    return v == null ? def : v.toInt();
  }

  // 화면
  double get textScale => _getD('textScale', 1.0);
  set textScale(double v) => db.setSetting('textScale', v.clamp(0.8, 2.0));
  String get language => _get('language', 'ko');
  set language(String v) => db.setSetting('language', v);
  bool get onboardingDone => _get('onboardingDone', false);
  set onboardingDone(bool v) => db.setSetting('onboardingDone', v);

  // 앱 꾸미기
  /// 앱 이름 (빈 값이면 기본 이름)
  String get appDisplayName => _get('appDisplayName', '');
  set appDisplayName(String v) => db.setSetting('appDisplayName', v.trim());

  /// 아이콘: 'blue' | 'purple' | 'green' | 'orange' | 'pink' | 'custom'
  String get appIcon => _get('appIcon', 'blue');
  set appIcon(String v) => db.setSetting('appIcon', v);

  /// 'basic' | 'ocean' | 'forest' | 'sunset'
  String get colorTheme => _get('colorTheme', 'basic');
  set colorTheme(String v) => db.setSetting('colorTheme', v);

  /// 실제 채널이 연결된 뒤에도 연습용 가짜 채널을 보여 줄지
  bool get showPracticeData => _get('showPracticeData', false);
  set showPracticeData(bool v) => db.setSetting('showPracticeData', v);

  // 보기 (화면 개선)
  /// 'system' | 'light' | 'dark'
  String get themeMode => _get('themeMode', 'system');
  set themeMode(String v) => db.setSetting('themeMode', v);
  bool get highContrast => _get('highContrast', false);
  set highContrast(bool v) => db.setSetting('highContrast', v);
  bool get reduceMotion => _get('reduceMotion', false);
  set reduceMotion(bool v) => db.setSetting('reduceMotion', v);
  bool get haptics => _get('haptics', true);
  set haptics(bool v) => db.setSetting('haptics', v);
  bool get clickSound => _get('clickSound', false);
  set clickSound(bool v) => db.setSetting('clickSound', v);
  List<String> get seenTips => (db.getSetting<List<dynamic>>('seenTips') ?? const []).cast<String>();
  bool tipSeen(String id) => seenTips.contains(id);
  void markTipSeen(String id) => db.setSetting('seenTips', {...seenTips, id}.toList());
  void resetTips() => db.setSetting('seenTips', <String>[]);

  // 처음 사용한 날 (첫 한 달 수정 제한에 사용)
  String? get firstUseDay => db.getSetting<String>('firstUseDay');
  void ensureFirstUseDay(DateTime now) {
    if (firstUseDay == null) db.setSetting('firstUseDay', dayKey(now));
  }

  bool isFirstMonth(DateTime now) {
    final f = firstUseDay;
    if (f == null) return true;
    final start = DateTime.parse(f);
    return now.difference(start).inDays < 30;
  }

  // 음성
  bool get ttsEnabled => _get('ttsEnabled', true);
  set ttsEnabled(bool v) => db.setSetting('ttsEnabled', v);
  double get ttsRate => _getD('ttsRate', 0.5);
  set ttsRate(double v) => db.setSetting('ttsRate', v.clamp(0.1, 1.0));

  /// 'device'(기기 내장, 기본) | 'external'(외부 음성 서비스, 준비 중)
  String get voiceEngine => _get('voiceEngine', 'device');
  set voiceEngine(String v) => db.setSetting('voiceEngine', v);
  bool get briefingEnabled => _get('briefingEnabled', false);
  set briefingEnabled(bool v) => db.setSetting('briefingEnabled', v);
  int get briefingHour => _getI('briefingHour', 8);
  set briefingHour(int v) => db.setSetting('briefingHour', v.clamp(0, 23));
  int get briefingMinute => _getI('briefingMinute', 0);
  set briefingMinute(int v) => db.setSetting('briefingMinute', v.clamp(0, 59));
  String? get lastBriefingDay => db.getSetting<String>('lastBriefingDay');
  set lastBriefingDay(String? v) => db.setSetting('lastBriefingDay', v);

  // AI
  String get aiProvider => _get('aiProvider', 'claude');
  set aiProvider(String v) => db.setSetting('aiProvider', v);
  String get aiModel => _get('aiModel', 'claude-opus-5-5');
  set aiModel(String v) => db.setSetting('aiModel', v);
  double get monthlyCostLimitUsd => _getD('monthlyCostLimitUsd', 10);
  set monthlyCostLimitUsd(double v) => db.setSetting('monthlyCostLimitUsd', v < 0 ? 0 : v);

  // 구글
  String get googleClientId => _get('googleClientId', '');
  set googleClientId(String v) => db.setSetting('googleClientId', v.trim());

  /// 구글 OAuth 앱이 아직 "테스트" 상태인가 (테스트 상태면 연결이 7일 뒤 만료됨)
  bool get googleAppInTesting => _get('googleAppInTesting', true);
  set googleAppInTesting(bool v) => db.setSetting('googleAppInTesting', v);

  // 유튜브
  int get quotaDailyLimit => _getI('quotaDailyLimit', 10000);
  set quotaDailyLimit(int v) => db.setSetting('quotaDailyLimit', v.clamp(100, 10000000));
  int get editsPerChannelPerDay => _getI('editsPerChannelPerDay', 2);
  set editsPerChannelPerDay(int v) => db.setSetting('editsPerChannelPerDay', v.clamp(0, 20));

  /// 실제로 적용되는 하루 수정 개수 (첫 한 달은 최대 3개).
  int effectiveEditsPerDay(DateTime now) {
    final v = editsPerChannelPerDay;
    return isFirstMonth(now) ? (v > 3 ? 3 : v) : v;
  }

  // 자동 작업 실행기 (기본 꺼짐)
  bool get runnerEnabled => _get('runnerEnabled', false);
  set runnerEnabled(bool v) => db.setSetting('runnerEnabled', v);
  int get runnerFromHour => _getI('runnerFromHour', 2);
  set runnerFromHour(int v) => db.setSetting('runnerFromHour', v.clamp(0, 23));
  int get runnerToHour => _getI('runnerToHour', 6);
  set runnerToHour(int v) => db.setSetting('runnerToHour', v.clamp(0, 24));
  String? get lastRunnerDay => db.getSetting<String>('lastRunnerDay');
  set lastRunnerDay(String? v) => db.setSetting('lastRunnerDay', v);

  // 제작 (2단계)
  int get produceDailyLimit => _getI('produceDailyLimit', 3);
  set produceDailyLimit(int v) => db.setSetting('produceDailyLimit', v.clamp(0, 20));

  /// 'description' | 'channel' | 'setting'
  String get aiLabelMethod => _get('aiLabelMethod', 'setting');
  set aiLabelMethod(String v) => db.setSetting('aiLabelMethod', v);
  List<String> get videoToolPriority =>
      (db.getSetting<List<dynamic>>('videoToolPriority') ?? ['googleVids', 'higgsfield', 'ownFile']).cast<String>();
  set videoToolPriority(List<String> v) => db.setSetting('videoToolPriority', v);
  List<String> get narrationToolPriority =>
      (db.getSetting<List<dynamic>>('narrationToolPriority') ?? ['higgsfield', 'vrew']).cast<String>();
  set narrationToolPriority(List<String> v) => db.setSetting('narrationToolPriority', v);

  // 블로그 (3단계)
  int get blogPostsPerDay => _getI('blogPostsPerDay', 1);
  set blogPostsPerDay(int v) => db.setSetting('blogPostsPerDay', v.clamp(1, 2));
}
