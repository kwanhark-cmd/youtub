import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_controller.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'nav.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/timeline_screen.dart';
import 'screens/topics_screen.dart';

/// 탭 이동과 "홈에서 검색" 요청을 전하는 곳.
class ShellNav {
  static final tab = ValueNotifier<int>(0);
  static final searchRequest = ValueNotifier<String?>(null);

  static const home = 0, search = 1, topics = 2, timeline = 3, settings = 4;

  /// 어디서든 홈 탭으로(쌓인 화면을 모두 닫고).
  static void goHome() {
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    tab.value = home;
  }

  static void goTab(int i) {
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    tab.value = i;
  }

  /// 홈 검색창에서 찾기 → 찾기 탭으로 넘어가 바로 검색.
  static void openSearch(String text) {
    goTab(search);
    searchRequest.value = text;
  }
}

/// 넓은 화면(컴퓨터)인지
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 1000;

/// 로그인 뒤의 기본 틀. 탭마다 상태를 보존합니다(IndexedStack).
class MainShell extends StatelessWidget {
  const MainShell({super.key});

  static const _items = [
    (Icons.home_rounded, '홈'),
    (Icons.search_rounded, '찾기'),
    (Icons.folder_rounded, '주제'),
    (Icons.calendar_month_rounded, '날짜'),
    (Icons.settings_rounded, '설정'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final p = AppTheme.of(context).palette;
    return ValueListenableBuilder<int>(
      valueListenable: ShellNav.tab,
      builder: (context, index, _) {
        final pages = IndexedStack(
          index: index,
          children: const [
            HomeScreen(),
            SearchScreen(asTab: true),
            TopicsScreen(asTab: true),
            TimelineScreen(asTab: true),
            SettingsScreen(asTab: true),
          ],
        );
        final badge = c.hasUpdateBadge;
        if (isWide(context)) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: (i) => ShellNav.tab.value = i,
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: p.surface,
                  indicatorColor: Color.lerp(p.surface, p.primary, 0.22),
                  minWidth: 88,
                  groupAlignment: -0.9,
                  destinations: [
                    for (final (i, (icon, label)) in _items.indexed)
                      NavigationRailDestination(
                        icon: Badge(isLabelVisible: i == ShellNav.settings && badge, child: Icon(icon, size: 30)),
                        selectedIcon: Icon(icon, size: 30, color: p.primaryText),
                        label: Text(label, style: Theme.of(context).textTheme.labelMedium),
                      ),
                  ],
                ),
                Expanded(child: pages),
              ],
            ),
          );
        }
        return Scaffold(
          body: pages,
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => ShellNav.tab.value = i,
            backgroundColor: p.surface,
            indicatorColor: Color.lerp(p.surface, p.primary, 0.22),
            height: 76,
            destinations: [
              for (final (i, (icon, label)) in _items.indexed)
                NavigationDestination(
                  icon: Badge(isLabelVisible: i == ShellNav.settings && badge, child: Icon(icon, size: 28)),
                  selectedIcon: Icon(icon, size: 28, color: p.primaryText),
                  label: label,
                  tooltip: label,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 탭 화면 높이 안에서 쓰는 간격(아래 탭 메뉴에 가리지 않게).
const bottomSafeGap = SizedBox(height: AppSize.gapXl);
