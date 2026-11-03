// 개인비서(통합 앱)에서 이 모듈을 여는 입구. 단독 앱 main.dart 와 같은 준비를 한다.
// 자료는 통합 앱 사용자 폴더 아래 `binugi/`. 창 제목은 본체 앱이 정하므로 바꾸지 않는다.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'core/clock.dart';
import 'services/media_picker.dart';
import 'services/notification_service.dart';
import 'services/secret_store.dart';
import 'services/voice_service.dart';
import 'state/app_state.dart';

int _memN = 0;

/// [inMemory]: 시험용. 메모리 DB(격리 없이)와 조용한 음성·알림을 쓴다.
/// 나머지 인자는 시험에서 가짜를 넣을 때만 쓴다(기본은 단독 앱과 같음).
Future<AppState> openDeclutterState({
  Directory? rootOverride,
  bool inMemory = false,
  Clock? clock,
  VoiceIO? voice,
  Notifier? notifier,
  SecretStore? secretStore,
  http.Client? httpClient,
}) async {
  final DatabaseFactory factory;
  if (inMemory) {
    sqfliteFfiInit();
    factory = databaseFactoryFfiNoIsolate;
  } else if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    factory = databaseFactoryFfi;
  } else {
    factory = sqflite.databaseFactory;
  }
  final root = rootOverride ?? Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}binugi');
  await root.create(recursive: true);
  return AppState.open(
    dbFactory: factory,
    root: root,
    dbPath: inMemory ? 'file:assistant_mem${_memN++}_${DateTime.now().microsecondsSinceEpoch}?mode=memory&cache=shared' : null,
    clock: clock ?? const SystemClock(),
    voice: voice ?? (inMemory ? SilentVoice() : DeviceVoice()),
    notifier: notifier ?? (inMemory ? SilentNotifier() : DeviceNotifier()),
    secretStore: secretStore ?? (inMemory ? MemorySecretStore() : null),
    httpClient: httpClient,
  );
}

Widget declutterApp(AppState state) => BinugiApp(state: state, picker: DeviceMediaPicker());
