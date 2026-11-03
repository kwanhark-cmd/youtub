// ★ 최우선: 단독 금고 앱(1.0.0)이 만든 금고를 "기존 앱에서 가져오기"로 옮긴 뒤,
// 통합 앱 위치에서 같은 마스터 비밀번호로 열리고 모든 항목이 그대로인지 확인한다.
import 'dart:convert';
import 'dart:io';

import 'package:account_vault/core/vault/vault.dart';
import 'package:account_vault/data/migrations.dart';
import 'package:account_vault/data/repository.dart';
import 'package:assistant_core/assistant_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_assistant/app/legacy_import.dart';

const fixture = '../../packages/vault/test/fixtures/vault_v1.0.0';
const fixturePassword = 'fixture-master-phrase-1.0.0';
const profileId = '4f44ca4174037170f801757831fcc587';

void copyDir(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final e in from.listSync()) {
    final name = p.basename(e.path);
    if (e is File) e.copySync(p.join(to.path, name));
    if (e is Directory) copyDir(e, Directory(p.join(to.path, name)));
  }
}

void main() {
  late Directory tmp, home, target;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('imp');
    home = Directory(p.join(tmp.path, 'home'))..createSync();
    target = Directory(p.join(tmp.path, 'assistant'))..createSync();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  LegacyImporter imp({String os = 'linux'}) => LegacyImporter(target: target, env: {'HOME': home.path, 'APPDATA': p.join(home.path, 'AppData')}, os: os);

  test('금고 호환: 가져온 금고가 기존 마스터 비밀번호로 열리고 항목이 그대로', () async {
    final old = Directory(p.join(home.path, '.local/share/com.kwanhark.vaultassistant.account_vault/vault_app'));
    copyDir(Directory(fixture), old);
    final originalHashes = {for (final f in old.listSync(recursive: true).whereType<File>()) p.relative(f.path, from: old.path): f.readAsBytesSync().length};

    final found = await imp().discover();
    final src = found.singleWhere((s) => s.module == ModuleId.vault);
    final r = await imp().importOne(src);
    expect(r.ok, isTrue);
    expect(r.message, contains('마스터 비밀번호'));

    final repo = ProfileRepository(Directory(p.join(target.path, 'vault_app', 'store')));
    expect((await repo.list()).single.id, profileId);
    final u = await repo.storeFor(profileId).unlockWithPassword(fixturePassword);
    expect(u, isA<UnlockSuccess>());
    final data = loadVaultData((u as UnlockSuccess).session.data);
    expect(data.accounts.first.password, 'Fixture-Fake-PW-claude-01');
    expect(data.subscriptions.first.cardLast4, '1111');
    expect(await repo.storeFor(profileId).unlockWithPassword('wrong'), isA<UnlockWrongSecret>());

    // 원본은 그대로 (읽기만)
    for (final e in originalHashes.entries) {
      expect(File(p.join(old.path, e.key)).lengthSync(), e.value);
    }
    // 두 번째부터는 "이미 가져왔어요"
    expect((await imp().discover()).singleWhere((s) => s.module == ModuleId.vault).alreadyImported, isTrue);
  });

  test('윈도우·맥 경로에서도 찾는다', () async {
    Directory(p.join(home.path, 'AppData', 'com.binugi', 'binugi', 'binugi'))
      ..createSync(recursive: true)
      ..let((d) => File(p.join(d.path, 'binugi.db')).writeAsStringSync('x'));
    expect((await imp(os: 'windows').discover()).single.module, ModuleId.declutter);
    Directory(p.join(home.path, 'Library/Containers/com.channelbiseo.channelBiseo/Data/Library/Application Support/com.channelbiseo.channelBiseo'))
      ..createSync(recursive: true)
      ..let((d) => File(p.join(d.path, 'users.db')).writeAsStringSync('x'));
    expect((await imp(os: 'macos').discover()).single.module, ModuleId.channel);
  });

  test('채널: 사용자 폴더 전체를 옮기되 임시·기록·남의 폴더는 빼고, 기존 자료는 먼저 백업', () async {
    final old = Directory(p.join(home.path, '.local/share/com.channelbiseo.channel_biseo'))..createSync(recursive: true);
    File(p.join(old.path, 'users.db')).writeAsStringSync('db');
    File(p.join(old.path, 'users', 'u1', 'data.db'))
      ..createSync(recursive: true)
      ..writeAsStringSync('u1');
    File(p.join(old.path, 'logs', 'app.log'))
      ..createSync(recursive: true)
      ..writeAsStringSync('log');
    Directory(p.join(target.path, 'channel_biseo')).createSync();
    File(p.join(target.path, 'channel_biseo', 'users.db')).writeAsStringSync('new-app-data');

    final r = await imp().importOne((await imp().discover()).single);
    expect(r.ok, isTrue);
    expect(File(p.join(target.path, 'channel_biseo', 'users.db')).readAsStringSync(), 'db');
    expect(File(p.join(target.path, 'channel_biseo', 'users', 'u1', 'data.db')).existsSync(), isTrue);
    expect(File(p.join(target.path, 'channel_biseo', 'logs', 'app.log')).existsSync(), isFalse);
    final backups = Directory(p.join(target.path, 'backups')).listSync();
    expect(backups.single.path, contains('channel_biseo_가져오기전'));
    expect(File(p.join(backups.single.path, 'users.db')).readAsStringSync(), 'new-app-data');
  });

  test('대화: 암호 열쇠가 기기 보안 저장소에만 있으면 옮기지 않고 백업 방법을 안내', () async {
    final old = Directory(p.join(home.path, '.local/share/com.aichatorganizer.ai_chat_organizer/ai_chat_organizer'))..createSync(recursive: true);
    File(p.join(old.path, 'users.json')).writeAsStringSync('[]');
    final src = (await imp().discover()).single;
    expect(src.warning, contains('백업 만들기'));
    final r = await imp().importOne(src);
    expect(r.ok, isFalse);
    expect(Directory(p.join(target.path, 'ai_chat_organizer')).existsSync(), isFalse);

    // 열쇠 대체 파일이 함께 있으면 옮긴다
    File(p.join(old.path, '.keys')).writeAsStringSync(base64.encode(utf8.encode(jsonEncode({'datakey-abc': 'x'}))));
    final src2 = (await imp().discover()).single;
    expect(src2.warning, isNull);
    expect((await imp().importOne(src2)).ok, isTrue);
    expect(File(p.join(target.path, 'ai_chat_organizer', '.keys')).existsSync(), isTrue);
  });

  test('아무것도 없으면 빈 목록', () async => expect(await imp().discover(), isEmpty));
}

extension<T> on T {
  void let(void Function(T) f) => f(this);
}
