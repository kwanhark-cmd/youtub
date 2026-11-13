import 'package:assistant_core/assistant_core.dart';
import 'package:flutter/widgets.dart';
import 'package:metaclean/assistant_entry.dart';

import 'lazy.dart';

/// 6번 "메타지우개 플러스" 모듈: 사진 지우기·사진 수정·문서·구매 기록 네 탭을 단독 앱 그대로 연다.
///
/// - 코드는 apps/metaclean 그대로 (경로 의존성). 단독 앱의 업데이트 확인·띠·ⓘ 업데이트 창은
///   hostedByAssistant 로 숨긴다 (업데이트는 개인비서 설정 하나로).
/// - 따로 저장해 두는 자료가 없어 오늘 할 일·검색·가져오기·백업은 없다.
///   만든 사본은 단독 앱과 같이 임시 폴더·문서 폴더·갤러리("메타지우개", "중고거래 기록" 앨범)에 저장된다.
/// - 음성은 "메타지우개 열어 줘", "사진 위치 정보 지워 줘"처럼 말하면 이 화면을 연다 (지우기는 화면에서 직접).
class MetacleanModule extends PackagedModule {
  /// [app]: 시험에서 화면을 바꿔 끼울 때만 쓴다 (기본은 단독 앱 화면을 hostedByAssistant 로).
  MetacleanModule({Widget Function()? app}) : _app = app ?? metacleanApp;
  final Widget Function() _app;

  @override
  ModuleId get id => ModuleId.metaclean;

  /// 모듈 그림이 없다 (아이콘만 쓰는 화면).
  @override
  String? get package => null;

  @override
  Future<Widget> open() async => _app();

  @override
  Future<String> statusLine() async => '사진·문서 메타데이터 지우기·수정';

  @override
  Future<ModuleReply?> handle(VoiceCommand cmd) async =>
      const ModuleReply('메타지우개 플러스를 열게요. 사진이나 문서를 골라 주세요.', openModule: true);
}
