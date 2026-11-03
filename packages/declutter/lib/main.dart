import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'core/logger.dart';
import 'services/appearance.dart';
import 'services/data_location.dart';
import 'services/media_picker.dart';
import 'services/notification_service.dart';
import 'services/voice_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    final startWatch = Stopwatch()..start();
    WidgetsFlutterBinding.ensureInitialized();
    // 전역 오류 처리: 기록만 하고 앱은 멈추지 않게
    FlutterError.onError = (details) {
      log.error('화면 오류', details.exception, details.stack);
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (e, st) {
      log.error('처리 안 된 오류', e, st);
      return true;
    };
    ErrorWidget.builder = (d) => const Material(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('이 부분을 보여 주지 못했어요. 뒤로 가서 다시 해 보세요.', textAlign: TextAlign.center),
        ),
      ),
    );

    final DatabaseFactory factory;
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    } else {
      factory = sqflite.databaseFactory;
    }
    final root = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}binugi');
    await migrateLegacyData(root);
    await root.create(recursive: true);
    AppState? state;
    Object? startError;
    try {
      state = await AppState.open(dbFactory: factory, root: root, voice: DeviceVoice(), notifier: DeviceNotifier());
    } catch (e, st) {
      log.error('시작 실패', e, st);
      startError = e;
    }
    final sw = Stopwatch()..start();
    if (state != null) {
      await Appearance.initWindow(state.global.appName);
      // 표시 이름을 바꾸면 창 제목도 바로 바뀜
      var lastName = state.global.appName;
      state.addListener(() {
        if (state!.global.appName != lastName) {
          lastName = state.global.appName;
          Appearance.setTitle(lastName);
        }
      });
    }
    runApp(state == null ? StartFailedApp(error: '$startError') : BinugiApp(state: state, picker: DeviceMediaPicker()));
    WidgetsBinding.instance.addPostFrameCallback((_) => log.info('첫 화면까지 ${sw.elapsedMilliseconds}ms (시작 준비 포함 ${startWatch.elapsedMilliseconds}ms)'));
    // 하루 한 번 조용히 새 버전 확인 (자동으로 내려받지는 않음)
    state?.quietUpdateCheck();
  }, (e, st) => log.error('처리 안 된 오류', e, st));
}
