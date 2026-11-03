import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../core/log/app_logger.dart';
import '../core/vault/vault.dart';
import 'services.dart';

const appVersion = '1.1.0';

Future<AppServices> createPlatformServices() async {
  final support = await getApplicationSupportDirectory();
  final dataDir = Directory(p.join(support.path, 'vault_app'));
  await dataDir.create(recursive: true);
  final scratch = Directory(p.join(dataDir.path, 'tmp'));
  await scratch.create(recursive: true);
  return AppServices(
    dataDir: dataDir,
    scratchDir: scratch,
    keyStore: SecureDeviceKeyStore(),
    biometric: LocalAuthGate(),
    clipboard: SystemClipboard(),
    notifications: LocalNotifications(),
    speech: DeviceSpeech(),
    tts: DeviceTts(),
    files: PlatformFiles(),
    launcher: UrlLauncherPort(),
    secureScreen: AndroidSecureScreen(),
    haptics: SystemHaptics(),
    installer: PlatformInstaller(),
    launcherStyle: AndroidLauncherStyle(),
    appVersion: appVersion,
  );
}

class SecureDeviceKeyStore implements DeviceKeyStore {
  final _s = const FlutterSecureStorage();
  String _k(String id) => 'device_key_$id';

  @override
  Future<void> delete(String profileId) => _s.delete(key: _k(profileId));

  @override
  Future<List<int>?> read(String profileId) async {
    final v = await _s.read(key: _k(profileId));
    return v == null ? null : base64Decode(v);
  }

  @override
  Future<void> write(String profileId, List<int> key) =>
      _s.write(key: _k(profileId), value: base64Encode(key));
}

class LocalAuthGate implements BiometricGate {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      if (!(Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows)) {
        return false;
      }
      return await _auth.isDeviceSupported();
    } catch (e) {
      log.warn('생체 인증 확인 실패: ${e.runtimeType}');
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason);
    } catch (e) {
      log.warn('생체 인증 실패: ${e.runtimeType}');
      return false;
    }
  }
}

class SystemClipboard implements ClipboardPort {
  @override
  Future<String?> read() async {
    try {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {}
  }
}

class LocalNotifications implements NotificationPort {
  final _p = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _title = '구독·계정 비서';
  static const _body = '확인할 항목이 있어요. 앱을 열어 확인해 주세요.';

  @override
  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      _ready =
          await _p.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              macOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
              linux: LinuxInitializationSettings(defaultActionName: '열기'),
              windows: WindowsInitializationSettings(
                appName: '구독·계정 비서',
                appUserModelId: 'Kwanhark.AccountVault',
                guid: '6f1d7a3e-6c1b-4d2a-9b7e-1c2d3e4f5a6b',
              ),
            ),
          ) ??
          false;
    } catch (e) {
      log.warn('알림 준비 실패: ${e.runtimeType}');
      _ready = false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      if (Platform.isAndroid) {
        final a = _p
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return await a?.requestNotificationsPermission() ?? false;
      }
      if (Platform.isMacOS) {
        final m = _p
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >();
        return await m?.requestPermissions(alert: true, sound: true) ?? false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> scheduleReminders(List<DateTime> times) async {
    if (!_ready) return;
    try {
      await _p.cancelAll();
      if (!(Platform.isAndroid ||
          Platform.isMacOS ||
          Platform.isIOS ||
          Platform.isWindows)) {
        return; // 리눅스는 예약 알림 미지원 → 앱을 열면 밀린 알림으로 보여 줌
      }
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          '만료·결제 알림',
          channelDescription: '크레딧 만료와 구독 결제 전에 알려 드려요',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.secret,
        ),
        macOS: DarwinNotificationDetails(),
      );
      var id = 1;
      for (final t in times) {
        await _p.zonedSchedule(
          id: id++,
          scheduledDate: tz.TZDateTime.from(t, tz.UTC),
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: _title,
          body: _body,
        );
      }
    } catch (e) {
      log.warn('알림 예약 실패: ${e.runtimeType}');
    }
  }

  @override
  Future<void> cancelAll() async {
    try {
      if (_ready) await _p.cancelAll();
    } catch (_) {}
  }
}

class DeviceSpeech implements SpeechPort {
  final _s = SpeechToText();
  bool? _ok;

  bool get _platformSupported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;

  @override
  Future<bool> isAvailable() async {
    if (!_platformSupported) return false;
    if (_ok != null) return _ok!;
    try {
      _ok = await _s.initialize(onError: (e) => log.warn('음성 인식 오류'));
    } catch (e) {
      log.warn('음성 인식 준비 실패: ${e.runtimeType}');
      _ok = false;
    }
    return _ok!;
  }

  @override
  Future<bool> listen({
    required void Function(String text) onPartial,
    required void Function(String text) onFinal,
  }) async {
    if (!await isAvailable()) return false;
    try {
      await _s.listen(
        onResult: (r) {
          if (r.finalResult) {
            onFinal(r.recognizedWords);
          } else {
            onPartial(r.recognizedWords);
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: 'ko_KR',
          listenFor: const Duration(seconds: 20),
          pauseFor: const Duration(seconds: 3),
          cancelOnError: true,
        ),
      );
      return true;
    } catch (e) {
      log.warn('음성 듣기 실패: ${e.runtimeType}');
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _s.stop();
    } catch (_) {}
  }
}

class DeviceTts implements TtsPort {
  final _t = FlutterTts();
  bool? _ok;

  @override
  Future<bool> isAvailable() async {
    if (_ok != null) return _ok!;
    if (!(Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows)) {
      return _ok = false;
    }
    try {
      await _t.setLanguage('ko-KR');
      await _t.setSpeechRate(Platform.isAndroid ? 0.45 : 0.5);
      _ok = true;
    } catch (e) {
      log.warn('음성 읽기 준비 실패: ${e.runtimeType}');
      _ok = false;
    }
    return _ok!;
  }

  @override
  Future<void> speak(String text) async {
    if (!await isAvailable()) return;
    try {
      await _t.stop();
      await _t.speak(text);
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      await _t.stop();
    } catch (_) {}
  }
}

class PlatformFiles implements FilePort {
  @override
  Future<String?> saveText(String suggestedName, String content) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final dir = await getTemporaryDirectory();
        final f = File(p.join(dir.path, suggestedName));
        await f.writeAsString(content, flush: true);
        final r = await SharePlus.instance.share(
          ShareParams(files: [XFile(f.path)], title: suggestedName),
        );
        // 공유가 끝나면 임시 파일은 지운다.
        unawaited(
          Future.delayed(const Duration(minutes: 2), () async {
            if (f.existsSync()) await f.delete();
          }),
        );
        return r.status == ShareResultStatus.dismissed ? null : '공유한 위치';
      }
      final loc = await getSaveLocation(suggestedName: suggestedName);
      if (loc == null) return null;
      await File(loc.path).writeAsString(content, flush: true);
      return loc.path;
    } catch (e) {
      log.warn('파일 저장 실패: ${e.runtimeType}');
      return null;
    }
  }

  @override
  Future<String?> openText({List<String> extensions = const []}) async {
    try {
      final f = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(
            label: '파일',
            extensions: extensions.isEmpty ? null : extensions,
            uniformTypeIdentifiers: const ['public.data'],
          ),
        ],
      );
      if (f == null) return null;
      final bytes = await f.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      log.warn('파일 열기 실패: ${e.runtimeType}');
      return null;
    }
  }
}

class UrlLauncherPort implements LauncherPort {
  @override
  Future<bool> open(Uri uri) async {
    try {
      if (!(uri.scheme == 'https' || uri.scheme == 'http')) return false;
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

class AndroidSecureScreen implements SecureScreenPort {
  static const _ch = MethodChannel('account_vault/secure_screen');

  @override
  Future<void> setSecure(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('setSecure', on);
    } catch (_) {}
  }
}

class SystemHaptics implements HapticPort {
  @override
  void tap() {
    if (kIsWeb) return;
    HapticFeedback.lightImpact();
  }

  @override
  void success() {
    if (kIsWeb) return;
    HapticFeedback.mediumImpact();
  }
}

class PlatformInstaller implements InstallerPort {
  static const _ch = MethodChannel('account_vault/installer');

  @override
  String get os => Platform.operatingSystem;

  @override
  Future<Directory> downloadDir() async {
    Directory base;
    if (Platform.isAndroid || Platform.isIOS) {
      base = Directory(p.join((await getTemporaryDirectory()).path, 'updates'));
    } else {
      base = await getDownloadsDirectory() ?? await getTemporaryDirectory();
    }
    await base.create(recursive: true);
    return base;
  }

  @override
  Future<String> install(File file) async {
    try {
      if (Platform.isAndroid) {
        final r = await _ch.invokeMethod<String>('installApk', file.path);
        return r == 'need_permission'
            ? '"이 출처 허용"을 켠 뒤 다시 "설치"를 눌러 주세요.'
            : '설치 화면에서 "업데이트"를 눌러 주세요. 금고는 그대로 남아요.';
      }
      if (Platform.isWindows) {
        await Process.start(
          file.path,
          const [],
          mode: ProcessStartMode.detached,
        );
        // 설치 프로그램이 앱을 덮어쓸 수 있도록 앱을 닫는다(금고 파일은 %APPDATA% 에 그대로).
        Future.delayed(const Duration(seconds: 2), () => exit(0));
        return '설치 프로그램을 열었어요. 앱이 잠시 후 닫혀요.';
      }
      // 맥·리눅스: 보안 상자(샌드박스) 때문에 앱이 스스로를 바꿀 수 없어 내려받은 폴더를 연다.
      await launchUrl(Uri.directory(file.parent.path));
      return Platform.isMacOS
          ? '내려받은 폴더를 열었어요. 압축을 풀고 새 앱을 "응용 프로그램" 폴더로 끌어 기존 앱을 바꿔 주세요.'
          : '내려받은 폴더를 열었어요. 압축을 풀어 기존 앱 폴더를 바꿔 주세요.';
    } catch (e) {
      log.warn('설치 시작 실패: ${e.runtimeType}');
      return '설치를 시작하지 못했어요. 내려받은 파일: ${file.path}';
    }
  }
}

class AndroidLauncherStyle implements LauncherStylePort {
  static const _ch = MethodChannel('account_vault/launcher');

  @override
  Future<bool> setStyle(String style) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('setStyle', style) ?? false;
    } catch (e) {
      log.warn('런처 모양 바꾸기 실패: ${e.runtimeType}');
      return false;
    }
  }
}
