import 'dart:io';
import 'dart:typed_data';

import 'package:ai_chat_organizer/app.dart';
import 'package:ai_chat_organizer/data/key_store.dart';
import 'package:ai_chat_organizer/services/app_controller.dart';
import 'package:ai_chat_organizer/services/settings.dart';
import 'package:ai_chat_organizer/voice/voice_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 말하면 미리 정한 문장을 돌려주는 가짜 음성.
class FakeVoice implements VoiceService {
  String nextPhrase = '';
  final spoken = <String>[];
  @override
  bool canListen = true;
  @override
  bool canSpeak = true;
  @override
  bool get isListening => false;
  @override
  Future<void> init() async {}
  @override
  Future<void> listen({required void Function(String, bool) onResult, void Function(String)? onError}) async => onResult(nextPhrase, true);
  @override
  Future<void> stopListening() async {}
  @override
  Future<void> speak(String text, {double rate = 0.5}) async => spoken.add(text);
  @override
  Future<void> stopSpeaking() async {}
}

Future<Uint8List> fileAsset(String a) async => File(a).readAsBytesSync();

AppController makeController({VoiceService? voice}) {
  final dir = Directory.systemTemp.createTempSync('aico_test');
  return AppController(
    root: dir,
    keys: MemoryKeyStore(),
    voice: voice ?? FakeVoice(),
    inMemoryDb: true,
    autoUpdateCheck: false,
    loadAsset: fileAsset,
  );
}

/// 사용자 한 명 + 샘플 대화가 들어 있는 컨트롤러.
Future<AppController> readyController({VoiceService? voice, void Function(AppSettings)? settings}) async {
  final c = makeController(voice: voice);
  await c.init();
  await c.createUser('시험');
  c.updateSettings((s) {
    s.onboardingDone = true;
    s.seenTips.addAll(['search', 'topics', 'decisions', 'conversation-voice']);
    settings?.call(s);
  });
  await c.importSamples();
  return c;
}

Future<void> setScreen(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget appWith(AppController c, {Widget? home}) => AiChatOrganizerApp(controller: c, home: home);
