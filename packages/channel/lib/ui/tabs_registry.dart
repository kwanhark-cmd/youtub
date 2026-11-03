import 'package:flutter/material.dart';

import '../app/services.dart';
import 'home_shell.dart';

class AppTab {
  AppTab(this.label, this.icon, this.builder, {String? id}) : id = id ?? label;
  final String label;
  final IconData icon;
  final Widget Function(Key key) builder;
  final String id;
}

/// 2~4단계 화면(제작, 블로그, 내 코너)을 메뉴에 붙이는 곳.
class TabsRegistry {
  static final List<AppTab Function(UserContext u, HomeShellState shell)> _tabs = [];
  static final Map<String, void Function(BuildContext, UserContext)> _routes = {};

  static void addTab(AppTab Function(UserContext u, HomeShellState shell) t) => _tabs.add(t);
  static void addRoute(String id, void Function(BuildContext, UserContext) open) => _routes[id] = open;

  static List<AppTab> extraTabs(UserContext u, HomeShellState shell) => [for (final t in _tabs) t(u, shell)];

  static void openRoute(BuildContext context, UserContext u, String id) => _routes[id]?.call(context, u);
}
