import 'package:flutter/widgets.dart';

import 'links.dart';

/// 다섯 모듈.
enum ModuleId { channel, chats, harddisk, declutter, vault }

extension ModuleIdName on ModuleId {
  /// 화면에 보이는 이름
  String get title => switch (this) {
        ModuleId.channel => '채널 관리',
        ModuleId.chats => 'AI 대화 기록',
        ModuleId.harddisk => '하드 자료 찾기',
        ModuleId.declutter => '물건 비우기',
        ModuleId.vault => '계정·구독 금고',
      };

  /// 모듈 색 면 (채널=파랑, 대화=보라, 하드=주황, 비우기=초록, 금고=분홍)
  Color get color => switch (this) {
        ModuleId.channel => const Color(0xFF2F6BFF),
        ModuleId.chats => const Color(0xFF7B4DFF),
        ModuleId.harddisk => const Color(0xFFFF8A1F),
        ModuleId.declutter => const Color(0xFF1FA463),
        ModuleId.vault => const Color(0xFFE5488A),
      };

  String get emoji => switch (this) {
        ModuleId.channel => '📺',
        ModuleId.chats => '💬',
        ModuleId.harddisk => '🗄️',
        ModuleId.declutter => '📦',
        ModuleId.vault => '🔐',
      };
}

/// "오늘 할 일" 한 줄.
class TodayItem {
  const TodayItem({required this.module, required this.text, this.urgency = 50, this.due, this.actionLabel});
  final ModuleId module;
  final String text;

  /// 0~100. 클수록 급함. 가장 큰 것 하나가 홈 맨 위에 크게 나온다.
  final int urgency;
  final DateTime? due;
  final String? actionLabel;
}

/// 통합 검색 결과 하나. 비밀번호 같은 비밀 값은 절대 넣지 않는다.
class SearchHit {
  const SearchHit({required this.module, required this.title, this.subtitle, this.kind = ''});
  final ModuleId module;
  final String title;
  final String? subtitle;
  final String kind;
}

/// 음성·글자 명령 하나 (라우터가 모듈을 정한 뒤 모듈에 넘긴다).
class VoiceCommand {
  const VoiceCommand(this.text, {this.intent = ''});
  final String text;
  final String intent;
}

/// 모듈 답. [speak]는 소리로 읽을 말 (비밀번호는 넣지 않는다).
/// [needsConfirm]이 참이면 실행 전에 "정말 할까요?"를 묻는다.
class ModuleReply {
  const ModuleReply(this.speak, {this.needsConfirm = false, this.openModule = false});
  final String speak;
  final bool needsConfirm;
  final bool openModule;
}

/// 본체 앱이 각 모듈과 이야기하는 규격.
abstract class AssistantModule {
  ModuleId get id;

  /// 모듈 화면을 만든다. 처음 누를 때만 불린다(늦게 로드).
  Future<Widget> open();

  /// 홈 타일의 한 줄 상태.
  Future<String> statusLine() async => '눌러서 열기';

  /// 오늘 할 일.
  Future<List<TodayItem>> today() async => const [];

  /// 통합 검색.
  Future<List<SearchHit>> search(String query) async => const [];

  /// 음성 명령 처리. 모르면 null.
  Future<ModuleReply?> handle(VoiceCommand cmd) async => null;

  /// 다른 모듈이 보낸 제안을 사용자가 "받기" 했을 때 이 모듈 자료에 넣는다. 넣었으면 true.
  Future<bool> receive(Suggestion s) async => false;

  /// 연결 상태 화면에 쓸 점검 (이름 → 정상 여부).
  Future<Map<String, bool>> checkConnections() async => const {};
}
