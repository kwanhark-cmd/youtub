import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app/app.dart';
import 'app/services.dart';
import 'core/logger.dart';
import 'core/secret_store.dart';
import 'features/runner/notifier.dart';
import 'features/update/installer.dart';
import 'features/voice/voice_io.dart';
import 'stages.dart';
import 'ui/common.dart';

/// 안드로이드 앱 꾸미기 (MainActivity.kt)
const _look = MethodChannel('channel_biseo/look');

Future<void> main() async {
  AppLogger? logger;
  // 어떤 오류가 나도 앱이 죽지 않게 모두 붙잡아 기록한다.
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    final support = await getApplicationSupportDirectory();
    final docs = await _documentsDir(support);
    logger = AppLogger(file: File(p.join(support.path, 'logs', 'app.log')));
    final log = logger!;
    FlutterError.onError = (d) {
      log.error('화면 오류', d.exception, d.stack);
      if (kDebugMode) FlutterError.presentError(d);
    };
    PlatformDispatcher.instance.onError = (e, st) {
      log.error('처리되지 않은 오류', e, st);
      return true;
    };
    ErrorWidget.builder = friendlyErrorWidget;

    final info = await PackageInfo.fromPlatform();
    final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    final env = AppEnv(
      baseDir: support.path,
      documentsDir: docs,
      secrets: OsSecretStore(),
      httpClient: http.Client(),
      logger: log,
      speech: DeviceSpeechInput(log),
      speaker: DeviceSpeaker(log),
      notifier: DeviceNotifier(log),
      isDesktop: isDesktop,
      platformName: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      appVersion: '${info.version}+${info.buildNumber}',
      launchUrl: (u) => launchUrl(u, mode: LaunchMode.externalApplication),
      pickFile: (ext) async {
        final f = await FilePicker.pickFile(
          type: ext.isEmpty ? FileType.any : FileType.custom,
          allowedExtensions: ext.isEmpty ? null : ext,
        );
        return f?.path;
      },
      pickDirectory: () => FilePicker.getDirectoryPath(),
      installUpdate: UpdateInstaller(log).install,
      osName: Platform.operatingSystem,
      setLauncherIcon: Platform.isAndroid ? (id) => _look.invokeMethod<void>('setLauncherIcon', {'id': id}) : null,
      pinShortcut: Platform.isAndroid
          ? (label, png) async => await _look.invokeMethod<bool>('pinShortcut', {'label': label, 'png': png}) ?? false
          : null,
    );
    log.info('앱 시작 ${env.appVersion} ${env.platformName}');
    registerStages();
    final state = AppState(env);
    await state.tryAutoLogin();
    runApp(ChannelBiseoApp(state: state));
  }, (e, st) => logger?.error('앱 오류', e, st));
}

Future<String> _documentsDir(Directory fallback) async {
  try {
    final d = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(d.path, '채널관리비서'));
    dir.createSync(recursive: true);
    return dir.path;
  } catch (_) {
    return fallback.path;
  }
}
