import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app.dart';
import 'core/app_log.dart';
import 'data/key_store.dart';
import 'services/app_controller.dart';
import 'services/data_location.dart';
import 'voice/voice_service.dart';

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      final root = await DataLocation.resolve();
      root.createSync(recursive: true);
      AppLog.init(File('${root.path}/logs/app.log'));
      AppLog.info('앱 시작', {'os': Platform.operatingSystem});

      // 전역 오류 처리: 앱이 멈추지 않게 기록만 남기고 쉬운 안내를 띄움
      FlutterError.onError = (details) {
        AppLog.error('화면 오류', details.exception, details.stack);
        FlutterError.presentError(details);
      };
      WidgetsBinding.instance.platformDispatcher.onError = (e, st) {
        AppLog.error('처리되지 않은 오류', e, st);
        AppErrorBus.report();
        return true;
      };

      // 함께 쓰는 글꼴·그림의 라이선스를 앱 안 라이선스 목록에 등록
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks(['플루언트 이모지 3D'], await rootBundle.loadString('assets/licenses/FluentEmoji-MIT-LICENSE.txt'));
        yield LicenseEntryWithLineBreaks(['나눔고딕'], await rootBundle.loadString('assets/licenses/NanumGothic-OFL.txt'));
      });

      final controller = AppController(root: root, keys: SecureKeyStore(File('${root.path}/.keys')), voice: DeviceVoiceService());
      // 지메일 연결 때 브라우저 열기
      controller.openBrowser = (u) async {
        await launchUrl(u, mode: LaunchMode.externalApplication);
      };
      runApp(AiChatOrganizerApp(controller: controller));
      await controller.init();
    },
    (e, st) {
      AppLog.error('처리되지 않은 오류(영역)', e, st);
      AppErrorBus.report();
    },
  );
}
