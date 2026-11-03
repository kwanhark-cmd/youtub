import 'dart:convert';
import 'dart:io';

import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/features/youtube/google_setup.dart';
import 'package:channel_biseo/features/youtube/youtube_service.dart';
import 'package:channel_biseo/stages.dart';
import 'package:channel_biseo/ui/google_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 구글 연결 준비 마법사와 JSON 불러오기.
String desktopJson({String id = '123-abc.apps.googleusercontent.com', String secret = 'GOCSPX-test'}) => jsonEncode({
  'installed': {
    'client_id': id,
    'project_id': 'chbiseo',
    'auth_uri': 'https://accounts.google.com/o/oauth2/auth',
    'token_uri': 'https://oauth2.googleapis.com/token',
    'client_secret': secret,
    'redirect_uris': ['http://localhost'],
  },
});

String webJson() => jsonEncode({
  'web': {'client_id': '9-x.apps.googleusercontent.com', 'client_secret': 's'},
});

File tmpFile(String text) {
  final f = File('${Directory.systemTemp.createTempSync('gs').path}/client_secret_1.json');
  f.writeAsStringSync(text);
  return f;
}

void main() {
  group('JSON 읽기', () {
    test('데스크톱 앱 파일 → 앱 번호·비밀 값', () {
      final f = GoogleClientFile.parse(desktopJson());
      expect(f.clientId, '123-abc.apps.googleusercontent.com');
      expect(f.clientSecret, 'GOCSPX-test');
      expect(f.projectId, 'chbiseo');
    });

    test('웹 앱 유형 → 유형이 다름', () {
      expect(
        () => GoogleClientFile.parse(webJson()),
        throwsA(isA<GoogleClientFileError>().having((e) => e.problem, 'problem', GoogleClientFileProblem.wrongType)),
      );
    });

    test('JSON 아님 / 다른 JSON', () {
      expect(
        () => GoogleClientFile.parse('hello'),
        throwsA(isA<GoogleClientFileError>().having((e) => e.problem, 'problem', GoogleClientFileProblem.notJson)),
      );
      expect(
        () => GoogleClientFile.parse('{"a":1}'),
        throwsA(
          isA<GoogleClientFileError>().having((e) => e.problem, 'problem', GoogleClientFileProblem.notClientFile),
        ),
      );
      expect(() => GoogleClientFile.parse(desktopJson(id: 'not-an-id')), throwsA(isA<GoogleClientFileError>()));
    });
  });

  group('화면', () {
    Future<(TestKit, AppState)> open(WidgetTester t) async {
      registerStages();
      t.view.physicalSize = const Size(390 * 2, 844 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final k = TestKit();
      final s = AppState(k.env);
      await s.login(k.env.accounts.create('구글준비', '1234'));
      s.user!.settings.onboardingDone = true;
      await t.pumpWidget(ChannelBiseoApp(state: s));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.settings).last);
      await t.pumpAndSettle();
      return (k, s);
    }

    Future<void> tapKey(WidgetTester t, String key) async {
      final f = find.byKey(Key(key));
      await t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      await t.tap(f);
      await t.pumpAndSettle();
    }

    testWidgets('설정 → 계정 연결 → 마법사: 7단계, 콘솔 열기, JSON 불러오기로 저장, 경고 그림', (t) async {
      final (k, s) = await open(t);
      final opened = <Uri>[];
      // launchUrl 기록 (테스트 env 의 launchUrl 은 true 만 돌려줌) → 단계별 링크 버튼이 있는지만 확인
      await tapKey(t, 'open-google-setup');
      expect(find.byType(GoogleSetupScreen), findsOneWidget);
      expect(find.text('7단계 중 1단계'), findsOneWidget);
      expect(find.text('프로젝트 만들기 열기'), findsOneWidget);
      for (var i = 2; i <= 6; i++) {
        await tapKey(t, 'gs-next');
        expect(find.text('7단계 중 $i단계'), findsOneWidget);
      }
      // 6단계: JSON 불러오기
      k.pickResult = tmpFile(desktopJson()).path;
      await tapKey(t, 'gs-import-json');
      expect(s.user!.settings.googleClientId, '123-abc.apps.googleusercontent.com');
      expect(await s.user!.secrets.read(YouTubeService.googleSecretKey), 'GOCSPX-test');
      expect(
        t.widget<TextField>(find.byKey(const Key('gs-client-id'))).controller!.text,
        contains('apps.googleusercontent'),
      );
      // 비밀 값은 로그에 남지 않음
      expect(k.logger.recentLines().join('\n'), isNot(contains('GOCSPX')));
      // 7단계: 확인되지 않은 앱 그림 (고급 → 이동)
      await tapKey(t, 'gs-next');
      expect(find.byKey(const Key('gs-unverified-pictures')), findsOneWidget);
      expect(find.text('고급'), findsOneWidget);
      expect(find.textContaining('(으)로 이동'), findsWidgets);
      await tapKey(t, 'gs-next'); // 다 했어요
      expect(find.byType(GoogleSetupScreen), findsNothing);
      expect(opened, isEmpty);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('웹 앱 JSON 을 고르면 "유형이 달라요, 데스크톱 앱으로 다시 만들어 주세요"', (t) async {
      final (k, s) = await open(t);
      k.pickResult = tmpFile(webJson()).path;
      await tapKey(t, 'import-google-json');
      expect(find.byKey(const Key('gs-json-error')), findsOneWidget);
      expect(find.textContaining('유형이 달라요, 데스크톱 앱으로 다시 만들어 주세요'), findsOneWidget);
      expect(s.user!.settings.googleClientId, isEmpty);
      await t.tap(find.text('확인'));
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
    });
  });

  for (final contrast in [false, true]) {
    testWidgets('가장 작은 화면 + 아주 큰 글씨 + 어두운 모드${contrast ? ' + 고대비' : ''}: 7단계 모두 잘림 없음', (t) async {
      registerStages();
      t.view.physicalSize = const Size(320 * 2, 568 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final k = TestKit();
      final s = AppState(k.env);
      await s.login(k.env.accounts.create('작은화면', '1234'));
      s.user!.settings.onboardingDone = true;
      s.setTextScale(1.6);
      s.setView(themeMode: 'dark', highContrast: contrast);
      await t.pumpWidget(ChannelBiseoApp(state: s));
      await t.pumpAndSettle();
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      // ignore: unawaited_futures
      nav.push(MaterialPageRoute<void>(builder: (_) => GoogleSetupScreen(user: s.user!)));
      await t.pumpAndSettle();
      for (var i = 1; i <= 7; i++) {
        final list = find.byType(Scrollable).first;
        await t.drag(list, const Offset(0, -4000), warnIfMissed: false);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: '$i단계');
        if (i < 7) {
          await t.tap(find.byKey(const Key('gs-next')));
          await t.pumpAndSettle();
        }
      }
      await t.pumpWidget(const SizedBox());
    });
  }
}
