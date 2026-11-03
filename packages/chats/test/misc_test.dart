import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_organizer/core/app_info.dart';
import 'package:ai_chat_organizer/core/app_log.dart';
import 'package:ai_chat_organizer/services/backup_service.dart';
import 'package:ai_chat_organizer/services/export_service.dart';
import 'package:ai_chat_organizer/services/settings.dart';
import 'package:ai_chat_organizer/services/user_service.dart';
import 'package:ai_chat_organizer/voice/voice_command.dart';
import 'package:ai_chat_organizer/data/topic_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_env.dart';

void main() {
  group('음성 명령', () {
    test('지시서의 예문', () {
      expect((VoiceCommandParser.parse('이 대화를 앱 만들기 주제로 옮겨') as MoveToTopicCommand).topic, '앱 만들기');
      expect(VoiceCommandParser.parse('오늘 가져온 대화 정리해 줘'), isA<ClassifyRecentCommand>());
      expect((VoiceCommandParser.parse('메모 다음 주에 다시 보기') as AddNoteCommand).text, '다음 주에 다시 보기');
      expect((VoiceCommandParser.parse('예산은 백만 원이라고 메모해 줘') as AddNoteCommand).text, '예산은 백만 원');
      final m = VoiceCommandParser.parse('여행 주제를 휴가 주제로 합쳐') as MergeTopicsCommand;
      expect((m.from, m.into, m.needsConfirm), ('여행', '휴가', true));
      expect(VoiceCommandParser.parse('이 대화 지워 줘').needsConfirm, isTrue);
      expect(VoiceCommandParser.parse('읽어 줘'), isA<ReadAloudCommand>());
      expect(VoiceCommandParser.parse('그만'), isA<StopReadingCommand>());
      expect(VoiceCommandParser.parse('지난달에 유튜브 앱 얘기한 대화 찾아줘'), isA<SearchCommand>());
    });
  });

  test('설정 저장·읽기와 내보내기 알림 시기', () {
    final dir = Directory.systemTemp.createTempSync('set');
    final f = File('${dir.path}/s.json');
    final s = AppSettings()
      ..fontSize = FontSize.xlarge
      ..highContrast = true
      ..lastExportRequest = {'claude': DateTime(2026, 10, 30)};
    s.save(f);
    final r = AppSettings.load(f);
    expect(r.fontSize, FontSize.xlarge);
    expect(r.highContrast, isTrue);
    final due = r.exportDue(DateTime(2026, 11, 3));
    expect(due.map((e) => e.name), ['chatgpt', 'gemini']);
    expect(AppSettings.load(File('${dir.path}/없음.json')).fontSize, FontSize.normal);
    File('${dir.path}/깨짐.json').writeAsStringSync('{{{');
    expect(AppSettings.load(File('${dir.path}/깨짐.json')).aiMode, AiMode.searchOnly);
  });

  test('여러 사용자: 비밀번호와 분리', () {
    final dir = Directory.systemTemp.createTempSync('users');
    final us = UserService(dir);
    final a = us.create('엄마', pin: '1234');
    final b = us.create('아빠');
    expect(us.load().length, 2);
    expect(us.checkPin(a, '1234'), isTrue);
    expect(us.checkPin(a, '0000'), isFalse);
    expect(us.checkPin(b, ''), isTrue);
    expect(us.dirOf(a.id).path, isNot(us.dirOf(b.id).path));
    us.remove(a.id);
    expect(us.load().single.name, '아빠');
  });

  test('백업 만들기 → 되살리기', () async {
    final s = await storeWithSamples();
    final t = TopicStore(s.db);
    final topic = t.create('보관');
    final first = s.list().first;
    t.setOrigin(first.id, topic, 'user');
    s.addTag(first.id, '중요');
    await s.addNote(first.id, '비밀 메모');
    final bytes = await BackupService.create(s, '비밀번호123', settings: {'fontSize': 'large'});
    expect(utf8.decode(bytes, allowMalformed: true).contains('비밀 메모'), isFalse);
    final other = memoryStore();
    final settings = await BackupService.restore(other, bytes, '비밀번호123');
    expect(settings!['fontSize'], 'large');
    expect(other.count(), s.count());
    expect(other.tagsOf(first.id), ['중요']);
    expect((await other.notes(first.id)).single.text, '비밀 메모');
    expect(TopicStore(other.db).topicsOf(first.id).single.name, '보관');
    expect(() => BackupService.restore(other, bytes, '틀림'), throwsA(anything));
  });

  test('로그에는 키·본문이 남지 않는다', () {
    final dir = Directory.systemTemp.createTempSync('log');
    AppLog.init(File('${dir.path}/a.log'));
    AppLog.info('키 저장 sk-ant-api03-ABCDEF123456', {'text': '대화 본문', 'apiKey': 'sk-ant-xyz', 'count': 3});
    final line = AppLog.recent().last;
    expect(line.contains('ABCDEF'), isFalse);
    expect(line.contains('대화 본문'), isFalse);
    expect(line.contains('sk-ant-xyz'), isFalse);
    expect(line.contains('count=3'), isTrue);
  });

  test('대화 내보내기(마크다운·글자·PDF)', () async {
    final s = await storeWithSamples();
    final c = s.list().firstWhere((x) => x.title.contains('세븐 스플릿'));
    final msgs = await s.messages(c.id);
    final md = ExportService.markdown(c, msgs);
    expect(md, contains('# ${c.title}'));
    expect(md, contains('첨부: 참고자료.pdf'));
    expect(ExportService.plainText(c, msgs), contains('[나]'));
    final pdf = await ExportService.pdf(
      c,
      msgs,
      regularFont: ByteData.sublistView(File('assets/fonts/NanumGothic-Regular.ttf').readAsBytesSync()),
      boldFont: ByteData.sublistView(File('assets/fonts/NanumGothic-Bold.ttf').readAsBytesSync()),
    );
    expect(String.fromCharCodes(pdf.sublist(0, 4)), '%PDF');
    expect(ExportService.safeFileName('a/b:c?'), 'a b c');
  });

  test('앱 버전이 pubspec과 같다', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    expect(pub, contains('version: ${AppInfo.version}+${AppInfo.build}'));
  });

  group('안전 검사(코드 훑어보기)', () {
    final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

    test('파일을 지우거나 쓰는 코드는 앱 자기 폴더용 파일에만 있다', () {
      const allowed = {
        'lib/core/app_log.dart', // 로그 파일
        'lib/services/settings.dart', // 설정 파일
        'lib/services/user_service.dart', // 사용자 목록·사용자 폴더
        'lib/data/key_store.dart', // 키 대체 파일
        'lib/ui/widgets/file_actions.dart', // 임시 폴더에 공유용 새 파일
        'lib/services/app_controller.dart', // 사용자 폴더 안 backups의 오래된 업데이트 전 백업 정리
        'lib/ui/screens/customize_screen.dart', // 사용자가 고른 사진의 복사본을 앱 자기 폴더에(원본은 그대로)
        'lib/services/update_service.dart', // 업데이트: 임시 폴더에 내려받기, 앱 자신의 실행 파일만 교체
      };
      final pattern = RegExp(
        r'\.(deleteSync|writeAsBytes|writeAsBytesSync|writeAsString|writeAsStringSync|renameSync|openWrite)\(|(File|Directory)\([^)]*\)\.(delete|rename)\(',
      );
      for (final f in files) {
        final rel = f.path.replaceAll('\\', '/');
        if (pattern.hasMatch(f.readAsStringSync())) {
          expect(allowed.contains(rel), isTrue, reason: '$rel 에서 파일 쓰기/지우기 발견');
        }
      }
    });

    test('가져오기는 파일을 읽기만 한다', () {
      final src =
          File('lib/services/app_controller.dart').readAsStringSync() + File('lib/ui/screens/import_screen.dart').readAsStringSync();
      expect(RegExp(r'File\([^)]*\)\.(write|delete|rename)').hasMatch(src), isFalse);
    });

    test('화면 문구는 한국어(영문 문장 없음)', () {
      // 따옴표 안 글자 중 화면에 보일 만한 것만 검사(경로·코드 이름·주소는 제외)
      final literal = RegExp(r"'([^'\\]*(?:\\.[^'\\]*)*)'");
      final allowWords = RegExp(r'^(GPT|PDF|md|txt|pdf|zip|json|html|AI|OS|MIT|SIL|API|OAuth|ID|JSON|ico|png)$');
      final problems = <String>[];
      for (final f in files.where((f) => f.path.contains('lib/ui/'))) {
        for (final m in literal.allMatches(f.readAsStringSync())) {
          final s = m.group(1)!;
          if (!RegExp(r'[가-힣]').hasMatch(s)) continue; // 한국어가 없는 글자는 화면 문구가 아님(경로·키 등)
          if (s.contains('yyyy')) continue; // 날짜 형식
          if (s.contains(r'${') && (s.contains('(') || s.contains('?'))) continue; // 따옴표가 섞인 코드 조각
          final latinWords = RegExp(r'[A-Za-z]{2,}')
              .allMatches(s.replaceAll(RegExp(r'\$\{[^}]*\}|\$[A-Za-z_]+|https?://\S+|[a-z]+\.[a-z.]+'), ''))
              .map((e) => e.group(0)!)
              .where((w) => !allowWords.hasMatch(w));
          if (latinWords.isNotEmpty) problems.add('${f.path}: $s');
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  });
}
