import '../data/models.dart';

/// 음성으로 한 말을 명령으로 바꿈. 폐기·판매 확정은 실행 전에 꼭 확인합니다.
enum VoiceCommandKind { decide, readToday, readProgress, unknown }

class VoiceCommand {
  final VoiceCommandKind kind;
  final Decision? decision;
  final String text;
  VoiceCommand(this.kind, {this.decision, required this.text});
  bool get needsConfirm => kind == VoiceCommandKind.decide && decision != Decision.use;
}

VoiceCommand parseVoiceCommand(String said) {
  final s = said.replaceAll(' ', '');
  if (RegExp(r'폐기|버려|버릴|버리').hasMatch(s)) {
    return VoiceCommand(VoiceCommandKind.decide, decision: Decision.discard, text: said);
  }
  if (RegExp(r'판매|팔아|팔래|팔기|팔자').hasMatch(s)) {
    return VoiceCommand(VoiceCommandKind.decide, decision: Decision.sell, text: said);
  }
  if (RegExp(r'지금쓰|쓰는거|쓸거|사용|남겨|쓸래').hasMatch(s)) {
    return VoiceCommand(VoiceCommandKind.decide, decision: Decision.use, text: said);
  }
  if (RegExp(r'오늘할일|오늘뭐').hasMatch(s)) return VoiceCommand(VoiceCommandKind.readToday, text: said);
  if (RegExp(r'현황|얼마나|진행').hasMatch(s)) return VoiceCommand(VoiceCommandKind.readProgress, text: said);
  return VoiceCommand(VoiceCommandKind.unknown, text: said);
}
