// 개인비서(통합 앱)에서 이 모듈을 여는 입구. 단독 앱 main.dart 와 같은 준비를 한다.
// 금고 자료는 통합 앱 사용자 폴더 아래 `vault_app/`. 암호화 방식·마스터 비밀번호는 그대로이며
// 개인비서 로그인과 상관없이 금고는 항상 자기 마스터 비밀번호로 연다.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app_controller.dart';
import 'app/platform_services.dart';
import 'data/repository.dart';
import 'ui/app.dart';

Future<AppController> openVaultController() async {
  final services = await createPlatformServices();
  final c = AppController(services);
  await c.init();
  return c;
}

Widget vaultApp(AppController c) => VaultApp(controller: c);

/// 금고를 아직 띄우지 않았을 때(늦게 로드) 사용자 금고가 하나라도 있는지만 본다.
/// 사용자 목록(profiles.json, 이름·id 만 있고 비밀 정보 없음)만 읽고, 금고 파일은 열지 않는다.
Future<bool> vaultHasProfiles({Directory? dataDir}) async {
  try {
    final dir = dataDir ??
        Directory(p.join((await getApplicationSupportDirectory()).path, 'vault_app'));
    final list = await ProfileRepository(Directory(p.join(dir.path, 'store'))).list();
    return list.isNotEmpty;
  } catch (_) {
    return false;
  }
}
