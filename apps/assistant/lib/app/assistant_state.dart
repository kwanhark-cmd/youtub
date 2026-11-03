import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../modules/registry.dart';

const appVersion = '1.0.0';
const releaseRepo = 'kwanhark-cmd/youtub';

/// 본체 앱 전체 상태: 설정 하나, 로그인 하나, 모듈 다섯, 제안함 하나.
class AssistantState extends ChangeNotifier {
  AssistantState({required this.root, required this.secrets, ModuleRegistry? modules})
      : settings = AppSettings(File(p.join(root.path, 'assistant', 'settings.json'))),
        auth = AuthService(file: File(p.join(root.path, 'assistant', 'users.json')), secrets: secrets) {
    links = LinkHub(file: File(p.join(root.path, 'assistant', 'links.json')), enabled: (k) => settings.linkOn(k.name));
    this.modules = modules ?? ModuleRegistry.device(this);
    settings.addListener(notifyListeners);
    links.addListener(notifyListeners);
  }

  /// 통합 앱 사용자 폴더. 모듈 자료는 이 아래 모듈별 하위 폴더에 있다.
  final Directory root;
  final SecretStore secrets;
  final AppSettings settings;
  final AuthService auth;
  late final LinkHub links;
  late final ModuleRegistry modules;
  final router = VoiceRouter();

  AssistantUser? user;

  Future<void> start() async {
    user = await auth.tryAutoLogin();
    notifyListeners();
  }

  Future<void> login(AssistantUser u, {bool remember = true}) async {
    user = u;
    await auth.setAutoLogin(u, remember);
    CoreLog.info('로그인 #${u.id}');
    notifyListeners();
  }

  /// 제안 받기: 받는 모듈에 넣고, 넣었으면 제안함에서 "받음"으로.
  Future<bool> acceptSuggestion(Suggestion sg) async {
    try {
      final ok = await modules.of(sg.to).receive(sg);
      if (ok) links.accept(sg.id);
      return ok;
    } catch (e, st) {
      CoreLog.error('제안 받기 실패 (${sg.kind.title})', e, st);
      return false;
    }
  }

  Future<void> logout() async {
    await auth.logout();
    user = null;
    notifyListeners();
  }
}
