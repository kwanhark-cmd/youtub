import 'dart:io';

import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/core/db.dart';
import 'package:channel_biseo/features/edits/edit_service.dart';
import 'package:channel_biseo/stages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 목업 모드 전체 흐름: 채널 등록 → 현황 보기 → 제목 수정 → 되돌리기 → 음성 명령 → 아침 브리핑.
void main() {
  setUpAll(registerStages);

  Future<void> setPhone(WidgetTester t, {double scale = 1.0}) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  Future<void> enter(WidgetTester t, String key, String text) async {
    await t.enterText(find.byKey(Key(key)), text);
    await t.pump();
  }

  Future<void> tap(WidgetTester t, String key) async {
    final f = find.byKey(Key(key));
    if (f.evaluate().isEmpty) {
      // 화면에 보이는 것 중 가장 큰 스크롤 영역(본문 목록)을 내린다
      final all = find.byType(Scrollable).hitTestable().evaluate().toList()
        ..sort((a, b) => (b.size!.width * b.size!.height).compareTo(a.size!.width * a.size!.height));
      await t.scrollUntilVisible(f, 200, scrollable: find.byElementPredicate((e) => e == all.first));
    }
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> back(WidgetTester t) async {
    final dialogs = find.byType(Dialog);
    expect(dialogs, findsNothing, reason: '열린 창이 남아 있음');
    await t.tap(find.byType(BackButton).last);
    await t.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester t, String text) async {
    final f = find.text(text).last;
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  testWidgets('전체 흐름 (휴대폰 화면, 큰 글씨)', (t) async {
    await setPhone(t);
    final k = TestKit();
    final state = AppState(k.env);
    await t.pumpWidget(ChannelBiseoApp(state: state));
    await t.pumpAndSettle();

    // 1) 새 사용자
    await tap(t, 'new-user');
    await enter(t, 'new-name', '김사장');
    await enter(t, 'new-password', '1234');
    await enter(t, 'new-password2', '1234');
    await tap(t, 'new-user-ok');
    expect(find.text('처음 사용 안내'), findsOneWidget);

    // 2) 첫 실행 안내: 글씨 "크게" → 권한(건너뜀) → 계정 연결 → 연습 모드
    await tapText(t, '크게');
    expect(state.textScale, 1.3);
    await tap(t, 'wizard-next');
    await tap(t, 'wizard-next');
    await tap(t, 'wizard-connect');
    await tap(t, 'connect-google'); // 연습 계정으로 연결
    expect(find.textContaining('연결된 채널: 3개'), findsOneWidget);
    await tap(t, 'wizard-next');
    expect(find.textContaining('연습 모드'), findsWidgets);
    await tap(t, 'wizard-next');

    // 3) 현황
    expect(find.text('오늘 남은 유튜브 사용량'), findsOneWidget);
    expect(find.textContaining('연습 모드 —'), findsOneWidget);

    // 4) 채널 목록 → 채널 상세
    await t.tap(find.byIcon(Icons.video_library).last);
    await t.pumpAndSettle();
    await tap(t, 'channel-UC_mock_cook');
    expect(find.textContaining('영상 목록 (120)'), findsOneWidget);
    await tap(t, 'analyze-style');
    expect(find.textContaining('친근한 존댓말'), findsOneWidget);
    await back(t);
    await t.pumpAndSettle();

    // 5) 제목 수정 (미리보기 → 적용)
    await t.tap(find.byIcon(Icons.dashboard).last);
    await t.pumpAndSettle();
    await tap(t, 'run-edits');
    expect(find.text('이렇게 수정할게요'), findsOneWidget);
    await tap(t, 'apply-edits');
    final u = state.user!;
    final applied = u.editLog.list().where((e) => e.status == EditStatus.applied).toList();
    expect(applied.length, 6);

    // 6) 되돌리기
    await tap(t, 'open-edits');
    final target = applied.first;
    await tap(t, 'revert-${target.id}');
    expect(u.editLog.byId(target.id)!.status, EditStatus.reverted);
    expect(k.mockYt.videos[target.targetId]!.title, target.before.title);
    await back(t);
    await t.pumpAndSettle();

    // 7) 음성 명령 (글자 입력으로)
    await tap(t, 'mic');
    await enter(t, 'voice-text', '이번 주 조회수 보여줘');
    await tap(t, 'voice-send');
    expect(find.textContaining('이번 주 전체 조회수'), findsWidgets);
    expect(k.speaker.spoken.last, contains('이번 주 전체 조회수'));
    // 마이크(음성 인식)로도
    k.speechIn.queue = ['메모 다음 영상은 잡채'];
    await tap(t, 'voice-listen');
    expect(u.memos.list().single.text, '다음 영상은 잡채');
    await tap(t, 'voice-close');
    expect(find.text('음성 메모'), findsWidgets); // 메모 화면으로 이동
    await back(t);

    // 8) 아침 브리핑
    await tap(t, 'briefing');
    expect(find.textContaining('좋은 아침이에요'), findsOneWidget);
    expect(u.settings.lastBriefingDay, dayKey(k.clock()));
    await tapText(t, '닫기');

    // 화면 그리기 오류가 하나도 없어야 한다
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('2단계 흐름: 만들기 → 영상 넣기 → 비공개 업로드 확인 → 확인 대기 목록', (t) async {
    await setPhone(t);
    final k = TestKit();
    final state = AppState(k.env);
    await state.login(k.env.accounts.create('제작', '1234'));
    final u = state.user!;
    u.settings.onboardingDone = true;
    await u.youtube.connectGoogle();
    await t.pumpWidget(ChannelBiseoApp(state: state));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.movie_creation).last);
    await t.pumpAndSettle();
    await tap(t, 'produce-new');
    await tap(t, 'format-long');
    await enter(t, 'produce-topic', '전주 비빔밥');
    await tap(t, 'produce-make');
    expect(find.textContaining('전주 비빔밥'), findsWidgets);
    k.pickResult = (File('${Directory.systemTemp.createTempSync('v').path}/a.mp4')..writeAsBytesSync([1])).path;
    await tap(t, 'attach-video');
    expect(find.textContaining('준비됨'), findsOneWidget);
    await tap(t, 'upload');
    expect(find.text('AI 콘텐츠 표시를 확인해 주세요'), findsOneWidget);
    expect(k.speaker.spoken.last, contains('비공개'));
    await tap(t, 'upload-confirm');
    expect(k.mockYt.uploadCalls, 1);
    expect(find.text('유튜브에서 확인하기'), findsOneWidget);
    await back(t);
    await tap(t, 'open-review');
    expect(find.byKey(const Key('review-1')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('3단계 흐름: 티스토리 추가 → 새 글 → 본문 복사', (t) async {
    await setPhone(t);
    String? clip;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clip = (call.arguments as Map)['text'] as String?;
      return null;
    });
    final k = TestKit();
    final state = AppState(k.env);
    await state.login(k.env.accounts.create('블로그', '1234'));
    state.user!.settings.onboardingDone = true;
    await t.pumpWidget(ChannelBiseoApp(state: state));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.rss_feed).last);
    await t.pumpAndSettle();
    await tap(t, 'add-tistory');
    await enter(t, 'tistory-name', '내 티스토리');
    await tap(t, 'tistory-ok');
    await tapText(t, '내 티스토리');
    await tap(t, 'blog-new');
    await enter(t, 'blog-topic', '가을 단풍');
    await tap(t, 'blog-make');
    await tap(t, 'copy-body-1');
    expect(clip, contains('가을 단풍'));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('4단계 흐름: 코너 만들기 → 영상 넣기 → 저작권 확인 → 자동 제작', (t) async {
    await setPhone(t);
    final k = TestKit();
    final state = AppState(k.env);
    await state.login(k.env.accounts.create('코너', '1234'));
    final u = state.user!;
    u.settings.onboardingDone = true;
    await u.youtube.connectGoogle();
    await t.pumpWidget(ChannelBiseoApp(state: state));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.auto_stories).last);
    await t.pumpAndSettle();
    await tap(t, 'corner-new');
    await enter(t, 'corner-name', '사장님의 하루');
    await tap(t, 'corner-ok');
    await tapText(t, '사장님의 하루');
    k.pickResult = (File('${Directory.systemTemp.createTempSync('c').path}/드라마 1화.mp4')..writeAsBytesSync([1])).path;
    await tap(t, 'corner-add-video');
    expect(find.textContaining('저작권이 있을 수 있어요'), findsOneWidget);
    await tapText(t, '네, 사용해도 돼요');
    expect(find.text('사용하기로 함'), findsOneWidget);
    await tap(t, 'corner-make');
    expect(find.textContaining('가지 형식으로 만들었어요'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('아주 큰 글씨 + 작은 화면에서도 모든 메뉴가 잘리지 않는다', (t) async {
    t.view.physicalSize = const Size(320 * 2, 640 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final k = TestKit();
    final state = AppState(k.env);
    final user = k.env.accounts.create('작은화면', '1234');
    await state.login(user);
    state.user!.settings.onboardingDone = true;
    state.setTextScale(1.6);
    await state.user!.youtube.connectGoogle();
    await t.pumpWidget(ChannelBiseoApp(state: state));
    await t.pumpAndSettle();
    final tabs = find.descendant(of: find.byType(NavigationBar), matching: find.byType(NavigationDestination));
    final n = tabs.evaluate().length;
    expect(n, greaterThanOrEqualTo(3));
    for (var i = 0; i < n; i++) {
      await t.tap(tabs.at(i));
      await t.pumpAndSettle();
      // 끝까지 스크롤하며 그리기 오류 확인
      final lists = find.byType(Scrollable);
      if (lists.evaluate().isNotEmpty) {
        await t.drag(lists.first, const Offset(0, -3000));
        await t.pumpAndSettle();
      }
      expect(t.takeException(), isNull, reason: '메뉴 $i');
    }
    expect(MediaQuery.of(t.element(find.byType(NavigationBar))).textScaler.scale(10), 16);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('로그인: 다른 사용자의 자료가 보이지 않는다', (t) async {
    await setPhone(t);
    final k = TestKit();
    final state = AppState(k.env);
    final a = k.env.accounts.create('가', '1111');
    k.env.accounts.create('나', '2222');
    await state.login(a);
    await state.user!.youtube.connectGoogle();
    state.logout();
    await t.pumpWidget(ChannelBiseoApp(state: state));
    await t.pumpAndSettle();
    await tapText(t, '나 님으로 들어가기');
    await enter(t, 'login-password', '1111'); // 틀린 비밀번호
    await tapText(t, '들어가기');
    expect(state.user, isNull);
    await tapText(t, '나 님으로 들어가기');
    await enter(t, 'login-password', '2222');
    await tapText(t, '들어가기');
    expect(state.user!.user.name, '나');
    expect(state.user!.youtube.channels(), isEmpty);
    await t.pumpWidget(const SizedBox());
  });
}
