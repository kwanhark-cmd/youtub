import '../services/secret_store.dart';
import '../theme/app_theme.dart';
import 'repository.dart';

/// 기기 전체 설정 (사용자 0번에 저장)
class GlobalSettings {
  TextSizeChoice textSize;
  ThemeModeChoice theme;
  bool reduceMotion;
  bool haptics;
  bool sound;
  bool onboarded;
  int? currentUserId;

  /// 앱이 본 가장 늦은 시각. 기기 시간이 뒤로 가도 날짜 계산이 꼬이지 않게 함.
  DateTime? latestSeen;
  String appName; // 표시 이름 (홈·창 제목·알림)
  String icon; // 앱 안 아이콘: box, house, recycle, sparkle, photo
  String? iconPhoto; // 사용자 사진 아이콘 (앱 폴더 기준 경로)
  String colorTheme; // ocean, forest, sunset, grape
  String? lastUpdateCheck; // yyyy-m-d
  String? latestVersion; // 새로 나온 버전 (없으면 null)
  String latestNotes;

  GlobalSettings({
    this.textSize = TextSizeChoice.normal,
    this.theme = ThemeModeChoice.light,
    this.reduceMotion = false,
    this.haptics = true,
    this.sound = true,
    this.onboarded = false,
    this.currentUserId,
    this.latestSeen,
    this.appName = defaultAppName,
    this.icon = 'box',
    this.iconPhoto,
    this.colorTheme = 'ocean',
    this.lastUpdateCheck,
    this.latestVersion,
    this.latestNotes = '',
  });

  static const defaultAppName = '비우기 비서';

  static Future<GlobalSettings> load(Repository r) async {
    final m = await r.allSettings(Repository.globalUser);
    T pick<T extends Enum>(List<T> values, String? s, T def) => values.firstWhere((v) => v.name == s, orElse: () => def);
    return GlobalSettings(
      textSize: pick(TextSizeChoice.values, m['textSize'], TextSizeChoice.normal),
      theme: pick(ThemeModeChoice.values, m['theme'], ThemeModeChoice.light),
      reduceMotion: m['reduceMotion'] == '1',
      haptics: m['haptics'] != '0',
      sound: m['sound'] != '0',
      onboarded: m['onboarded'] == '1',
      currentUserId: int.tryParse(m['currentUserId'] ?? ''),
      latestSeen: int.tryParse(m['latestSeen'] ?? '') == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse(m['latestSeen']!)),
    );
  }

  Future<void> save(Repository r) async {
    final u = Repository.globalUser;
    await r.setSetting(u, 'textSize', textSize.name);
    await r.setSetting(u, 'theme', theme.name);
    await r.setSetting(u, 'reduceMotion', reduceMotion ? '1' : '0');
    await r.setSetting(u, 'haptics', haptics ? '1' : '0');
    await r.setSetting(u, 'sound', sound ? '1' : '0');
    await r.setSetting(u, 'onboarded', onboarded ? '1' : '0');
    await r.setSetting(u, 'currentUserId', currentUserId?.toString());
    await r.setSetting(u, 'latestSeen', latestSeen?.millisecondsSinceEpoch.toString());
    await r.setSetting(u, 'appName', appName);
    await r.setSetting(u, 'icon', icon);
    await r.setSetting(u, 'iconPhoto', iconPhoto ?? '');
    await r.setSetting(u, 'colorTheme', colorTheme);
    await r.setSetting(u, 'lastUpdateCheck', lastUpdateCheck);
    await r.setSetting(u, 'latestVersion', latestVersion ?? '');
    await r.setSetting(u, 'latestNotes', latestNotes);
  }
}

/// 사용자별 설정
class UserSettings {
  String sido; // 시·도
  String sigungu; // 시·군·구
  String aiProvider; // practice, claude
  String apiKey; // 기기 안에만 저장, 백업·로그에 넣지 않음
  double monthlyLimitUsd;
  double krwPerUsd;
  bool sendPhotosToAi; // 사진을 외부 AI로 보내도 되는지 (사용자 동의)
  bool ttsOn;
  double ttsRate; // 0.3 ~ 0.7
  bool voiceInputOn;
  int dailyHour; // 매일 알림 시각
  bool dailyOn;
  bool keepOriginals; // 원본 사진 따로 보관
  int priceDropDays;
  int priceDropPercent;
  String googleClientId;
  String googleClientSecret; // 보안 저장소
  String googleRefreshToken; // 보안 저장소
  String gmailSubject; // 제미나이 정리 메일 제목 규칙
  String? gmailConnectedAt;

  UserSettings({
    this.sido = '',
    this.sigungu = '',
    this.aiProvider = 'practice',
    this.apiKey = '',
    this.monthlyLimitUsd = 5,
    this.krwPerUsd = 1400,
    this.sendPhotosToAi = false,
    this.ttsOn = true,
    this.ttsRate = 0.45,
    this.voiceInputOn = true,
    this.dailyHour = 8,
    this.dailyOn = true,
    this.keepOriginals = false,
    this.priceDropDays = 14,
    this.priceDropPercent = 10,
    this.googleClientId = '',
    this.googleClientSecret = '',
    this.googleRefreshToken = '',
    this.gmailSubject = defaultGmailSubject,
    this.gmailConnectedAt,
  });

  static const defaultGmailSubject = '[비우기 정리]';
  bool get gmailReady => googleClientId.trim().isNotEmpty && googleClientSecret.trim().isNotEmpty;
  bool get gmailConnected => gmailReady && googleRefreshToken.isNotEmpty;

  bool get aiConnected => aiProvider != 'practice' && apiKey.trim().isNotEmpty;
  String get regionLabel => [sido, sigungu].where((s) => s.isNotEmpty).join(' ');

  /// [secrets]: 운영체제 보안 저장소. 예전 버전이 DB에 넣어 둔 AI 열쇠는 여기서 1회 옮깁니다.
  static Future<UserSettings> load(Repository r, int userId, SecretStore secrets) async {
    final m = await r.allSettings(userId);
    final old = m['apiKey'] ?? '';
    if (old.isNotEmpty) {
      await secrets.write(apiKeyName(userId), old);
      await r.setSetting(userId, 'apiKey', null);
    }
    double d(String k, double def) => double.tryParse(m[k] ?? '') ?? def;
    int i(String k, int def) => int.tryParse(m[k] ?? '') ?? def;
    return UserSettings(
      sido: m['sido'] ?? '',
      sigungu: m['sigungu'] ?? '',
      aiProvider: m['aiProvider'] ?? 'practice',
      apiKey: await secrets.read(apiKeyName(userId)) ?? '',
      monthlyLimitUsd: d('monthlyLimitUsd', 5),
      krwPerUsd: d('krwPerUsd', 1400),
      sendPhotosToAi: m['sendPhotosToAi'] == '1',
      ttsOn: m['ttsOn'] != '0',
      ttsRate: d('ttsRate', 0.45),
      voiceInputOn: m['voiceInputOn'] != '0',
      dailyHour: i('dailyHour', 8),
      dailyOn: m['dailyOn'] != '0',
      keepOriginals: m['keepOriginals'] == '1',
      priceDropDays: i('priceDropDays', 14),
      priceDropPercent: i('priceDropPercent', 10),
      googleClientId: m['googleClientId'] ?? '',
      googleClientSecret: await secrets.read(googleSecretName(userId)) ?? '',
      googleRefreshToken: await secrets.read(googleRefreshName(userId)) ?? '',
      gmailSubject: (m['gmailSubject'] ?? '').trim().isEmpty ? defaultGmailSubject : m['gmailSubject']!,
      gmailConnectedAt: m['gmailConnectedAt'],
    );
  }

  Future<void> save(Repository r, int userId, SecretStore secrets) async {
    await secrets.write(apiKeyName(userId), apiKey.trim());
    await secrets.write(googleSecretName(userId), googleClientSecret.trim());
    await secrets.write(googleRefreshName(userId), googleRefreshToken);
    final values = <String, String>{
      'sido': sido,
      'sigungu': sigungu,
      'aiProvider': aiProvider,
      'monthlyLimitUsd': '$monthlyLimitUsd',
      'krwPerUsd': '$krwPerUsd',
      'sendPhotosToAi': sendPhotosToAi ? '1' : '0',
      'ttsOn': ttsOn ? '1' : '0',
      'ttsRate': '$ttsRate',
      'voiceInputOn': voiceInputOn ? '1' : '0',
      'dailyHour': '$dailyHour',
      'dailyOn': dailyOn ? '1' : '0',
      'keepOriginals': keepOriginals ? '1' : '0',
      'priceDropDays': '$priceDropDays',
      'priceDropPercent': '$priceDropPercent',
      'googleClientId': googleClientId.trim(),
      'gmailSubject': gmailSubject,
      'gmailConnectedAt': gmailConnectedAt ?? '',
    };
    for (final e in values.entries) {
      await r.setSetting(userId, e.key, e.value);
    }
  }
}

/// 백업 파일에 넣지 않는 설정 키 (AI 키)
const secretSettingKeys = {'apiKey'};

/// 비밀 값이 DB에 들어 있을 때의 키 접두사 (보안 저장소를 못 쓰는 기기). 백업에서 뺌.
bool isSecretSettingKey(String key) => secretSettingKeys.contains(key) || key.startsWith('secret_');
