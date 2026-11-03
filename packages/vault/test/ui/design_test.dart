import 'package:account_vault/app/app_controller.dart';
import 'package:account_vault/logic/alerts.dart';
import 'package:account_vault/ui/app.dart';
import 'package:account_vault/ui/screens/accounts_screens.dart';
import 'package:account_vault/ui/screens/cleanup_screens.dart';
import 'package:account_vault/ui/screens/credits_screens.dart';
import 'package:account_vault/ui/screens/mail_screens.dart';
import 'package:account_vault/ui/screens/recovery_code_view.dart';
import 'package:account_vault/ui/screens/settings_screens.dart';
import 'package:account_vault/ui/screens/subscriptions_screens.dart';
import 'package:account_vault/ui/screens/voice_screen.dart';
import 'package:account_vault/ui/theme/tokens.dart';
import 'package:account_vault/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// 디자인 자동 검사:
/// - 가장 작은 화면(360×640) + 가장 큰 글씨(아주 크게) + 밝은/어두운/고대비 모드
/// - 모든 화면에서 잘림·겹침(넘침 오류)이 없어야 한다.
/// - 색 대비 WCAG AA, 움직임 줄이기.

typedef ScreenBuilder = Widget Function(AppController app);

final screens = <String, ScreenBuilder>{
  '구독 목록': (_) => const SubscriptionsScreen(),
  '구독 상세': (a) => SubscriptionDetailScreen(id: a.data.subscriptions.first.id),
  '구독 상세(긴 이름)': (a) =>
      SubscriptionDetailScreen(id: a.data.subscriptions[2].id),
  '구독 추가': (_) => const SubscriptionEditScreen(),
  '만료 알림': (_) => const CreditsScreen(),
  '마감일 수정': (a) => CreditEditScreen(existing: a.data.credits.first),
  '계정 목록': (_) => const AccountsScreen(),
  '계정 상세': (a) => AccountDetailScreen(id: a.data.accounts.first.id),
  '계정 수정': (a) => AccountEditScreen(existing: a.data.accounts.first),
  '비밀번호 만들기': (_) => const GeneratorScreen(),
  '정리 도우미': (_) => const CleanupScreen(),
  '건강 보고서': (_) => const HealthScreen(),
  '음성 비서': (_) => const VoiceScreen(),
  '메일로 채우기': (_) => const MailImportScreen(),
  '설정': (_) => const SettingsScreen(),
  '비밀번호 바꾸기': (_) => const ChangePasswordScreen(),
  '복구 코드 새로': (_) => const NewRecoveryCodeScreen(),
  'AI 연결': (_) => const AiSettingsScreen(),
  '지메일 연결': (_) => const GmailSettingsScreen(),
  '백업': (_) => const BackupScreen(),
  '복구 코드 보기': (_) => const AppPage(
    title: '복구 코드',
    children: [RecoveryCodeView(code: '7K3QD-M9XAT-2B4CE-HJKMN-PQRST')],
  ),
};

Future<TestRig> unlockedRig(
  WidgetTester tester, {
  required String theme,
  required int textLevel,
}) async {
  late TestRig rig;
  await tester.runAsync(() async {
    rig = await TestRig.create();
    final app = rig.controller;
    await app.updateSettings((s) {
      s.autoLockSeconds = 0; // 테스트 중 타이머 없음
      s.themeMode = theme;
      s.textScaleLevel = textLevel;
      s.tipsShown = {};
    });
    await app.createProfile('아주 긴 이름의 테스트 사용자', 'fake-master-phrase-1');
    await app.mutate((d) {
      final s = sampleData(app.now());
      d.subscriptions.addAll(s.subscriptions);
      d.credits.addAll(s.credits);
      d.accounts.addAll(s.accounts);
      markSeen(d, computeAlerts(d, app.now())); // 밀린 알림 창은 따로 검사
    });
  });
  addTearDown(rig.dispose);
  return rig;
}

void setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  const variants = [
    ('light', 2), // 가장 큰 글씨 + 밝게
    ('dark', 2), // 가장 큰 글씨 + 어둡게
    ('contrast', 2), // 가장 큰 글씨 + 고대비
    ('light', 0), // 보통 글씨
  ];

  for (final (theme, level) in variants) {
    for (final size in const [Size(360, 640), Size(360, 9000)]) {
      testWidgets(
        '홈: $theme / 글씨 $level / ${size.width.toInt()}×${size.height.toInt()}',
        (tester) async {
          setSize(tester, size);
          final rig = await unlockedRig(tester, theme: theme, textLevel: level);
          await tester.pumpWidget(VaultApp(controller: rig.controller));
          await settle(tester);
          expect(find.text('잠그기'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        '모든 화면: $theme / 글씨 $level / ${size.width.toInt()}×${size.height.toInt()}',
        (tester) async {
          setSize(tester, size);
          final rig = await unlockedRig(tester, theme: theme, textLevel: level);
          await tester.pumpWidget(VaultApp(controller: rig.controller));
          await settle(tester);
          final nav = tester.state<NavigatorState>(
            find.byType(Navigator).first,
          );
          for (final e in screens.entries) {
            nav.push(
              MaterialPageRoute(builder: (_) => e.value(rig.controller)),
            );
            await settle(tester);
            final err = tester.takeException();
            if (err is FlutterError) debugPrint(err.toStringDeep());
            expect(err, isNull, reason: '"${e.key}" 화면에서 오류: $err');
            nav.pop();
            await settle(tester);
          }
        },
      );
    }

    testWidgets('잠금 화면·첫 실행 마법사: $theme / 글씨 $level / 360×640', (tester) async {
      setSize(tester, const Size(360, 640));
      late TestRig rig;
      await tester.runAsync(() async {
        rig = await TestRig.create();
        await rig.controller.updateSettings((s) {
          s.themeMode = theme;
          s.textScaleLevel = level;
          s.autoLockSeconds = 0;
        });
      });
      addTearDown(rig.dispose);
      await tester.pumpWidget(VaultApp(controller: rig.controller));
      await settle(tester);
      expect(find.text('반가워요!'), findsOneWidget);
      await tester.ensureVisible(find.text('다음'));
      await tester.pump();
      await tester.tap(find.text('다음'));
      await settle(tester);
      expect(find.text('마스터 비밀번호 정하기'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 잠금 화면(사용자 2명)
      await tester.runAsync(() async {
        await rig.controller.createProfile('가', 'fake-master-phrase-1');
        await rig.controller.createProfile('나', 'fake-master-phrase-2');
        rig.controller.endOnboarding();
        await rig.controller.lock();
      });
      await settle(tester);
      expect(find.text('금고가 잠겨 있어요'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('밀린 알림 창(가장 큰 글씨, 360×640)', (tester) async {
    setSize(tester, const Size(360, 640));
    late TestRig rig;
    await tester.runAsync(() async {
      rig = await TestRig.create();
      await rig.controller.updateSettings((s) {
        s.autoLockSeconds = 0;
        s.textScaleLevel = 2;
      });
      await rig.controller.createProfile('a', 'fake-master-phrase-1');
      await rig.controller.mutate(
        (d) => d.credits.addAll(sampleData(rig.controller.now()).credits),
      );
    });
    addTearDown(rig.dispose);
    await tester.pumpWidget(VaultApp(controller: rig.controller));
    await settle(tester);
    expect(find.textContaining('확인할 알림'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('가장 먼저 눈에 띄는 것이 가장 중요한 것: 큰 숫자 > 오늘 할 일 > 이번 주 결제 > 타일 > 상태 띠', (
    tester,
  ) async {
    setSize(tester, const Size(400, 3000));
    final rig = await unlockedRig(tester, theme: 'light', textLevel: 1);
    await tester.pumpWidget(VaultApp(controller: rig.controller));
    await settle(tester);
    // 화면에서 가장 큰 글자 = 이번 달 구독료 숫자
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.data != null && t.style?.fontSize != null)
        .toList();
    texts.sort((a, b) => b.style!.fontSize!.compareTo(a.style!.fontSize!));
    expect(texts.first.data, endsWith('원'));
    expect(find.text('이번 달 구독료'), findsOneWidget);
    double y(String text) => tester.getTopLeft(find.text(text).first).dy;
    expect(y('이번 달 구독료'), lessThan(y('오늘 할 일')));
    expect(y('오늘 할 일'), lessThan(y('이번 주 결제 예정')));
    expect(y('이번 주 결제 예정'), lessThan(y('구독 결제')));
    expect(y('구독 결제'), lessThan(y('연결 상태')));
    // 같은 크기 상자 3개 이상 나란히 없음: 타일은 한 줄에 최대 2개
    final tileTops = <double, int>{};
    for (final e
        in find
            .text('구독 결제')
            .evaluate()
            .followedBy(find.text('계정·비밀번호').evaluate())
            .followedBy(find.text('금고 건강').evaluate())
            .followedBy(find.text('만료 알림').evaluate())) {
      final top = tester.getTopLeft(find.byWidget(e.widget)).dy.roundToDouble();
      tileTops[top] = (tileTops[top] ?? 0) + 1;
    }
    expect(tileTops.values.every((n) => n <= 2), isTrue);
  });

  testWidgets('연결 상태가 저장 즉시 홈에 반영', (tester) async {
    setSize(tester, const Size(400, 3000));
    final rig = await unlockedRig(tester, theme: 'light', textLevel: 1);
    await tester.pumpWidget(VaultApp(controller: rig.controller));
    await settle(tester);
    expect(find.text('지메일: 연결 안 함'), findsOneWidget);
    expect(find.text('AI: 연결 안 함'), findsOneWidget);
    await tester.runAsync(
      () => rig.controller.mutate((d) {
        d.prefs.gmailRefreshToken = 'fake';
        d.prefs.aiApiKey = 'fake';
      }),
    );
    await settle(tester);
    expect(find.text('지메일: 연결됨'), findsOneWidget);
    expect(find.text('AI: 연결됨'), findsOneWidget);
  });

  test('색 테마 4종 × 밝게/어둡게: 주요 버튼·큰 숫자 대비 AA', () {
    for (final base in [AppPalette.light, AppPalette.dark]) {
      for (final theme in AppPalette.colorThemes.keys) {
        final p = base.withColorTheme(theme);
        expect(
          contrastRatio(p.onPrimary, p.primary),
          greaterThanOrEqualTo(4.5),
          reason: '${p.name} 버튼',
        );
        expect(
          contrastRatio(p.primary, p.surface),
          greaterThanOrEqualTo(4.5),
          reason: '${p.name} 글자',
        );
      }
    }
    expect(
      AppPalette.contrast.withColorTheme('plum'),
      same(AppPalette.contrast),
    );
  });

  group('색 대비(WCAG AA)', () {
    for (final p in AppPalette.all) {
      test(p.name, () {
        void aa(Color fg, Color bg, String what, [double min = 4.5]) => expect(
          contrastRatio(fg, bg),
          greaterThanOrEqualTo(min),
          reason:
              '${p.name}: $what ${contrastRatio(fg, bg).toStringAsFixed(2)}',
        );
        for (final bg in [p.background, p.surface, p.surfaceAlt]) {
          aa(p.text, bg, '본문 글자');
          aa(p.textMuted, bg, '흐린 글자');
          for (final k in StatusKind.values) {
            aa(p.status(k), p.surface, '상태색 $k 글자');
          }
        }
        aa(p.onPrimary, p.primary, '주요 버튼');
        aa(p.onAccent, p.accent, '강조 버튼');
        for (final k in StatusKind.values) {
          aa(p.onStatusFill(k), p.statusFill(k), '상태 배지 $k');
        }
        aa(p.text, p.tileTop, '타일 위쪽');
        aa(p.text, p.tileBottom, '타일 아래쪽');
        aa(p.textMuted, p.tileBottom, '타일 설명');
      });
    }
  });

  testWidgets('움직임 줄이기: 애니메이션 시간이 0', (tester) async {
    late Duration d1, d2;
    await tester.pumpWidget(
      AppTheme(
        palette: AppPalette.light,
        reduceMotion: true,
        child: Builder(
          builder: (c) {
            d1 = c.motion(AppTokens.lockAnimation);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpWidget(
      AppTheme(
        palette: AppPalette.light,
        reduceMotion: false,
        child: Builder(
          builder: (c) {
            d2 = c.motion(AppTokens.lockAnimation);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(d1, Duration.zero);
    expect(d2, AppTokens.lockAnimation);
    expect(AppTokens.lockAnimation.inMilliseconds, lessThan(1000));
  });

  test('버튼·터치 크기 규칙', () {
    expect(AppTokens.buttonHeight, greaterThanOrEqualTo(56));
    expect(AppTokens.minTouch, greaterThanOrEqualTo(48));
  });
}
