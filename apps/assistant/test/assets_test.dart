import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('모듈 그림을 모듈 코드 그대로의 이름으로 찾는다', () async {
    for (final e in {
      'channel_biseo': 'assets/icons3d/hello.png',
      'ai_chat_organizer': 'assets/mascot/mascot_hello.svg',
      'binugi': 'assets/mascot/hello.svg',
      'account_vault': 'assets/mascot/hello.svg',
    }.entries) {
      final b = PackageAssetBundle(e.key);
      expect((await b.load(e.value)).lengthInBytes, greaterThan(100), reason: e.key);
    }
  });

  test('본체 그림은 그대로 찾는다', () async {
    final b = PackageAssetBundle('binugi');
    expect((await b.load('assets/icons/mascot_hello.png')).lengthInBytes, greaterThan(100));
    expect(() => rootBundle.load('assets/없음.png'), throwsA(anything));
  });
}
