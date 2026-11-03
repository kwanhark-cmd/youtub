// 통합 앱 식별자가 바뀌면 업데이트가 "덮어쓰기"가 아니라 다른 앱이 되어 자료·열쇠를 못 찾는다.
// 또 다섯 단독 앱과 겹치면 안 된다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String f) => File(f).readAsStringSync();

void main() {
  test('통합 앱 식별자 고정 (단독 앱 다섯과 다름)', () {
    expect(read('android/app/build.gradle.kts'), contains('applicationId = "com.kwanhark.personal_assistant"'));
    expect(read('macos/Runner/Configs/AppInfo.xcconfig'), contains('PRODUCT_BUNDLE_IDENTIFIER = com.kwanhark.personalAssistant'));
    expect(read('linux/CMakeLists.txt'), contains('set(APPLICATION_ID "com.kwanhark.personal_assistant")'));
    expect(read('windows/runner/Runner.rc'), contains('VALUE "CompanyName", "com.kwanhark"'));
    expect(read('windows/runner/Runner.rc'), contains('VALUE "ProductName", "personal_assistant"'));
    for (final old in ['com.channelbiseo', 'com.aichatorganizer', 'com.binugi', 'com.kwanhark.vaultassistant']) {
      expect(read('android/app/build.gradle.kts'), isNot(contains(old)));
    }
  });

  test('표시 이름은 "개인비서"', () {
    expect(read('android/app/src/main/AndroidManifest.xml'), contains('android:label="개인비서"'));
    expect(read('macos/Runner/Info.plist'), contains('<string>개인비서</string>'));
    expect(read('windows/runner/main.cpp'), contains(r'L"\uAC1C\uC778\uBE44\uC11C"'));
  });
}
