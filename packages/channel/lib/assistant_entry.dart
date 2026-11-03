// 개인비서(통합 앱)에서 이 모듈을 여는 입구. 단독 앱의 main.dart 와 같은 준비를 하되,
// 자료는 통합 앱 사용자 폴더 아래 `channel_biseo/` 에 두고, 로그인은 개인비서 로그인 하나로 대신한다.
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
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

/// 채널 모듈 자료 폴더 이름 (통합 앱 사용자 폴더 아래)
const channelFolder = 'channel_biseo';

bool _stagesRegistered = false;

/// 채널 모듈 준비 (한 번만). [userName]은 개인비서에 로그인한 사람 이름.
Future<AppState> openChannelState({required String userName, required String appVersion, String? baseDir}) async {
  final support = baseDir ?? p.join((await getApplicationSupportDirectory()).path, channelFolder);
  Directory(support).createSync(recursive: true);
  String docs;
  try {
    docs = p.join((await getApplicationDocumentsDirectory()).path, '개인비서', '채널');
    Directory(docs).createSync(recursive: true);
  } catch (_) {
    docs = support;
  }
  final log = AppLogger(file: File(p.join(support, 'logs', 'app.log')));
  final env = AppEnv(
    baseDir: support,
    documentsDir: docs,
    secrets: OsSecretStore(),
    httpClient: http.Client(),
    logger: log,
    speech: DeviceSpeechInput(log),
    speaker: DeviceSpeaker(log),
    notifier: DeviceNotifier(log),
    isDesktop: Platform.isWindows || Platform.isMacOS || Platform.isLinux,
    platformName: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    appVersion: appVersion,
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
  );
  if (!_stagesRegistered) {
    registerStages();
    _stagesRegistered = true;
  }
  final state = AppState(env);
  await signInAs(state, userName);
  return state;
}

/// 개인비서 로그인 이름과 같은 채널 사용자로 바로 들어간다. 없으면 만든다(비밀번호는 무작위, 쓰지 않음).
Future<void> signInAs(AppState state, String userName) async {
  if (await state.tryAutoLogin() && state.user?.user.name == userName) return;
  final name = userName.trim().isEmpty ? '나' : userName.trim();
  final found = state.env.accounts.list().where((u) => u.name == name);
  final r = Random.secure();
  final u = found.isNotEmpty
      ? found.first
      : state.env.accounts.create(name, List.generate(24, (_) => r.nextInt(36).toRadixString(36)).join());
  await state.login(u);
}

Widget channelApp(AppState state) => ChannelBiseoApp(state: state);
