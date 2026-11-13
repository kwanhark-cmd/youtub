import 'dart:io';
import 'dart:typed_data';

import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/app/services.dart';
import 'package:channel_biseo/assistant_entry.dart';
import 'package:channel_biseo/core/logger.dart';
import 'package:channel_biseo/core/secret_store.dart';
import 'package:channel_biseo/core/strings.dart';
import 'package:channel_biseo/features/runner/notifier.dart';
import 'package:channel_biseo/features/voice/voice_io.dart';
import 'package:channel_biseo/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 개인비서 안의 안드로이드: 새 버전은 "기존 앱 지우고 설치"라서 앱 안 파일은 함께 지워진다.
/// "백업 만들기"는 저장 창(saveFileAs)으로 앱 밖에 저장하고, 새로 설치한 앱에서 그 파일로 복원할 수 있어야 한다.
void main() {
  AppEnv env(Directory base, Directory docs, {Future<String?> Function(String, Uint8List)? saveFileAs, Future<String?> Function(List<String>)? pickFile}) {
    Directory(base.path).createSync(recursive: true);
    return AppEnv(
      baseDir: base.path,
      documentsDir: docs.path,
      secrets: MemorySecretStore(),
      httpClient: noNetwork(),
      logger: AppLogger(),
      speech: FakeSpeechInput(const []),
      speaker: FakeSpeaker(),
      notifier: MemoryNotifier(),
      isDesktop: false,
      platformName: 'test',
      appVersion: '1.0.0',
      launchUrl: (u) async => true,
      now: () => DateTime(2026, 11, 3, 9),
      osName: 'android',
      saveFileAs: saveFileAs,
      pickFile: pickFile,
    );
  }

  Future<void> openSettings(WidgetTester t, AppState s) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    s.user!.settings.reduceMotion = true;
    await t.pumpWidget(ChannelBiseoApp(state: s));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.settings).last);
    await t.pumpAndSettle();
  }

  Future<void> tapButton(WidgetTester t, String label) async {
    final f = find.text(label);
    await t.scrollUntilVisible(f, 300, scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first);
    await t.pumpAndSettle();
    await t.tap(f);
    // 파일 쓰기·읽기는 진짜 시간이 걸린다.
    for (var i = 0; i < 10; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
  }

  testWidgets('백업 만들기 → 앱 밖 저장 → 앱 지움 → 새로 설치한 앱에서 복원', (t) async {
    final tmp = Directory.systemTemp.createTempSync('cb_export');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final outside = Directory('${tmp.path}/다운로드')..createSync();
    final oldBase = Directory('${tmp.path}/old/support');
    final oldDocs = Directory('${tmp.path}/old/docs')..createSync(recursive: true);
    final saved = <String>[];

    // 1) 기존 앱: 메모 하나 + 백업 만들기 (저장 창에서 "다운로드"를 고름)
    final s = (await t.runAsync(() => openChannelStateWith(
          env(oldBase, oldDocs, saveFileAs: (name, bytes) async {
            final f = File('${outside.path}/$name')..writeAsBytesSync(bytes);
            saved.add(f.path);
            return f.path;
          }),
          userName: '관학',
          skipOnboarding: true,
        )))!;
    s.user!.memos.add('옮길 메모');
    await openSettings(t, s);
    await tapButton(t, S.settingsBackup);
    expect(saved, hasLength(1), reason: '백업을 앱 밖 저장 창으로 넘김');
    expect(find.text(S.settingsBackupDone), findsOneWidget);
    await t.tap(find.text(S.ok));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    s.logout();

    // 2) 기존 앱 지우기: 앱 자료 폴더가 통째로 사라진다. 앱 밖 백업은 남는다.
    Directory('${tmp.path}/old').deleteSync(recursive: true);
    expect(File(saved.single).existsSync(), isTrue);

    // 3) 새로 설치한 앱: 빈 자료 폴더에서 같은 이름으로 들어가 "백업에서 복원"
    final fresh = (await t.runAsync(() => openChannelStateWith(
          env(Directory('${tmp.path}/new/support'), Directory('${tmp.path}/new/docs')..createSync(recursive: true),
              pickFile: (_) async => saved.single),
          userName: '관학',
          skipOnboarding: true,
        )))!;
    expect(fresh.user!.memos.list().map((m) => m.text), isNot(contains('옮길 메모')));
    await openSettings(t, fresh);
    await tapButton(t, S.settingsRestore);
    // 복원은 로그아웃 → 파일 바꾸기 → 다시 로그인. 그 사이 옛 화면이 닫힌 자료를 읽으면 오류가 난다.
    final errors = <String>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.exceptionAsString());
    await t.tap(find.text(S.settingsRestore).last);
    for (var i = 0; i < 10; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
    FlutterError.onError = old;
    expect(errors, isEmpty, reason: '복원 뒤 화면이 닫힌 자료를 읽지 않음');
    expect(fresh.user!.memos.list().map((m) => m.text), contains('옮길 메모'));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('저장 창을 취소하면 "앱 안에만 있어요" 안내', (t) async {
    final tmp = Directory.systemTemp.createTempSync('cb_export_cancel');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final s = (await t.runAsync(() => openChannelStateWith(
          env(Directory('${tmp.path}/support'), Directory('${tmp.path}/docs')..createSync(recursive: true), saveFileAs: (_, _) async => null),
          userName: '관학',
          skipOnboarding: true,
        )))!;
    await openSettings(t, s);
    await tapButton(t, S.settingsBackup);
    expect(find.text(S.settingsBackupInsideTitle), findsOneWidget);
    expect(find.text(S.settingsBackupInsideOnly), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
