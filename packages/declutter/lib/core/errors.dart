/// AI 관련 오류 종류. 사용자에게 다르게 안내합니다.
enum AiErrorKind { noKey, badKey, recognitionFailed, timeout, budgetExceeded, network, refused, server }

class AiException implements Exception {
  final AiErrorKind kind;
  final String? detail;
  AiException(this.kind, [this.detail]);

  /// 쉬운 한국어 안내 문구
  String get userMessage => switch (kind) {
    AiErrorKind.noKey => 'AI가 연결되어 있지 않아요. 연습 모드로 해 볼게요. (설정 → AI 연결)',
    AiErrorKind.badKey => 'AI 연결 키가 맞지 않아요. 설정 → AI 연결에서 키를 다시 확인해 주세요. 지금은 직접 이름을 적어주세요.',
    AiErrorKind.recognitionFailed => '사진에서 물건을 알아보지 못했어요. 직접 이름을 적어주세요.',
    AiErrorKind.timeout => 'AI 응답이 너무 오래 걸려요. 잠시 뒤 다시 하거나 직접 이름을 적어주세요.',
    AiErrorKind.budgetExceeded => '이번 달 AI 사용 한도에 다다랐어요. 직접 이름을 적거나 설정에서 한도를 늘려주세요.',
    AiErrorKind.network => '인터넷 연결이 불안정해요. 직접 이름을 적어주세요.',
    AiErrorKind.refused => 'AI가 이 사진은 처리하지 않았어요. 직접 이름을 적어주세요.',
    AiErrorKind.server => 'AI 서비스에 문제가 있어요. 직접 이름을 적어주세요.',
  };

  @override
  String toString() => 'AiException($kind)';
}

/// 사용자에게 보여 줄 수 있는 일반 오류
class UserFacingException implements Exception {
  final String message;
  UserFacingException(this.message);
  @override
  String toString() => message;
}
