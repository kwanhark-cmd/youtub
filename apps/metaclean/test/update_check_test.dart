import 'package:flutter_test/flutter_test.dart';
import 'package:metaclean/src/app_version.dart';
import 'package:metaclean/src/update_check.dart';

void main() {
  group('안내 파일 읽기', () {
    test('정상 내용', () {
      final i = parseUpdateInfo(
          '{"build": 61, "version": "2.1.0", "notes": " 달라진 점 "}')!;
      expect(i.build, 61);
      expect(i.version, '2.1.0');
      expect(i.notes, '달라진 점');
    });

    test('버전·설명이 없어도 빌드 번호만 있으면 읽는다', () {
      final i = parseUpdateInfo('{"build": 7}')!;
      expect(i.build, 7);
      expect(i.version, '');
      expect(i.notes, '');
    });

    test('형식이 틀리면 null', () {
      expect(parseUpdateInfo(''), isNull);
      expect(parseUpdateInfo('<html>Not Found</html>'), isNull);
      expect(parseUpdateInfo('[1,2]'), isNull);
      expect(parseUpdateInfo('{"build": "61"}'), isNull);
      expect(parseUpdateInfo('{"build": 0}'), isNull);
      expect(parseUpdateInfo('{"build": -3}'), isNull);
      expect(parseUpdateInfo('{"version": "2.1.0"}'), isNull);
    });

    test('너무 긴 설명은 줄인다', () {
      final i = parseUpdateInfo('{"build": 2, "notes": "${'가' * 2000}"}')!;
      expect(i.notes.length, lessThan(700));
    });

    test('설명을 자를 때 이모지가 반으로 잘리지 않는다', () {
      // 599글자 뒤에 이모지(UTF-16 두 칸)가 오도록 만든다
      final notes = '${'a' * 599}😀${'b' * 50}';
      final i = parseUpdateInfo('{"build": 2, "notes": "$notes"}')!;
      expect(i.notes, '${'a' * 599}😀…');
      // 짝이 맞지 않는 반쪽 글자가 없어야 화면에 그릴 수 있다
      expect(String.fromCharCodes(i.notes.runes), i.notes);
      expect(i.notes.runes.any((r) => r >= 0xD800 && r <= 0xDFFF), isFalse);
    });

    test('버전 글자는 한 줄로 만들고 길이를 제한한다', () {
      final i = parseUpdateInfo(
          '{"build": 2, "version": "  2.1.0\\n\\n ${'9' * 1500}  "}')!;
      expect(i.version.contains('\n'), isFalse);
      expect(i.version.runes.length, lessThanOrEqualTo(21));
      expect(i.version, startsWith('2.1.0 9'));
    });
  });

  group('새 버전 확인', () {
    Future<String?> Function(Uri) reply(String? body) => (_) async => body;

    test('더 큰 빌드 번호면 새 버전', () async {
      final r = await checkForUpdate(
          currentBuild: 60, fetch: reply('{"build": 61, "version": "2.1.0"}'));
      expect(r.status, UpdateStatus.available);
      expect(r.info!.build, 61);
    });

    test('같거나 작은 빌드 번호면 최신', () async {
      for (final b in [60, 59]) {
        final r = await checkForUpdate(
            currentBuild: 60, fetch: reply('{"build": $b}'));
        expect(r.status, UpdateStatus.upToDate);
      }
    });

    test('올라온 것이 없으면(404) 아직 없음, 내용이 이상하면 알 수 없음', () async {
      expect((await checkForUpdate(currentBuild: 60, fetch: reply(null))).status,
          UpdateStatus.notPublished);
      expect(
          (await checkForUpdate(currentBuild: 60, fetch: reply('oops'))).status,
          UpdateStatus.unknown);
    });

    test('인터넷이 안 돼도 예외 없이 알 수 없음', () async {
      final r = await checkForUpdate(
          currentBuild: 60, fetch: (_) async => throw Exception('연결 실패'));
      expect(r.status, UpdateStatus.unknown);
    });

    test('정해진 주소만 읽는다', () async {
      Uri? asked;
      await checkForUpdate(
          currentBuild: 1,
          fetch: (u) async {
            asked = u;
            return null;
          });
      expect(asked, latestInfoUrl);
      expect(latestInfoUrl.scheme, 'https');
      expect(latestApkUrl.scheme, 'https');
      expect(latestApkUrl.host, 'github.com');
      expect(latestApkUrl.path, endsWith('/metaclean-plus.apk'));
      // 빌드마다 이름이 다른 설치 파일 주소도 같은 고정 주소 아래에 있다
      final numbered = apkUrlFor(61);
      expect(numbered.scheme, 'https');
      expect(numbered.host, 'github.com');
      expect(numbered.path,
          '${latestApkUrl.path.replaceAll('metaclean-plus.apk', '')}metaclean-plus-61.apk');
    });
  });

  test('버전 글자', () {
    expect(versionLabel('2.1.0', 61), '2.1.0 (빌드 61)');
    expect(versionLabel('', 61), '빌드 61');
    expect(versionLabel('2.1.0', 0), '시험판');
  });
}
