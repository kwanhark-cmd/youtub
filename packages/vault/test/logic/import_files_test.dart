import 'package:account_vault/logic/import_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('구글 데스크톱 앱 JSON', () {
    final (id, secret) = parseGoogleClientJson(
      '{"installed":{"client_id":"123-fake.apps.googleusercontent.com","project_id":"x","client_secret":"FAKE-secret","redirect_uris":["http://localhost"]}}',
    );
    expect(id, '123-fake.apps.googleusercontent.com');
    expect(secret, 'FAKE-secret');
  });

  test('웹 유형·엉뚱한 파일은 쉬운 안내', () {
    expect(
      () => parseGoogleClientJson(
        '{"web":{"client_id":"a.apps.googleusercontent.com"}}',
      ),
      throwsA(
        isA<ImportFileException>().having(
          (e) => e.message,
          'm',
          contains('데스크톱 앱'),
        ),
      ),
    );
    expect(
      () => parseGoogleClientJson('hello'),
      throwsA(isA<ImportFileException>()),
    );
    expect(
      () => parseGoogleClientJson('{"installed":{"client_id":"x"}}'),
      throwsA(isA<ImportFileException>()),
    );
  });

  test('AI 열쇠 파일', () {
    expect(
      parseAiKeyFile('메모\nsk-ant-api03-FAKEFAKEFAKE1234\n'),
      'sk-ant-api03-FAKEFAKEFAKE1234',
    );
    expect(
      parseAiKeyFile('  abcdefghijklmnopqrstuvwxyz  \n'),
      'abcdefghijklmnopqrstuvwxyz',
    );
    expect(
      () => parseAiKeyFile('그냥 글 여러 단어'),
      throwsA(isA<ImportFileException>()),
    );
  });
}
