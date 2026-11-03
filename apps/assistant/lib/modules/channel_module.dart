import 'package:assistant_core/assistant_core.dart';
import 'package:channel_biseo/app/app.dart';
import 'package:channel_biseo/app/services.dart';
import 'package:channel_biseo/assistant_entry.dart';
import 'package:flutter/widgets.dart';

import '../app/assistant_state.dart';
import '../app/keys.dart';
import 'lazy.dart';

class ChannelModule extends PackagedModule {
  /// [openState]: 시험에서 메모리 저장소로 만든 채널 상태를 넣을 때.
  ChannelModule(this.s, {this.openState});
  final AssistantState s;
  final Future<AppState> Function()? openState;

  late final lazy = Lazy<AppState>(() async {
    final st = await (openState?.call() ??
        openChannelState(userName: s.user?.name ?? '나', appVersion: appVersion, skipOnboarding: true));
    await _applyKeys(st);
    return st;
  });

  @override
  ModuleId get id => ModuleId.channel;
  @override
  String get package => 'channel_biseo';

  UserContext? _user(AppState st) => st.user;

  @override
  Future<Widget> open() async {
    final st = await lazy.get();
    await _applyKeys(st); // 그 사이 개인비서 열쇠 화면에서 새로 넣었을 수 있다
    _applyLook(st);
    return channelApp(st);
  }

  /// 개인비서의 글씨 크기·테마를 채널 모듈에도 바로 적용
  void _applyLook(AppState st) {
    final c = s.settings;
    st.setView(themeMode: c.themeMode, highContrast: c.highContrast, reduceMotion: c.reduceMotion);
    st.setTextScale(c.textSize.scale);
  }

  /// 개인비서 공용 열쇠 → 채널 사용자 열쇠 자리 (채널 쪽에 없을 때만). 값은 기록하지 않는다.
  Future<void> _applyKeys(AppState st) async {
    final u = _user(st);
    if (u == null) return;
    try {
      final keys = SharedKeys(s.secrets);
      final g = await keys.googleClient();
      final ai = await keys.ai();
      final higgs = await s.secrets.read(SharedKeys.higgsfield);
      final figma = await s.secrets.read(SharedKeys.figma);
      final done = await applySharedKeys(
        u,
        ChannelSharedKeys(
          googleClientId: g?.clientId,
          googleClientSecret: g?.clientSecret,
          aiProvider: ai?.provider,
          aiKey: ai?.key,
          higgsfieldKey: higgs,
          figmaKey: figma,
        ),
      );
      if (done.isNotEmpty) CoreLog.info('채널 모듈에 공용 열쇠 적용: ${done.join(', ')}');
    } catch (e) {
      CoreLog.warn('채널 모듈 열쇠 적용 실패: ${e.runtimeType}');
    }
  }

  @override
  Future<List<TodayItem>> today() async {
    try {
      final u = _user(await lazy.get().timeout(const Duration(seconds: 3)));
      if (u == null) return const [];
      final lines = await channelToday(u);
      return [
        for (final l in lines) TodayItem(module: id, text: l.text, urgency: l.urgency, actionLabel: l.action),
      ];
    } catch (e) {
      CoreLog.warn('채널 오늘 할 일 실패: ${e.runtimeType}');
      return const [];
    }
  }

  @override
  Future<List<SearchHit>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    try {
      final u = _user(await lazy.get());
      if (u == null) return const [];
      return [
        for (final h in channelSearch(u, query)) SearchHit(module: id, title: h.title, subtitle: h.subtitle, kind: h.kind),
      ];
    } catch (e) {
      CoreLog.warn('채널 검색 실패: ${e.runtimeType}');
      return const [];
    }
  }

  @override
  Future<ModuleReply?> handle(VoiceCommand cmd) async {
    final u = _user(await lazy.get());
    if (u == null) return const ModuleReply('채널 관리를 열게요.', openModule: true);
    final r = await channelVoice(u, cmd.text);
    if (r == null) return null;
    return ModuleReply(r.spoken, needsConfirm: r.needsConfirm, openModule: r.openModule);
  }

  @override
  Future<bool> receive(Suggestion s) async {
    final sg = s;
    if (sg.kind != LinkKind.declutterToChannel && sg.kind != LinkKind.hardToChannel) return false;
    final u = _user(await lazy.get());
    if (u == null) return false;
    return addSuggestedMaterial(
      u,
      title: sg.title,
      detail: sg.detail,
      files: sg.files,
      fromName: sg.from.title,
      // 물건 비우기 사진은 사용자가 직접 찍은 것. 하드에서 찾은 자료는 저작권 확인을 받는다.
      ownMaterial: sg.kind == LinkKind.declutterToChannel,
    );
  }

  @override
  Future<String> statusLine() async {
    try {
      final u = _user(await lazy.get().timeout(const Duration(seconds: 3)));
      if (u == null) return '유튜브·블로그 관리';
      final c = channelCounts(u);
      return '채널 ${c.channels}개 · 확인 대기 ${c.reviewWaiting}개';
    } catch (_) {
      return '유튜브·블로그 관리';
    }
  }

  @override
  Future<Map<String, bool>> checkConnections() async {
    if (!lazy.isLoaded) return const {};
    final u = _user(lazy.value!);
    if (u == null) return const {};
    return {'채널 구글 연결': u.googleConnected, '채널 AI 연결': u.aiConnected};
  }
}
