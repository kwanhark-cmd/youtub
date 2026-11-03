import 'package:flutter/services.dart';

import '../core/app_log.dart';

/// 안드로이드 "공유하기 → 이 앱"으로 받은 파일 경로를 받아옵니다(다른 기기에서는 아무 일도 안 함).
class ShareIntake {
  static const _channel = MethodChannel('aico/share');
  static bool _started = false;

  static void listen(void Function(String path) onFile) {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedFile' && call.arguments is String) onFile(call.arguments as String);
    });
    _channel
        .invokeMethod<String>('getInitialFile')
        .then((p) {
          if (p != null && p.isNotEmpty) onFile(p);
        })
        .catchError((Object e) {
          // 안드로이드가 아니면 여기로 옴(정상)
          if (e is! MissingPluginException) AppLog.warn('공유 파일 받기 실패', {'error': e.runtimeType.toString()});
          return null;
        });
  }
}
