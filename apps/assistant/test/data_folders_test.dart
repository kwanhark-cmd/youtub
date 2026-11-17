import 'dart:io';

import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_assistant/app/data_folders.dart';
import 'package:personal_assistant/ui/folders_screen.dart';

import 'support.dart';

/// 주인이 알려 준 맥북 폴더 구조 그대로 (/Users/praha/이관학 개인자료/...)
const userFolders = [
  '_클로드분석_20261117', '[세븐스플릿-완성]', '[확정영상-납품]', '개인생활', '법률 사건자료', '영상제작', '외부컴퓨터백업',
  '유튜브관리방', '일반자료', '캡쳐', '프로그램_코드', 'Claude 저장소', 'Gemini 저장소', 'GPT 저장소',
];

Map<String, int> snapshot(Directory d) => {
      for (final e in d.listSync(recursive: true)) p.relative(e.path, from: d.path): e is File ? e.lengthSync() : -1,
    };

void main() {
  late Directory home;
  late String base;
  setUp(() {
    home = Directory.systemTemp.createTempSync('praha');
    base = p.join(home.path, '이관학 개인자료');
    for (final f in userFolders) {
      Directory(p.join(base, f)).createSync(recursive: true);
    }
    File(p.join(base, 'Claude 저장소', 'conversations.json')).writeAsStringSync('[]');
    // 민감 폴더 안의 비슷한 이름은 찾지 않아야 함
    Directory(p.join(base, '법률 사건자료', 'GPT 저장소')).createSync();
    Directory(p.join(base, '외부컴퓨터백업', '유튜브관리방')).createSync();
    // 맥 보호 폴더·숨김 폴더는 열지 않음
    Directory(p.join(home.path, 'Documents', 'Claude 저장소')).createSync(recursive: true);
    Directory(p.join(home.path, '.hidden', '유튜브관리방')).createSync(recursive: true);
    Directory(p.join(home.path, 'Library', 'Claude 저장소')).createSync(recursive: true);
  });
  tearDown(() => home.deleteSync(recursive: true));

  test('알려 준 폴더 구조에서: 대화 저장소 3개 → 대화, 영상 폴더 4개 → 채널, 민감·보호·숨김 폴더는 제외', () {
    final found = DataFolderFinder(home.path).find();
    String rel(FolderMatch m) => p.relative(m.path, from: base);
    expect({for (final m in found.where((m) => m.module == ModuleId.chats)) rel(m)}, {'Claude 저장소', 'Gemini 저장소', 'GPT 저장소'});
    expect({for (final m in found.where((m) => m.module == ModuleId.channel)) rel(m)}, {'[확정영상-납품]', '영상제작', '유튜브관리방', '캡쳐'});
    expect(found.length, 7, reason: found.map(rel).join(', '));
    expect(found.any((m) => m.path.contains('법률') || m.path.contains('외부컴퓨터백업') || m.path.contains('개인생활')), isFalse);
    expect(found.any((m) => m.path.contains('Documents') || m.path.contains('.hidden') || m.path.contains('Library')), isFalse);
  });

  test('찾기만 해도 폴더 이름·위치·파일은 하나도 바뀌지 않음', () {
    final before = snapshot(home);
    DataFolderFinder(home.path).find();
    expect(snapshot(home), before);
  });

  test('이름 판단', () {
    expect(DataFolderFinder.moduleFor('Claude 저장소'), ModuleId.chats);
    expect(DataFolderFinder.moduleFor('챗GPT 내보내기'), ModuleId.chats);
    expect(DataFolderFinder.moduleFor('_클로드분석_20261117'), isNull, reason: '분석 결과 폴더는 대화 내보내기가 아님');
    expect(DataFolderFinder.moduleFor('유튜브관리방'), ModuleId.channel);
    expect(DataFolderFinder.moduleFor('법률 사건자료'), isNull);
    expect(DataFolderFinder.moduleFor('외부컴퓨터백업'), isNull);
    expect(DataFolderFinder.moduleFor('프로그램_코드'), isNull);
  });

  test('연결한 폴더는 설정에 경로만 남고, 끊을 수 있음', () {
    final s = AppSettings(File(p.join(home.path, 's.json')));
    final c = ConnectedFolders(s)
      ..add(ModuleId.chats, '/a')
      ..add(ModuleId.chats, '/a')
      ..add(ModuleId.channel, '/b');
    expect(c.of(ModuleId.chats), ['/a']);
    expect(ConnectedFolders(AppSettings(File(p.join(home.path, 's.json')))).of(ModuleId.channel), ['/b']);
    c.remove(ModuleId.chats, '/a');
    expect(c.of(ModuleId.chats), isEmpty);
  });

  testWidgets('폴더 연결 화면: 찾은 폴더 7개가 모듈 색 표시와 함께 나옴', (t) async {
    t.view.physicalSize = const Size(1080, 4000);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final st = fakeState(home);
    await t.pumpWidget(MaterialApp(home: FoldersScreen(state: st, home: home.path)));
    await t.pumpAndSettle();
    for (final n in ['Claude 저장소', 'Gemini 저장소', 'GPT 저장소', '[확정영상-납품]', '영상제작', '유튜브관리방', '캡쳐']) {
      expect(find.byKey(Key('folder-$n')), findsOneWidget, reason: n);
    }
    expect(find.text('법률 사건자료'), findsNothing);
    expect(find.text('연결하기'), findsNWidgets(7));
    expect(find.text('~/이관학 개인자료/Claude 저장소'), findsOneWidget);
  });
}
