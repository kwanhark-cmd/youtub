// 개인비서(통합 앱)에서 이 모듈을 여는 입구. 단독 앱 main.dart 와 같은 준비를 한다.
// 금고 자료는 통합 앱 사용자 폴더 아래 `vault_app/`. 암호화 방식·마스터 비밀번호는 그대로이며
// 개인비서 로그인과 상관없이 금고는 항상 자기 마스터 비밀번호로 연다.
import 'package:flutter/widgets.dart';

import 'app/app_controller.dart';
import 'app/platform_services.dart';
import 'ui/app.dart';

Future<AppController> openVaultController() async {
  final services = await createPlatformServices();
  final c = AppController(services);
  await c.init();
  return c;
}

Widget vaultApp(AppController c) => VaultApp(controller: c);
