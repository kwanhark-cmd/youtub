import 'dart:io';

import 'package:channel_biseo/core/db.dart';
import 'package:channel_biseo/core/failure.dart';
import 'package:channel_biseo/core/http_json.dart';
import 'package:channel_biseo/core/logger.dart';
import 'package:channel_biseo/core/retry.dart';
import 'package:channel_biseo/core/secret_store.dart';
import 'package:channel_biseo/core/strings.dart';
import 'package:channel_biseo/features/accounts/local_accounts.dart';
import 'package:channel_biseo/features/youtube/quota.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('민감정보 가리기', () {
    test('토큰·키·비밀번호가 지워진다', () {
      const raw =
          'Authorization: Bearer ya29.abcDEF123 key=sk-ant-api03-XYZ '
          '{"refresh_token":"1//0gabcdefghijkl","password":"hello"} client_secret=GOCSPX-abc '
          'AIzaSyA1234567890123456789012 user@example.com';
      final r = redact(raw);
      expect(r, isNot(contains('ya29.abcDEF123')));
      expect(r, isNot(contains('sk-ant-api03-XYZ')));
      expect(r, isNot(contains('1//0gabcdefghijkl')));
      expect(r, isNot(contains('hello')));
      expect(r, isNot(contains('GOCSPX-abc')));
      expect(r, isNot(contains('AIzaSyA1234567890123456789012')));
      expect(r, isNot(contains('user@example.com')));
      expect(r, contains('[가림]'));
    });

    test('로거는 기록할 때 자동으로 가린다', () {
      final dir = Directory.systemTemp.createTempSync('log');
      final l = AppLogger(file: File(p.join(dir.path, 'a.log')));
      l.info('api_key=sk-ant-secret123 다음');
      expect(l.recentLines().join(), isNot(contains('sk-ant-secret123')));
      expect(File(p.join(dir.path, 'a.log')).readAsStringSync(), isNot(contains('sk-ant-secret123')));
    });
  });

  group('재시도', () {
    test('네트워크 오류는 최대 3번, 간격을 늘리며 다시 시도', () async {
      var n = 0;
      final waits = <Duration>[];
      await expectLater(
        withRetry(() async {
          n++;
          throw AppFailure(FailureKind.network);
        }, sleep: (d) async => waits.add(d)),
        throwsA(isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.network)),
      );
      expect(n, 3);
      expect(waits, [const Duration(seconds: 1), const Duration(seconds: 2)]);
    });

    test('재시도하면 안 되는 오류는 한 번만', () async {
      var n = 0;
      await expectLater(
        withRetry(() async {
          n++;
          throw AppFailure(FailureKind.quotaExceeded);
        }, sleep: (_) async {}),
        throwsA(isA<AppFailure>()),
      );
      expect(n, 1);
    });

    test('두 번째에 성공하면 결과를 돌려준다', () async {
      var n = 0;
      final r = await withRetry(() async {
        if (++n == 1) throw AppFailure(FailureKind.timeout);
        return 7;
      }, sleep: (_) async {});
      expect(r, 7);
    });

    test('시간 제한을 넘으면 timeout', () async {
      await expectLater(
        withRetry(
          () => Future<int>.delayed(const Duration(seconds: 1), () => 1),
          timeout: const Duration(milliseconds: 10),
          maxAttempts: 1,
        ),
        throwsA(isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.timeout)),
      );
    });

    test('취소하면 바로 멈춘다', () async {
      final c = CancelToken()..cancel();
      await expectLater(withRetry(() async => 1, cancel: c), throwsA(isA<AppFailure>()));
    });
  });

  group('HTTP 오류 구분', () {
    test('토큰 만료·권한 취소·한도 초과를 구분', () {
      expect(classifyHttpError(401, '').kind, FailureKind.tokenExpired);
      expect(classifyHttpError(400, '{"error":"invalid_grant"}').kind, FailureKind.permissionRevoked);
      expect(classifyHttpError(403, '{"reason":"quotaExceeded"}').kind, FailureKind.quotaExceeded);
      expect(classifyHttpError(403, '{"reason":"forbidden"}').kind, FailureKind.permissionRevoked);
      expect(classifyHttpError(429, '').kind, FailureKind.rateLimited);
      expect(classifyHttpError(503, '').kind, FailureKind.network);
    });

    test('모든 실패 종류에 쉬운 한국어 안내와 다음 행동이 있다', () {
      for (final k in FailureKind.values) {
        final f = AppFailure(k);
        expect(f.userMessage, isNotEmpty);
        expect(RegExp(r'[가-힣]').hasMatch(f.userMessage), isTrue, reason: k.name);
        expect(RegExp(r'HTTP|Exception|null').hasMatch(f.userMessage), isFalse);
        expect(S.nextActionLabel(f.nextAction), isNotEmpty);
      }
      expect(AppFailure(FailureKind.tokenExpired).nextAction, NextAction.reconnect);
      expect(AppFailure(FailureKind.quotaExceeded).nextAction, NextAction.tryTomorrow);
    });
  });

  group('DB 자동 변환', () {
    test('버전이 오르면 변환 전에 자동 백업하고 자료를 지킨다', () {
      final dir = Directory.systemTemp.createTempSync('mig');
      final path = p.join(dir.path, 'd.sqlite');
      const v1 = [
        Migration(1, ['CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)', 'CREATE TABLE t(a TEXT)']),
      ];
      final a = AppDatabase.open(path, v1);
      a.execute("INSERT INTO t VALUES('보존')");
      expect(a.version, 1);
      a.close();

      const v2 = [
        ...v1,
        Migration(2, ['ALTER TABLE t ADD COLUMN b INTEGER DEFAULT 5']),
      ];
      final b = AppDatabase.open(path, v2);
      expect(b.version, 2);
      expect(b.select('SELECT a, b FROM t').first['a'], '보존');
      expect(b.select('SELECT a, b FROM t').first['b'], 5);
      b.close();
      final backups = Directory(p.join(dir.path, 'backups')).listSync();
      expect(backups.length, 1);
      expect(p.basename(backups.first.path), contains('-v1-'));
    });

    test('변환이 실패하면 되돌리고 버전은 그대로', () {
      final dir = Directory.systemTemp.createTempSync('mig2');
      final path = p.join(dir.path, 'd.sqlite');
      const v1 = [
        Migration(1, ['CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)']),
      ];
      AppDatabase.open(path, v1).close();
      const bad = [
        ...v1,
        Migration(2, ['CREATE TABLE x(a)', 'THIS IS NOT SQL']),
      ];
      expect(() => AppDatabase.open(path, bad), throwsA(anything));
      final c = AppDatabase.open(path, v1);
      expect(c.version, 1);
      expect(c.select("SELECT name FROM sqlite_master WHERE name='x'"), isEmpty);
    });

    test('1단계 자료(v1)를 최신 버전으로 자동 변환해도 채널·수정 내역이 남는다', () {
      final dir = Directory.systemTemp.createTempSync('mig3');
      final path = p.join(dir.path, 'data.sqlite');
      final v1 = AppDatabase.open(path, userDataMigrations.where((m) => m.version == 1).toList());
      v1.execute("INSERT INTO channels(channel_id, title, added_at) VALUES('C1','옛 채널','2026-01-01')");
      v1.close();
      final now = AppDatabase.open(path, userDataMigrations);
      expect(now.version, userDataMigrations.last.version);
      expect(now.select('SELECT title FROM channels').first['title'], '옛 채널');
      expect(
        now.select("SELECT name FROM sqlite_master WHERE name IN ('productions','blog_sites','corners')").length,
        3,
      );
      expect(Directory(p.join(dir.path, 'backups')).listSync(), isNotEmpty);
    });

    test('설정 저장', () {
      final d = AppDatabase.inMemory(userDataMigrations);
      d.setSetting('a', 3);
      d.setSetting('a', 4);
      expect(d.getSetting<num>('a'), 4);
      expect(d.getSetting<String>('none'), isNull);
    });
  });

  group('로컬 계정', () {
    test('비밀번호는 저장하지 않고 해시만 저장', () {
      final acc = LocalAccounts(baseDir: '', secrets: MemorySecretStore(), inMemory: true);
      final u = acc.create('홍길동', 'abcd1234');
      final row = acc.db.select('SELECT * FROM users').first;
      expect(row.values.join(), isNot(contains('abcd1234')));
      expect(acc.verify(u.id, 'abcd1234')?.name, '홍길동');
      expect(acc.verify(u.id, 'wrong'), isNull);
    });

    test('이름 중복·짧은 비밀번호 거부', () {
      final acc = LocalAccounts(baseDir: '', secrets: MemorySecretStore(), inMemory: true);
      acc.create('a', '1234');
      expect(() => acc.create('a', '5678'), throwsA(isA<AppFailure>()));
      expect(() => acc.create('b', '12'), throwsA(isA<AppFailure>()));
    });

    test('사용자마다 자료가 분리된다', () async {
      final secrets = MemorySecretStore();
      final acc = LocalAccounts(baseDir: '', secrets: secrets, inMemory: true);
      final a = acc.create('a', '1234');
      final b = acc.create('b', '1234');
      acc.openUserDb(a.id).setSetting('x', 'A의 자료');
      expect(acc.openUserDb(b.id).getSetting<String>('x'), isNull);
      await UserSecrets(secrets, a.id).write('k', 'A비밀');
      expect(await UserSecrets(secrets, b.id).read('k'), isNull);
      // u1/ 지우기가 u10/ 같은 다른 사용자를 건드리지 않는다
      await secrets.write('u10/k', 'x');
      await UserSecrets(secrets, 1).deleteAll();
      expect(await secrets.read('u10/k'), 'x');
    });
  });

  group('유튜브 한도', () {
    test('예약·초과·되돌려주기', () {
      final d = AppDatabase.inMemory(userDataMigrations);
      final q = QuotaTracker(d, limit: () => 100, now: () => DateTime.utc(2026, 11, 2, 12));
      q.reserve(50);
      expect(q.remaining, 50);
      expect(() => q.reserve(60), throwsA(isA<AppFailure>().having((e) => e.kind, 'k', FailureKind.quotaExceeded)));
      q.refund(10);
      expect(q.remaining, 60);
      q.markExhausted();
      expect(q.remaining, 0);
    });

    test('태평양 시간 자정 기준으로 하루가 바뀐다', () {
      // 한국 시간 2026-11-02 16:59 = UTC 07:59 → 태평양(PST, 서머타임 끝난 뒤) 11-01 23:59
      expect(quotaDay(DateTime.utc(2026, 11, 2, 7, 59)), '2026-11-01');
      expect(quotaDay(DateTime.utc(2026, 11, 2, 8, 0)), '2026-11-02');
      // 여름(PDT, UTC-7)
      expect(quotaDay(DateTime.utc(2026, 7, 1, 6, 59)), '2026-06-30');
      expect(quotaDay(DateTime.utc(2026, 7, 1, 7, 0)), '2026-07-01');
    });
  });
}
