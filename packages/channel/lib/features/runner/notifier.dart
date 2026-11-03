import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/logger.dart';

/// 알림 보내기. 권한이 없거나 지원하지 않는 기기면 조용히 넘어간다 (앱은 계속 동작).
abstract class Notifier {
  Future<bool> requestPermission();
  Future<void> show(String title, String body);
}

class DeviceNotifier implements Notifier {
  DeviceNotifier(this.logger);
  final AppLogger? logger;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _id = 0;

  Future<void> _init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          macOS: DarwinInitializationSettings(),
          iOS: DarwinInitializationSettings(),
          linux: LinuxInitializationSettings(defaultActionName: '열기'),
          windows: WindowsInitializationSettings(
            appName: '유튜브 블로그 채널 관리 비서',
            appUserModelId: 'com.channelbiseo.app',
            guid: '6f1c2c55-6b7e-4d1e-9c3a-2b8f6a1d4e10',
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      logger?.warn('알림 준비 실패: $e');
    }
  }

  @override
  Future<bool> requestPermission() async {
    await _init();
    try {
      final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (a != null) return await a.requestNotificationsPermission() ?? false;
      final m = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      if (m != null) return await m.requestPermissions(alert: true, sound: true) ?? false;
      return true;
    } catch (e) {
      logger?.warn('알림 권한 요청 실패: $e');
      return false;
    }
  }

  @override
  Future<void> show(String title, String body) async {
    await _init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _id++,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('main', '알림', importance: Importance.defaultImportance),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
      );
    } catch (e) {
      logger?.warn('알림 보내기 실패: $e');
    }
  }
}

class MemoryNotifier implements Notifier {
  final List<(String, String)> shown = [];
  bool granted = true;
  @override
  Future<bool> requestPermission() async => granted;
  @override
  Future<void> show(String title, String body) async => shown.add((title, body));
}
