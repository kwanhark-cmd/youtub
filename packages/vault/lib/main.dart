import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'app/platform_services.dart';
import 'core/log/app_logger.dart';
import 'ui/app.dart';

Future<void> main() async {
  // 전역 오류 처리: 어떤 오류도 비밀번호·계정 정보를 기록하지 않는다(로그에서 다시 가림).
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      log.error('화면 오류', details.exception, details.stack);
      if (kDebugMode) FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (e, st) {
      log.error('처리되지 않은 오류', e, st);
      return true;
    };
    ErrorWidget.builder = (details) => const FriendlyErrorBox();
    final services = await createPlatformServices();
    final controller = AppController(services);
    await controller.init();
    runApp(VaultApp(controller: controller));
  }, (e, st) => log.error('처리되지 않은 오류', e, st));
}
