import 'dart:convert';
import 'dart:io';

import '../classify/ai_provider.dart';
import '../models/models.dart';

enum FontSize { normal, large, xlarge }

extension FontSizeInfo on FontSize {
  double get scale => switch (this) {
    FontSize.normal => 1.0,
    FontSize.large => 1.25,
    FontSize.xlarge => 1.5,
  };
  String get label => switch (this) {
    FontSize.normal => '보통',
    FontSize.large => '크게',
    FontSize.xlarge => '아주 크게',
  };
}

enum ThemeChoice { system, light, dark }

extension ThemeChoiceInfo on ThemeChoice {
  String get label => switch (this) {
    ThemeChoice.system => '기기 설정 따르기',
    ThemeChoice.light => '밝게',
    ThemeChoice.dark => '어둡게',
  };
}

enum AiMode { searchOnly, claude }

/// 사용자별 설정. 파일 하나(JSON)에 저장합니다. 키 같은 비밀값은 여기 두지 않습니다.
class AppSettings {
  FontSize fontSize = FontSize.normal;
  ThemeChoice theme = ThemeChoice.system;
  bool highContrast = false;
  bool reduceMotion = false;
  bool haptics = true;
  bool sounds = true;
  bool ttsEnabled = true;
  double ttsRate = 0.5;
  String voiceEngine = 'device';
  AiMode aiMode = AiMode.searchOnly;
  String aiModel = ClaudeProvider.defaultModel;
  ShareScope shareScope = ShareScope.titlesOnly;
  bool shareConsentGiven = false;
  double monthlyCapUsd = 3.0;
  bool onboardingDone = false;
  Set<String> seenTips = {};
  Map<String, DateTime> lastExportRequest = {};
  bool exportReminder = true;
  bool exactMatch = false;
  bool similarWords = true;
  bool gmailConnected = false;

  // 1.1.0에서 추가
  static const formatVersion = 2;
  bool showSamples = false; // false: 실제 대화가 있으면 샘플 숨김
  String? displayName; // 앱 표시 이름(비우면 기본 이름)
  String iconChoice = 'robot';
  String colorTheme = 'blue';
  DateTime? lastUpdateCheck;
  String? latestVersion; // 마지막으로 확인한 새 버전
  String? gmailClientId;
  DateTime? lastGmailCheck;
  int gmailFoundCount = 0;

  Map<String, dynamic> toJson() => {
    'fontSize': fontSize.name,
    'theme': theme.name,
    'highContrast': highContrast,
    'reduceMotion': reduceMotion,
    'haptics': haptics,
    'sounds': sounds,
    'ttsEnabled': ttsEnabled,
    'ttsRate': ttsRate,
    'voiceEngine': voiceEngine,
    'aiMode': aiMode.name,
    'aiModel': aiModel,
    'shareScope': shareScope.name,
    'shareConsentGiven': shareConsentGiven,
    'monthlyCapUsd': monthlyCapUsd,
    'onboardingDone': onboardingDone,
    'seenTips': seenTips.toList(),
    'lastExportRequest': lastExportRequest.map((k, v) => MapEntry(k, v.toIso8601String())),
    'exportReminder': exportReminder,
    'exactMatch': exactMatch,
    'similarWords': similarWords,
    'gmailConnected': gmailConnected,
    'formatVersion': formatVersion,
    'showSamples': showSamples,
    'displayName': displayName,
    'iconChoice': iconChoice,
    'colorTheme': colorTheme,
    'lastUpdateCheck': lastUpdateCheck?.toIso8601String(),
    'latestVersion': latestVersion,
    'gmailClientId': gmailClientId,
    'lastGmailCheck': lastGmailCheck?.toIso8601String(),
    'gmailFoundCount': gmailFoundCount,
  };

  static T _enum<T extends Enum>(List<T> values, Object? v, T fallback) => values.firstWhere((e) => e.name == v, orElse: () => fallback);

  static AppSettings fromJson(Map<String, dynamic> j) {
    final s = AppSettings();
    s.fontSize = _enum(FontSize.values, j['fontSize'], FontSize.normal);
    s.theme = _enum(ThemeChoice.values, j['theme'], ThemeChoice.system);
    s.highContrast = j['highContrast'] == true;
    s.reduceMotion = j['reduceMotion'] == true;
    s.haptics = j['haptics'] != false;
    s.sounds = j['sounds'] != false;
    s.ttsEnabled = j['ttsEnabled'] != false;
    s.ttsRate = (j['ttsRate'] as num?)?.toDouble() ?? 0.5;
    s.voiceEngine = (j['voiceEngine'] ?? 'device') as String;
    s.aiMode = _enum(AiMode.values, j['aiMode'], AiMode.searchOnly);
    s.aiModel = (j['aiModel'] ?? ClaudeProvider.defaultModel) as String;
    s.shareScope = _enum(ShareScope.values, j['shareScope'], ShareScope.titlesOnly);
    s.shareConsentGiven = j['shareConsentGiven'] == true;
    s.monthlyCapUsd = (j['monthlyCapUsd'] as num?)?.toDouble() ?? 3.0;
    s.onboardingDone = j['onboardingDone'] == true;
    s.seenTips = ((j['seenTips'] as List?) ?? const []).map((e) => e.toString()).toSet();
    s.lastExportRequest = ((j['lastExportRequest'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k.toString(), DateTime.tryParse(v.toString()) ?? DateTime(2000)),
    );
    s.exportReminder = j['exportReminder'] != false;
    s.exactMatch = j['exactMatch'] == true;
    s.similarWords = j['similarWords'] != false;
    s.gmailConnected = j['gmailConnected'] == true;
    // 1.0.0 설정 파일에는 아래 값이 없음 → 기본값(자동 변환)
    final dn = (j['displayName'] as String?)?.trim();
    s.showSamples = j['showSamples'] == true;
    s.displayName = (dn == null || dn.isEmpty) ? null : dn;
    s.iconChoice = (j['iconChoice'] ?? 'robot') as String;
    s.colorTheme = (j['colorTheme'] ?? 'blue') as String;
    s.lastUpdateCheck = DateTime.tryParse('${j['lastUpdateCheck'] ?? ''}');
    s.latestVersion = j['latestVersion'] as String?;
    s.gmailClientId = j['gmailClientId'] as String?;
    s.lastGmailCheck = DateTime.tryParse('${j['lastGmailCheck'] ?? ''}');
    s.gmailFoundCount = (j['gmailFoundCount'] as num?)?.toInt() ?? 0;
    return s;
  }

  static AppSettings load(File f) {
    try {
      if (f.existsSync()) return fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
    } catch (_) {}
    return AppSettings();
  }

  void save(File f) {
    f.parent.createSync(recursive: true);
    final tmp = File('${f.path}.tmp');
    tmp.writeAsStringSync(jsonEncode(toJson()));
    tmp.renameSync(f.path);
  }

  /// 한 달에 한 번 "내보내기를 요청할 때가 됐어요" 알림이 필요한 AI.
  List<AiSource> exportDue(DateTime now) {
    if (!exportReminder) return const [];
    return AiSource.values.where((s) {
      final last = lastExportRequest[s.key];
      return last == null || now.difference(last).inDays >= 30;
    }).toList();
  }
}

/// 앱 기본 이름
const defaultAppName = 'AI 대화 기록 정리 비서';
