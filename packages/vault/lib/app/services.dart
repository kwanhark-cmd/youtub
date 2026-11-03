import 'dart:async';
import 'dart:io';

import '../core/vault/vault.dart';

/// 운영체제 기능을 바꿔 끼울 수 있게 모은 창구들. 테스트에서는 가짜를 넣는다.
/// 모든 구현은 실패해도 예외를 밖으로 던지지 않고 "안 됨"으로 알려야 한다.

abstract class ClipboardPort {
  Future<String?> read();
  Future<void> write(String text);
}

abstract class NotificationPort {
  Future<void> init();
  Future<bool> requestPermission();

  /// 예약을 모두 지우고 새로 건다. 문구에는 개인 정보를 넣지 않는다.
  Future<void> scheduleReminders(List<DateTime> times);
  Future<void> cancelAll();
}

abstract class SpeechPort {
  /// 이 기기에서 음성 인식을 쓸 수 있는지(마이크 권한 포함).
  Future<bool> isAvailable();

  /// 듣기 시작. 말이 끝나면 [onFinal], 듣는 중간에는 [onPartial].
  Future<bool> listen({
    required void Function(String text) onPartial,
    required void Function(String text) onFinal,
  });
  Future<void> stop();
}

abstract class TtsPort {
  Future<bool> isAvailable();
  Future<void> speak(String text);
  Future<void> stop();
}

abstract class FilePort {
  /// 글자 파일 저장. 성공하면 저장 위치(설명용) 반환, 취소·실패면 null.
  Future<String?> saveText(String suggestedName, String content);

  /// 글자 파일 열기. 취소면 null.
  Future<String?> openText({List<String> extensions});
}

abstract class LauncherPort {
  Future<bool> open(Uri uri);
}

abstract class SecureScreenPort {
  /// 화면 캡처 방지(안드로이드 FLAG_SECURE).
  Future<void> setSecure(bool on);
}

/// 새 버전 설치 파일을 넘겨 설치를 시작한다(사용자가 마지막 확인을 한다).
abstract class InstallerPort {
  /// 이 기기 종류: android / windows / macos / linux
  String get os;

  /// 내려받을 폴더.
  Future<Directory> downloadDir();

  /// 설치 시작. 사용자에게 보여 줄 안내 문구를 돌려준다.
  Future<String> install(File file);
}

/// 런처(홈 화면) 이름·아이콘 바꾸기. 안드로이드만 실제로 바뀌고, 나머지는 false.
abstract class LauncherStylePort {
  Future<bool> setStyle(String style);
}

abstract class HapticPort {
  void tap();
  void success();
}

class AppServices {
  AppServices({
    required this.dataDir,
    required this.keyStore,
    required this.biometric,
    required this.clipboard,
    required this.notifications,
    required this.speech,
    required this.tts,
    required this.files,
    required this.launcher,
    required this.secureScreen,
    required this.haptics,
    required this.installer,
    required this.launcherStyle,
    required this.appVersion,
    required this.scratchDir,
  });

  final Directory dataDir;
  final Directory scratchDir;
  final DeviceKeyStore keyStore;
  final BiometricGate biometric;
  final ClipboardPort clipboard;
  final NotificationPort notifications;
  final SpeechPort speech;
  final TtsPort tts;
  final FilePort files;
  final LauncherPort launcher;
  final SecureScreenPort secureScreen;
  final HapticPort haptics;
  final InstallerPort installer;
  final LauncherStylePort launcherStyle;
  final String appVersion;
}
