import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/app/services.dart';
import 'package:channel_biseo/core/failure.dart';
import 'package:channel_biseo/features/youtube/mock_youtube_api.dart';
import 'package:channel_biseo/stages.dart';
import 'package:channel_biseo/ui/common.dart';
import 'package:channel_biseo/ui/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 긴급 수정 (실제 사용 중 발견된 오류) 검증
Future<(TestKit, AppState, UserContext)> start(WidgetTester t, {MockYouTubeApi? yt, bool connect = true}) async {
  registerStages();
  t.view.physicalSize = const Size(320 * 2, 568 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final k = TestKit(yt: yt);
  final s = AppState(k.env);
  await s.login(k.env.accounts.create('긴급', '1234'));
  final u = s.user!;
  u.settings.onboardingDone = true;
  s.setTextScale(1.3);
  if (connect) {
    await u.youtube.connectGoogle();
    for (final c in u.youtube.channels()) {
      await u.youtube.syncChannel(c.channelId);
    }
  }
  await t.pumpWidget(ChannelBiseoApp(state: s));
  await t.pumpAndSettle();
  return (k, s, u);
}

HomeShellState shellOf(WidgetTester t) => t.state<HomeShellState>(find.byType(HomeShell, skipOffstage: false));

/// 화면에 보이는 가장 큰 세로 스크롤의 위치
double scrollPos(WidgetTester t) {
  final list = find.byType(Scrollable).hitTestable().evaluate().map((e) => e as StatefulElement).toList()
    ..sort((a, b) => (b.size!.height).compareTo(a.size!.height));
  return (list.first.state as ScrollableState).position.pixels;
}

Future<void> scrollDown(WidgetTester t, double by) async {
  final list = find.byType(Scrollable).hitTestable().evaluate().toList()
    ..sort((a, b) => (b.size!.height).compareTo(a.size!.height));
  await t.drag(find.byElementPredicate((e) => e == list.first), Offset(0, -by));
  await t.pumpAndSettle();
}

Future<void> tapKey(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.pumpAndSettle();
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

Future<void> openTab(WidgetTester t, IconData icon) async {
  await t.tap(find.byIcon(icon).last);
  await t.pumpAndSettle();
}

void main() {
  group('1. 스크롤 위치 유지', () {
    for (final (name, icon) in [
      ('홈', Icons.dashboard),
      ('채널', Icons.video_library),
      ('제작', Icons.movie_creation),
      ('블로그', Icons.rss_feed),
      ('설정', Icons.settings),
    ]) {
      testWidgets('$name: 자료 갱신·자동 작업 확인·메뉴 오가기 뒤에도 보던 위치 그대로', (t) async {
        final (k, _, u) = await start(t);
        await openTab(t, icon);
        await scrollDown(t, 250);
        final pos = scrollPos(t);
        expect(pos, greaterThan(0), reason: '$name 화면이 스크롤되어야 시험이 의미 있음');
        // 1분마다 도는 확인(브리핑·자동 작업) + 자료 갱신
        await shellOf(t).tick();
        shellOf(t).refreshAll();
        await t.pumpAndSettle();
        expect(scrollPos(t), pos, reason: '$name: 갱신 뒤');
        // 자동 작업이 실제로 돌아도
        u.settings.runnerEnabled = true;
        k.clock.t = DateTime(2026, 11, 3, 3, 0);
        await shellOf(t).tick();
        await t.pumpAndSettle();
        expect(scrollPos(t), pos, reason: '$name: 자동 작업 뒤');
        // 다른 메뉴에 갔다가 돌아와도
        await openTab(t, icon == Icons.dashboard ? Icons.settings : Icons.dashboard);
        await openTab(t, icon);
        expect(scrollPos(t), pos, reason: '$name: 메뉴 오간 뒤');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }

    testWidgets('채널 상세: 뒤에서 자료가 갱신돼도 위치 그대로', (t) async {
      final (_, _, _) = await start(t);
      await openTab(t, Icons.video_library);
      final card = find.byKey(const Key('channel-UC_mock_cook'));
      await t.scrollUntilVisible(card, 150, scrollable: find.byType(Scrollable).hitTestable().first);
      await t.pumpAndSettle();
      await t.tap(card);
      await t.pumpAndSettle();
      await scrollDown(t, 400);
      final pos = scrollPos(t);
      expect(pos, greaterThan(0));
      shellOf(t).refreshAll();
      await shellOf(t).tick();
      await t.pumpAndSettle();
      expect(scrollPos(t), pos);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('2. 실패 창의 "다시 시도"', () {
    testWidgets('연결 실패 → (사이에 자료 갱신) → 다시 시도 → 앱 오류 없이 다시 연결 창', (t) async {
      final (k, _, u) = await start(t, connect: false);
      await openTab(t, Icons.video_library);
      k.mockYt.failNext.addAll([FailureKind.network, FailureKind.network, FailureKind.network]);
      await tapKey(t, 'add-channel');
      await t.tap(find.byKey(const Key('connect-google')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('failure-action')), findsOneWidget);
      // 예전에는 여기서 화면이 새로 만들어져 원래 화면이 사라졌다
      await shellOf(t).tick();
      shellOf(t).refreshAll();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('failure-action')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('채널 등록'), findsWidgets); // 다시 연결 창이 열림
      await t.tap(find.byKey(const Key('connect-google')));
      await t.pumpAndSettle();
      expect(u.youtube.channels().length, 3);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('원래 화면이 이미 사라졌어도 실패 창과 다시 시도가 동작', (t) async {
      final (_, _, _) = await start(t);
      late BuildContext dead;
      final nav = appNavigatorKey.currentState!;
      // ignore: unawaited_futures
      nav.push(
        MaterialPageRoute<void>(
          builder: (c) {
            dead = c;
            return const Scaffold(body: Text('잠깐 화면'));
          },
        ),
      );
      await t.pumpAndSettle();
      nav.pop();
      await t.pumpAndSettle();
      expect(dead.mounted, isFalse);
      var retried = 0;
      // ignore: unawaited_futures
      showFailure(dead, AppFailure(FailureKind.network), onRetry: () => retried++);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('failure-action')));
      await t.pumpAndSettle();
      expect(retried, 1);
      // 사라진 화면으로 확인 창·알림도 오류 없이
      // ignore: unawaited_futures
      confirm(dead, '확인?');
      await t.pumpAndSettle();
      await t.tap(find.text('예'));
      await t.pumpAndSettle();
      toast(dead, '알림');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('3. 처음 실패도 로그에 단계와 함께 남김', () {
    testWidgets('채널 목록 단계 실패 → error 로그 + 실패 창 기록', (t) async {
      final (k, _, _) = await start(t, connect: false);
      await openTab(t, Icons.video_library);
      k.mockYt.failNext.add(FailureKind.permissionRevoked);
      await tapKey(t, 'add-channel');
      await t.tap(find.byKey(const Key('connect-google')));
      await t.pumpAndSettle();
      final log = k.logger.recentLines().join('\n');
      expect(log, contains('[error]'));
      expect(log, contains('구글 연결 실패 [채널 목록]'));
      expect(log, contains('실패 창 [구글 연결]'));
      await t.pumpWidget(const SizedBox());
    });

    test('영상 목록 단계 실패도 기록', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      k.mockYt.failNext.add(FailureKind.permissionRevoked);
      await expectLater(u.youtube.syncChannel('UC_mock_cook'), throwsA(isA<AppFailure>()));
      expect(k.logger.recentLines().join('\n'), contains('[영상 목록]'));
    });
  });

  group('4. 빈 채널', () {
    testWidgets('채널이 없는 구글 계정: 오류 대신 안내 + 다른 계정으로 연결', (t) async {
      final yt = MockYouTubeApi()..noChannels = true;
      final (_, _, u) = await start(t, yt: yt, connect: false);
      await openTab(t, Icons.video_library);
      await tapKey(t, 'add-channel');
      await t.tap(find.byKey(const Key('connect-google')));
      await t.pumpAndSettle();
      expect(find.textContaining('아직 유튜브 채널이 없어요'), findsOneWidget);
      expect(find.byKey(const Key('failure-action')), findsNothing); // 오류 창이 아님
      yt.noChannels = false;
      await t.tap(find.text('다른 계정으로 연결'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('connect-google')));
      await t.pumpAndSettle();
      expect(u.youtube.channels(), isNotEmpty);
      expect(u.youtube.accounts().length, 1); // 빈 계정은 남지 않음
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('영상이 0개인 채널: 등록은 되고 안내', (t) async {
      final (_, _, u) = await start(t, yt: MockYouTubeApi(emptyChannel: true), connect: false);
      await openTab(t, Icons.video_library);
      await tapKey(t, 'add-channel');
      await t.tap(find.byKey(const Key('connect-google')));
      await t.pumpAndSettle();
      expect(find.textContaining('아직 영상이 없는 채널'), findsOneWidget);
      expect(u.youtube.channel('UC_mock_empty'), isNotNull);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('5. 연결 상태 표시 (연습 모드 띠 대신)', () {
    testWidgets('구글·인공지능 상태를 따로 보여 주고, 저장하면 바로 바뀐다', (t) async {
      final (_, s, u) = await start(t);
      expect(find.text('구글: 아직 연결 안 됨'), findsOneWidget);
      expect(find.text('인공지능: 아직 연결 안 됨'), findsOneWidget);
      await u.ai.setKey('sk-ant-test');
      s.refresh();
      await t.pumpAndSettle();
      expect(find.text('인공지능: 연결됨'), findsOneWidget);
      // 실제 구글 계정 + 실제 채널
      final id = u.db.insert(
        "INSERT INTO accounts(provider,label,connected_at,status,mock) VALUES('google','실계정',?, 'ok', 0)",
        [DateTime(2026, 11, 2).toIso8601String()],
      );
      u.db.execute(
        "INSERT INTO channels(account_id, channel_id, title, uploads_playlist, added_at) VALUES(?, 'C_REAL', '진짜 채널', 'UU', '')",
        [id],
      );
      s.refresh();
      await t.pumpAndSettle();
      expect(find.text('구글: 연결됨'), findsOneWidget);
      expect(find.textContaining('연습 모드'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    test('실제 채널이 생기면 가짜 채널은 자동으로 숨고, "연습 자료 보기" 로 다시 보인다', () async {
      final k = TestKit();
      final u = await k.userWithChannels();
      expect(u.youtube.channels().length, 3);
      final id = u.db.insert(
        "INSERT INTO accounts(provider,label,connected_at,status,mock) VALUES('google','실계정','2026-11-02','ok',0)",
      );
      u.db.execute(
        "INSERT INTO channels(account_id, channel_id, title, view_count, uploads_playlist, added_at) VALUES(?, 'C_REAL', '진짜', 7, 'UU', '')",
        [id],
      );
      expect(u.youtube.channels().map((c) => c.channelId), ['C_REAL']);
      expect(u.youtube.totalViews(), 7);
      u.settings.showPracticeData = true;
      expect(u.youtube.channels().length, 4);
    });
  });

  group('6. 문제 신고를 찾기 쉽게', () {
    testWidgets('설정 맨 위에 있고, 오류 창 안에서도 바로 만들 수 있다', (t) async {
      final (k, s, _) = await start(t);
      // 보통 휴대폰 크기·보통 글씨에서 스크롤 없이 보여야 함
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      s.setTextScale(1.0);
      await t.pumpAndSettle();
      await openTab(t, Icons.settings);
      expect(find.byKey(const Key('report-top')).hitTestable(), findsOneWidget);
      await openTab(t, Icons.video_library);
      k.mockYt.failNext.add(FailureKind.permissionRevoked);
      await tapKey(t, 'add-channel');
      await t.tap(find.byKey(const Key('connect-google')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('report-from-error')));
      await t.pumpAndSettle();
      expect(find.textContaining('문제 신고 파일을 만들었어요'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });
}
