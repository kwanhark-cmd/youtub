import 'package:flutter/material.dart';

/// 앱 전체에서 살아 있는 화면·알림줄을 찾기 위한 열쇠.
/// 실패 창을 닫은 뒤 사라진 화면(context)으로 대화상자를 띄우면 앱이 죽는 문제를 막습니다.
final navKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// 살아 있는 context: 받은 것이 살아 있으면 그것, 아니면 앱 최상위 화면
BuildContext? liveContext([BuildContext? c]) {
  if (c != null && c.mounted) return c;
  final top = navKey.currentState?.overlay?.context ?? navKey.currentContext;
  return (top != null && top.mounted) ? top : null;
}
