// 앱 식별자·자료 위치가 바뀌면 업데이트 후 기존 금고를 못 찾는다. 절대 바뀌지 않게 지킨다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String p) => File(p).readAsStringSync();

// 통합 앱(개인비서) 안에서는 이 패키지에 플랫폼 폴더가 없어 단독 앱 저장소에서만 확인한다.
// 통합 앱 식별자는 apps/assistant/test/identifiers_test.dart 에서 지킨다.
final _standalone = File('android/app/build.gradle.kts').existsSync();

void main() {
  test('안드로이드 패키지 이름 고정', skip: !_standalone, () {
    final g = read('android/app/build.gradle.kts');
    expect(
      g,
      contains('applicationId = "com.kwanhark.vaultassistant.account_vault"'),
    );
    expect(
      g,
      contains('namespace = "com.kwanhark.vaultassistant.account_vault"'),
    );
  });

  test('맥 번들 ID 고정', skip: !_standalone, () {
    expect(
      read('macos/Runner/Configs/AppInfo.xcconfig'),
      contains(
        'PRODUCT_BUNDLE_IDENTIFIER = com.kwanhark.vaultassistant.accountVault',
      ),
    );
  });

  test('윈도우: 자료 폴더(%APPDATA%\\회사\\제품)를 정하는 값과 설치 AppId 고정', skip: !_standalone, () {
    final rc = read('windows/runner/Runner.rc');
    expect(rc, contains('VALUE "CompanyName", "com.kwanhark.vaultassistant"'));
    expect(rc, contains('VALUE "ProductName", "account_vault"'));
    expect(
      read('windows/CMakeLists.txt'),
      contains('set(BINARY_NAME "account_vault")'),
    );
    expect(
      read('windows/installer/account_vault.iss'),
      contains('AppId={{6F1D7A3E-6C1B-4D2A-9B7E-1C2D3E4F5A6B}'),
    );
  });

  test('리눅스 앱 ID 고정', skip: !_standalone, () {
    expect(
      read('linux/CMakeLists.txt'),
      contains(
        'set(APPLICATION_ID "com.kwanhark.vaultassistant.account_vault")',
      ),
    );
  });

  test('금고는 앱 파일이 아닌 사용자 자료 폴더에(덮어써도 남음)', () {
    final s = read('lib/app/platform_services.dart');
    // 맥 ~/Library/Application Support, 윈도우 %APPDATA%, 안드로이드 앱 데이터 = getApplicationSupportDirectory
    expect(
      s,
      contains("final support = await getApplicationSupportDirectory();"),
    );
    expect(s, contains("p.join(support.path, 'vault_app')"));
    expect(
      read('lib/app/app_controller.dart'),
      contains("p.join(services.dataDir.path, 'store')"),
    );
    expect(
      read('lib/app/app_controller.dart'),
      contains("p.join(services.dataDir.path, 'settings.json')"),
    );
  });

  test('생체 인증 래핑 키는 OS 보안 저장소(같은 키 이름)', () {
    final s = read('lib/app/platform_services.dart');
    expect(s, contains('FlutterSecureStorage'));
    expect(s, contains("'device_key_\$id'"));
  });
}
