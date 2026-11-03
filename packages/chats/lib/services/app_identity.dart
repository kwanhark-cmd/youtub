import 'dart:io';

import 'package:flutter/services.dart';

import '../core/app_log.dart';

/// 앱 이름·아이콘을 운영체제에 반영합니다.
/// - 창 제목(윈도우·맥·리눅스): 앱 안에서 바로 바뀜
/// - 안드로이드: 최근 앱 화면 이름 + 런처 아이콘·이름(미리 준비한 3가지 중 하나, activity-alias)
/// 앱 식별자(패키지 이름·번들 ID)는 바꾸지 않습니다.
class AppIdentity {
  static const _window = MethodChannel('aico/window');
  static const _launcher = MethodChannel('aico/launcher');

  static Future<void> applyName(String name) async {
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        await _window.invokeMethod('setTitle', name);
      }
      if (Platform.isAndroid) {
        await SystemChrome.setApplicationSwitcherDescription(ApplicationSwitcherDescription(label: name));
      }
    } on MissingPluginException {
      // 테스트 등 창 기능이 없는 곳
    } catch (e) {
      AppLog.warn('창 제목 바꾸기 실패', {'error': e.runtimeType.toString()});
    }
  }

  /// 안드로이드 런처 아이콘·이름 바꾸기(별칭 이름). 다른 기기에서는 아무 일도 안 함.
  static Future<bool> applyLauncherIcon(String? androidAlias) async {
    if (androidAlias == null || !Platform.isAndroid) return false;
    try {
      await _launcher.invokeMethod('setAlias', androidAlias);
      return true;
    } catch (e) {
      AppLog.warn('런처 아이콘 바꾸기 실패', {'error': e.runtimeType.toString()});
      return false;
    }
  }
}
