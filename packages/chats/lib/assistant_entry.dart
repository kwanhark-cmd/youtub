// 개인비서(통합 앱)에서 이 모듈을 여는 입구. 단독 앱 main.dart 와 같은 준비를 한다.
// 자료는 통합 앱 사용자 폴더 아래 `ai_chat_organizer/` (DataLocation 그대로).
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app.dart';
import 'core/app_log.dart';
import 'data/key_store.dart';
import 'services/app_controller.dart';
import 'services/data_location.dart';
import 'voice/voice_service.dart';

Future<AppController> openChatsController({required String userName, Directory? rootOverride}) async {
  final root = rootOverride ?? await DataLocation.resolve();
  root.createSync(recursive: true);
  AppLog.init(File('${root.path}/logs/app.log'));
  final c = AppController(root: root, keys: SecureKeyStore(File('${root.path}/.keys')), voice: DeviceVoiceService());
  c.openBrowser = (u) async {
    await launchUrl(u, mode: LaunchMode.externalApplication);
  };
  await c.init();
  await signInAs(c, userName);
  return c;
}

/// 개인비서 로그인 이름과 같은 사용자로 바로 들어간다. 없으면 만든다.
/// 기존 사용자에게 잠금 번호가 있으면 모듈 자기 잠금 화면을 그대로 보여 준다(건너뛰지 않음).
Future<void> signInAs(AppController c, String userName) async {
  final name = userName.trim().isEmpty ? '나' : userName.trim();
  if (c.session?.user.name == name) return;
  final same = c.profiles.where((u) => u.name == name).toList();
  if (same.isEmpty) {
    if (c.profiles.isEmpty) await c.createUser(name);
    return;
  }
  if (same.first.pinHash == null) await c.signIn(same.first);
}

Widget chatsApp(AppController c) => AiChatOrganizerApp(controller: c);
