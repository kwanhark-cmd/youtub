import 'strings.dart';

/// 외부 연결이나 작업이 실패한 이유의 종류.
/// 사용자에게는 [AppFailure.userMessage] 와 [AppFailure.nextAction] 만 보여 준다.
enum FailureKind {
  network,
  timeout,
  tokenExpired,
  permissionRevoked,
  quotaExceeded,
  rateLimited,
  costLimit,
  notConnected,
  notFound,
  invalidInput,
  conflict,
  cancelled,
  unknown,
}

/// 다음에 사용자가 할 행동.
enum NextAction { retry, reconnect, tryTomorrow, checkSettings, none }

class AppFailure implements Exception {
  AppFailure(this.kind, [this.detail = '']);

  final FailureKind kind;

  /// 개발자용 내부 설명. 화면에 그대로 보여 주지 않는다. (로그에는 민감정보 제거 후 기록)
  final String detail;

  bool get isRetryable => kind == FailureKind.network || kind == FailureKind.timeout || kind == FailureKind.rateLimited;

  String get userMessage => S.failureMessage(kind);

  NextAction get nextAction {
    switch (kind) {
      case FailureKind.network:
      case FailureKind.timeout:
      case FailureKind.rateLimited:
      case FailureKind.unknown:
        return NextAction.retry;
      case FailureKind.tokenExpired:
      case FailureKind.permissionRevoked:
      case FailureKind.notConnected:
        return NextAction.reconnect;
      case FailureKind.quotaExceeded:
        return NextAction.tryTomorrow;
      case FailureKind.costLimit:
      case FailureKind.invalidInput:
        return NextAction.checkSettings;
      case FailureKind.notFound:
      case FailureKind.conflict:
      case FailureKind.cancelled:
        return NextAction.none;
    }
  }

  @override
  String toString() => 'AppFailure(${kind.name}): $detail';
}

/// 어떤 오류든 [AppFailure] 로 바꾼다.
AppFailure toFailure(Object error) {
  if (error is AppFailure) return error;
  final text = error.toString();
  if (error is FormatException) {
    return AppFailure(FailureKind.unknown, text);
  }
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('HandshakeException') ||
      text.contains('Connection')) {
    return AppFailure(FailureKind.network, text);
  }
  if (text.contains('TimeoutException')) {
    return AppFailure(FailureKind.timeout, text);
  }
  return AppFailure(FailureKind.unknown, text);
}
