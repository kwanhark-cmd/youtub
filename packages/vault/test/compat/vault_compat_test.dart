// ★ 최우선 테스트: 이전 버전(1.0.0)이 만든 금고를 새 버전이 같은 마스터 비밀번호로 열고,
// 모든 항목이 그대로인지 확인한다. 이 테스트가 실패하면 다른 어떤 작업도 진행하지 않는다.
import 'dart:convert';
import 'dart:io';

import 'package:account_vault/core/crypto/vault_crypto.dart';
import 'package:account_vault/core/vault/vault.dart';
import 'package:account_vault/data/migrations.dart';
import 'package:account_vault/data/repository.dart';
import 'package:account_vault/ui/app.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/make_vault_fixture_test.dart'
    show fixtureData, fixturePassword;
import '../support/fakes.dart';

const fixtureDir = 'test/fixtures/vault_v1.0.0';
const profileId = '4f44ca4174037170f801757831fcc587';
const recoveryCode = '11RJG-B052Q-9QPF7-879DA-MJ41H';

/// 기준 파일이 바뀌지 않았는지(누가 다시 만들거나 고치지 않았는지) 확인하는 지문.
const fixtureHashes = {
  'store/profiles/$profileId/header.json':
      'e13bd52570c9513ad9bfed22dea1477845cd2d2d00c7195d1dc91a1134a5dd28',
  'store/profiles/$profileId/vault.enc':
      '49d1ef3d4d29a33edfe4457d3da50089fc3e5a84335b912e30333441bb86117e',
  'backup.vaultbackup':
      '7d797f17af8b586e71dd3cd24b1520b8ece5fe4a03ab7e8971099af70a1f1e43',
};

/// 기준 금고를 임시 폴더로 복사(원본은 건드리지 않음).
Directory copyFixture() {
  final tmp = Directory.systemTemp.createTempSync('compat');
  void copy(Directory from, Directory to) {
    to.createSync(recursive: true);
    for (final e in from.listSync()) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (e is File) e.copySync('${to.path}/$name');
      if (e is Directory) copy(e, Directory('${to.path}/$name'));
    }
  }

  copy(Directory(fixtureDir), tmp);
  return tmp;
}

void main() {
  test('기준 파일이 바뀌지 않았음', () async {
    final c = VaultCrypto();
    for (final e in fixtureHashes.entries) {
      final bytes = File('$fixtureDir/${e.key}').readAsBytesSync();
      expect(
        await c.sha256Hex(bytes),
        e.value,
        reason: '${e.key} 를 수정·재생성하면 안 됩니다',
      );
    }
  });

  test('파일 형식·이름·키 생성 설정이 1.0.0 과 같음', () {
    expect(VaultHeader.format, 'account-vault-header');
    expect(VaultHeader.version, 1);
    expect(VaultStore.dataFormat, 'account-vault-data');
    final h = jsonDecode(
      File('$fixtureDir/store/profiles/$profileId/header.json')
          .readAsStringSync(),
    ) as Map;
    expect(h['kdf'], {'alg': 'argon2id', 'm': 19456, 't': 2, 'p': 1});
    expect(KdfParams.standard.toJson(), h['kdf']);
    final store = VaultStore(
      directory: Directory('$fixtureDir/store/profiles/$profileId'),
    );
    expect(store.headerFile.path.endsWith('header.json'), isTrue);
    expect(store.dataFile.path.endsWith('vault.enc'), isTrue);
    expect(store.prevDataFile.path.endsWith('vault.enc.prev'), isTrue);
  });

  test('1.0.0 금고를 같은 마스터 비밀번호로 열고 모든 항목이 그대로', () async {
    final tmp = copyFixture();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = ProfileRepository(Directory('${tmp.path}/store'));
    final profiles = await repo.list();
    expect(profiles.single.id, profileId);
    expect(profiles.single.name, '기준 사용자');
    final r = await repo
        .storeFor(profileId)
        .unlockWithPassword(fixturePassword);
    expect(r, isA<UnlockSuccess>());
    final loaded = loadVaultData((r as UnlockSuccess).session.data);
    expect(jsonEncode(loaded.toJson()), jsonEncode(fixtureData().toJson()));
    // 대표 항목 직접 확인
    expect(loaded.accounts.first.password, 'Fixture-Fake-PW-claude-01');
    expect(loaded.subscriptions.first.cardLast4, '1111');
    expect(loaded.prefs.gmailRefreshToken, 'fake-refresh-token');
  });

  test('1.0.0 금고: 틀린 비밀번호는 거절, 복구 코드는 동작', () async {
    final tmp = copyFixture();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = ProfileRepository(Directory('${tmp.path}/store'))
        .storeFor(profileId);
    expect(
      await store.unlockWithPassword('wrong-password'),
      isA<UnlockWrongSecret>(),
    );
    final tmp2 = copyFixture();
    addTearDown(() => tmp2.deleteSync(recursive: true));
    final store2 = ProfileRepository(Directory('${tmp2.path}/store'))
        .storeFor(profileId);
    final r = await store2.unlockWithRecoveryCode(recoveryCode);
    expect(r, isA<UnlockSuccess>());
    expect((r as UnlockSuccess).session.mustResetPassword, isTrue);
  });

  test('사용자 목록 파일이 지워져도 금고 폴더를 다시 찾아 열 수 있음', () async {
    final tmp = copyFixture();
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/store/profiles.json').deleteSync();
    final repo = ProfileRepository(Directory('${tmp.path}/store'));
    final list = await repo.list();
    expect(list.single.id, profileId);
    expect(
      await repo.storeFor(profileId).unlockWithPassword(fixturePassword),
      isA<UnlockSuccess>(),
    );
    File('${tmp.path}/store/profiles.json').writeAsStringSync('{망가짐');
    expect((await repo.list()).single.id, profileId);
  });

  test('1.0.0 백업 파일을 새 버전이 검사·확인·복원', () async {
    final tmp = Directory.systemTemp.createTempSync('compat_backup');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = ProfileRepository(Directory('${tmp.path}/store'));
    final svc = BackupService(repo);
    final info = await svc.inspect(
      File('$fixtureDir/backup.vaultbackup').readAsStringSync(),
    );
    expect(info.profileId, profileId);
    expect(await svc.verifyPassword(info, fixturePassword, tmp), isTrue);
    await svc.restore(info, 'test');
    final r = await repo
        .storeFor(profileId)
        .unlockWithPassword(fixturePassword);
    expect(
      jsonEncode(loadVaultData((r as UnlockSuccess).session.data).toJson()),
      jsonEncode(fixtureData().toJson()),
    );
  });

  test('새 버전이 저장해도 1.0.0 형식 그대로(다시 열림)', () async {
    final tmp = copyFixture();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = ProfileRepository(Directory('${tmp.path}/store'))
        .storeFor(profileId);
    final s = (await store.unlockWithPassword(
      fixturePassword,
    ) as UnlockSuccess).session;
    await s.save(s.data);
    s.lock();
    final h = jsonDecode(store.headerFile.readAsStringSync()) as Map;
    expect(h['format'], 'account-vault-header');
    expect(h['kdf'], {'alg': 'argon2id', 'm': 19456, 't': 2, 'p': 1});
    final d = jsonDecode(store.dataFile.readAsStringSync()) as Map;
    expect(d['format'], 'account-vault-data');
    expect(d['v'], 1);
    expect(
      await store.unlockWithPassword(fixturePassword),
      isA<UnlockSuccess>(),
    );
  });

  testWidgets('금고가 이미 있으면 첫 실행 마법사를 건너뛰고 잠금 화면', (tester) async {
    late TestRig rig;
    late Directory tmp;
    await tester.runAsync(() async {
      tmp = copyFixture();
      rig = await TestRig.createAt(tmp);
    });
    addTearDown(() {
      rig.controller.dispose();
      tmp.deleteSync(recursive: true);
    });
    await tester.pumpWidget(VaultApp(controller: rig.controller));
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('반가워요!'), findsNothing);
    expect(find.text('금고가 잠겨 있어요'), findsOneWidget);
    expect(find.text('기준 사용자님의 금고'), findsOneWidget);
  });
}
