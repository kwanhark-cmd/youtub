import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/assistant_state.dart';
import 'ui/assistant_app.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    final sw = Stopwatch()..start();
    WidgetsFlutterBinding.ensureInitialized();
    final root = await getApplicationSupportDirectory();
    CoreLog.init(File(p.join(root.path, 'assistant', 'logs', 'app.log')));
    FlutterError.onError = (d) {
      CoreLog.error('화면 오류', d.exception, d.stack);
      if (kDebugMode) FlutterError.presentError(d);
    };
    PlatformDispatcher.instance.onError = (e, st) {
      CoreLog.error('처리되지 않은 오류', e, st);
      return true;
    };
    ErrorWidget.builder = (d) => const Material(
          child: Center(child: Padding(padding: EdgeInsets.all(24), child: Text('이 부분을 보여 주지 못했어요. 뒤로 가서 다시 해 보세요.', textAlign: TextAlign.center))),
        );
    final state = AssistantState(root: root, secrets: OsSecrets());
    await state.start();
    CoreLog.info('개인비서 시작 $appVersion ${Platform.operatingSystem}');
    runApp(AssistantApp(state: state));
    WidgetsBinding.instance.addPostFrameCallback((_) => CoreLog.info('첫 화면까지 ${sw.elapsedMilliseconds}ms'));
  }, (e, st) => CoreLog.error('처리되지 않은 오류', e, st));
}
