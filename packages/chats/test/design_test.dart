import 'dart:math' as math;

import 'package:ai_chat_organizer/services/app_controller.dart';
import 'package:ai_chat_organizer/services/settings.dart';
import 'package:ai_chat_organizer/theme/app_theme.dart';
import 'package:ai_chat_organizer/theme/tokens.dart';
import 'package:ai_chat_organizer/ui/screens/conversation_screen.dart';
import 'package:ai_chat_organizer/ui/screens/decisions_screen.dart';
import 'package:ai_chat_organizer/ui/screens/export_guide_screen.dart';
import 'package:ai_chat_organizer/ui/screens/home_screen.dart';
import 'package:ai_chat_organizer/ui/screens/import_screen.dart';
import 'package:ai_chat_organizer/ui/screens/licenses_screen.dart';
import 'package:ai_chat_organizer/ui/screens/problem_report_screen.dart';
import 'package:ai_chat_organizer/ui/screens/profile_screen.dart';
import 'package:ai_chat_organizer/ui/screens/search_screen.dart';
import 'package:ai_chat_organizer/ui/screens/settings_screen.dart';
import 'package:ai_chat_organizer/ui/screens/timeline_screen.dart';
import 'package:ai_chat_organizer/ui/screens/topics_screen.dart';
import 'package:ai_chat_organizer/ui/screens/onboarding_screen.dart';
import 'package:ai_chat_organizer/ui/screens/customize_screen.dart';
import 'package:ai_chat_organizer/ui/screens/gmail_setup_screen.dart';
import 'package:ai_chat_organizer/ui/shell.dart';
import 'package:ai_chat_organizer/ui/widgets/common.dart';
import 'package:ai_chat_organizer/ui/widgets/conversation_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

typedef ScreenBuilder = Widget Function(AppController c);

void main() {
  group('대비 검사(WCAG AA 4.5:1)', () {
    for (final (name, pal) in [
      ('밝게', AppPalette.light),
      ('어둡게', AppPalette.dark),
      ('고대비 밝게', AppPalette.highContrastLight),
      ('고대비 어둡게', AppPalette.highContrastDark),
      for (final t in ColorThemes.names.keys) ...[
        ('색 테마 $t 밝게', ColorThemes.apply(AppPalette.light, t)),
        ('색 테마 $t 어둡게', ColorThemes.apply(AppPalette.dark, t)),
      ],
    ]) {
      test(name, () {
        for (final (fg, bg, label) in pal.contrastPairs) {
          final r = contrast(fg, bg);
          expect(r, greaterThanOrEqualTo(4.5), reason: '$name / $label 대비 ${r.toStringAsFixed(2)}');
        }
      });
    }
  });

  group('화면 잘림 검사(360×640, 아주 큰 글씨)', () {
    int? convId;
    int? topicId;
    final screens = <String, ScreenBuilder>{
      '홈': (_) => const HomeScreen(),
      '검색': (_) => const SearchScreen(initialQuery: '유튜브'),
      '가져오기': (_) => const ImportScreen(),
      '주제': (_) => const TopicsScreen(),
      '주제 안': (_) => TopicDetailScreen(topicId: topicId!),
      '타임라인': (_) => const TimelineScreen(),
      '정한 내용': (_) => const DecisionsScreen(),
      '주제 정한 내용': (_) => TopicDigestScreen(topicId: topicId!),
      '설정': (_) => const SettingsScreen(),
      '대화': (_) => ConversationScreen(id: convId!, highlight: const ['유튜브']),
      '받는 법': (_) => const ExportGuideScreen(),
      '문제 신고': (_) => const ProblemReportScreen(),
      '라이선스': (_) => const LicensesScreen(),
      '사용자 고르기': (_) => const ProfileScreen(),
      '첫 안내': (_) => const OnboardingScreen(),
      '지메일 연결': (_) => const GmailSetupScreen(),
      '앱 꾸미기': (_) => const CustomizeScreen(),
      '탭 틀(홈)': (_) => const MainShell(),
      '찾기 탭(넓으면 목록+본문)': (_) => const SearchScreen(asTab: true, initialQuery: '유튜브'),
      '주제 탭(넓으면 3단)': (_) => const TopicsScreen(asTab: true),
      '주제 안(옆 칸)': (_) => TopicDetailScreen(topicId: topicId!, embedded: true),
      '대화(옆 칸)': (_) => ConversationScreen(id: convId!, embedded: true),
    };
    final modes = <String, void Function(AppSettings)>{
      '밝게': (s) => s.theme = ThemeChoice.light,
      '어둡게': (s) => s.theme = ThemeChoice.dark,
      '고대비': (s) {
        s.theme = ThemeChoice.dark;
        s.highContrast = true;
      },
    };
    for (final size in [const Size(360, 640), const Size(1280, 800), const Size(1600, 900)]) {
      for (final m in modes.entries) {
        testWidgets('${size.width.toInt()}폭 · ${m.key} · 모든 화면', (tester) async {
          await setScreen(tester, size);
          final c = (await tester.runAsync(
            () => readyController(
              settings: (s) {
                s.fontSize = FontSize.xlarge;
                m.value(s);
              },
            ),
          ))!;
          final store = c.session!.store;
          convId = store.list().firstWhere((x) => x.title.contains('유튜브 앱')).id;
          topicId = c.session!.topics.all().first.id;
          for (final e in screens.entries) {
            await tester.pumpWidget(appWith(c, home: e.value(c)));
            for (var i = 0; i < 6; i++) {
              await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
              await tester.pump(const Duration(milliseconds: 120));
            }
            final err = tester.takeException();
            expect(err, isNull, reason: '${e.key} 화면에서 오류/잘림: ${err is FlutterError ? err.toStringDeep() : err}');
            // 위로 끝까지 스크롤해서 긴 화면 아래쪽도 그려 봄
            final scrollables = find.byType(Scrollable);
            if (scrollables.evaluate().isNotEmpty) {
              await tester.drag(scrollables.first, const Offset(0, -3000), warnIfMissed: false);
              await tester.pump(const Duration(milliseconds: 300));
              expect(tester.takeException(), isNull, reason: '${e.key} 화면 아래쪽에서 오류/잘림');
            }
          }
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  });

  testWidgets('움직임 줄이기를 켜면 애니메이션이 꺼진다', (tester) async {
    await setScreen(tester, const Size(800, 1200));
    final c = (await tester.runAsync(() => readyController()))!;
    await tester.pumpWidget(appWith(c, home: const HomeScreen()));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(AnimatedSlide), findsWidgets);
    c.updateSettings((s) => s.reduceMotion = true);
    await tester.pumpWidget(appWith(c, home: const HomeScreen()));
    await tester.pump();
    expect(find.byType(AnimatedSlide), findsNothing);
    final ctx = tester.element(find.byType(HomeScreen));
    expect(AppTheme.of(ctx).motion(ctx, AppMotion.normal), Duration.zero);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('버튼 최소 높이 56, 터치 영역 48 이상', (tester) async {
    await setScreen(tester, const Size(360, 640));
    final c = (await tester.runAsync(() => readyController()))!;
    await tester.pumpWidget(appWith(c, home: const ImportScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    for (final e in find.byType(BigButton).evaluate()) {
      final size = (e.renderObject as RenderBox).size;
      expect(size.height, greaterThanOrEqualTo(AppSize.buttonHeight));
      expect(size.width, greaterThanOrEqualTo(AppSize.minTouch));
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('글씨 크기 설정이 화면에 즉시 적용된다', (tester) async {
    await setScreen(tester, const Size(800, 1200));
    final c = (await tester.runAsync(() => readyController()))!;
    await tester.pumpWidget(appWith(c, home: const HomeScreen()));
    await tester.pump();
    final ctx = tester.element(find.byType(HomeScreen));
    expect(MediaQuery.textScalerOf(ctx).scale(10), 10);
    c.updateSettings((s) => s.fontSize = FontSize.xlarge);
    await tester.pump();
    expect(MediaQuery.textScalerOf(tester.element(find.byType(HomeScreen))).scale(10), 15);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('가장 먼저 눈에 띄는 것이 가장 중요한 것인가: 홈 검색창이 맨 위·가장 크게', (tester) async {
    await setScreen(tester, const Size(390, 844));
    final c = (await tester.runAsync(() => readyController()))!;
    await tester.pumpWidget(appWith(c, home: const HomeScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    final search = tester.getRect(find.byType(TextField).first);
    final today = tester.getRect(find.text('오늘 할 일'));
    final firstTile = tester.getRect(find.byType(ConversationTile).first);
    expect(search.height, greaterThanOrEqualTo(64), reason: '검색창 높이 64 이상');
    expect(search.width, greaterThan(390 * 0.7), reason: '검색창은 화면 폭 거의 전체');
    expect(search.top, lessThan(today.top), reason: '검색창이 오늘 할 일보다 위');
    expect(today.top, lessThan(firstTile.top), reason: '오늘 할 일이 최근 대화보다 위');
    await tester.pumpWidget(const SizedBox());
  });
}
