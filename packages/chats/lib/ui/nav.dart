import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show ScaffoldMessengerState;

/// 앱 전체에서 하나만 쓰는 화면 이동 열쇠.
final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// 살아 있는 화면 정보(context)를 돌려줍니다.
/// 실패 창을 닫은 뒤처럼 [context]가 이미 사라졌으면 앱 전체 화면 정보로 대신합니다.
/// 둘 다 없으면 null → 대화상자를 띄우지 않음(앱이 죽지 않게).
BuildContext? liveContext(BuildContext? context) {
  if (context != null && context.mounted) return context;
  final root = navigatorKey.currentContext;
  if (root != null && root.mounted) return root;
  return null;
}
