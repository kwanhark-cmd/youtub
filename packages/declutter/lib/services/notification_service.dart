import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/logger.dart';

/// 기기 알림 (매일 아침 "오늘 하나만 정해 보세요").
/// 절전 등으로 알림이 안 와도 앱을 열면 앱 안 "밀린 알림"에서 볼 수 있습니다.
abstract class Notifier {
  Future<void> init();
  Future<bool> requestPermission();
  Future<void> scheduleDaily(int hour, String title, String body);
  Future<void> cancelDaily();
  Future<void> showNow(String title, String body);
}

class DeviceNotifier implements Notifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ok = false;
  static const _dailyId = 1;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails('daily', '하루 한 번 비우기', channelDescription: '매일 아침 물건 하나 정하기 알림', importance: Importance.high),
    macOS: DarwinNotificationDetails(),
    iOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  @override
  Future<void> init() async {
    if (kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
      }
      _ok =
          await _plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              macOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
              iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
              linux: LinuxInitializationSettings(defaultActionName: '열기'),
              windows: WindowsInitializationSettings(
                appName: '집안 물건 비우기 비서',
                appUserModelId: 'com.binugi.binugi',
                guid: '6f1c2b8e-3f7a-4c1d-9b2e-5a8d7c6e4f31',
              ),
            ),
          ) ??
          false;
    } catch (e) {
      log.warn('알림 준비 실패: $e');
      _ok = false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_ok) return false;
    try {
      if (Platform.isAndroid) {
        return await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission() ?? false;
      }
      if (Platform.isMacOS) {
        return await _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, sound: true) ??
            false;
      }
      if (Platform.isIOS) {
        return await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, sound: true) ?? false;
      }
      return true;
    } catch (e) {
      log.warn('알림 권한 요청 실패: $e');
      return false;
    }
  }

  @override
  Future<void> scheduleDaily(int hour, String title, String body) async {
    if (!_ok) return;
    try {
      final now = tz.TZDateTime.now(tz.local);
      var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      await _plugin.cancel(id: _dailyId);
      await _plugin.zonedSchedule(
        id: _dailyId,
        scheduledDate: at,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      // 윈도우·리눅스 등 예약 알림을 못 하는 곳: 앱을 열 때 밀린 알림으로 대신
      log.info('예약 알림 사용 불가: $e');
    }
  }

  @override
  Future<void> cancelDaily() async {
    if (!_ok) return;
    try {
      await _plugin.cancel(id: _dailyId);
    } catch (_) {}
  }

  @override
  Future<void> showNow(String title, String body) async {
    if (!_ok) return;
    try {
      await _plugin.show(id: 2, title: title, body: body, notificationDetails: _details);
    } catch (e) {
      log.info('알림 표시 실패: $e');
    }
  }
}

class SilentNotifier implements Notifier {
  final List<String> shown = [];
  int? scheduledHour;
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> scheduleDaily(int hour, String title, String body) async => scheduledHour = hour;
  @override
  Future<void> cancelDaily() async => scheduledHour = null;
  @override
  Future<void> showNow(String title, String body) async => shown.add(title);
}
