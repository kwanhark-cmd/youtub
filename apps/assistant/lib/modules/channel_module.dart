import 'package:assistant_core/assistant_core.dart';
import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/assistant_entry.dart';
import 'package:flutter/widgets.dart';

import '../app/assistant_state.dart';
import 'lazy.dart';

class ChannelModule extends PackagedModule {
  ChannelModule(this.s);
  final AssistantState s;
  late final lazy = Lazy<AppState>(() => openChannelState(userName: s.user?.name ?? '나', appVersion: appVersion));

  @override
  ModuleId get id => ModuleId.channel;
  @override
  String get package => 'channel_biseo';

  @override
  Future<Widget> open() async {
    final st = await lazy.get();
    _applyLook(st);
    return channelApp(st);
  }

  /// 개인비서의 글씨 크기·테마를 채널 모듈에도 바로 적용
  void _applyLook(AppState st) {
    final c = s.settings;
    st.setView(themeMode: c.themeMode, highContrast: c.highContrast, reduceMotion: c.reduceMotion);
    st.setTextScale(c.textSize.scale);
  }

  @override
  Future<String> statusLine() async => lazy.isLoaded ? '열려 있어요' : '유튜브·블로그 관리';
}
