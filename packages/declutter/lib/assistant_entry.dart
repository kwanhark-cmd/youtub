// 개인비서(통합 앱)에서 이 모듈을 여는 입구. 단독 앱 main.dart 와 같은 준비를 한다.
// 자료는 통합 앱 사용자 폴더 아래 `binugi/`. 창 제목은 본체 앱이 정하므로 바꾸지 않는다.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'services/media_picker.dart';
import 'services/notification_service.dart';
import 'services/voice_service.dart';
import 'state/app_state.dart';

Future<AppState> openDeclutterState({Directory? rootOverride}) async {
  final DatabaseFactory factory;
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    factory = databaseFactoryFfi;
  } else {
    factory = sqflite.databaseFactory;
  }
  final root = rootOverride ?? Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}binugi');
  await root.create(recursive: true);
  return AppState.open(dbFactory: factory, root: root, voice: DeviceVoice(), notifier: DeviceNotifier());
}

Widget declutterApp(AppState state) => BinugiApp(state: state, picker: DeviceMediaPicker());
