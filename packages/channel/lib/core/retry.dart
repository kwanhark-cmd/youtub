import 'dart:async';

import 'failure.dart';

/// 취소 신호. 긴 작업에서 사용자가 "취소" 를 누르면 [cancel] 을 부른다.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw AppFailure(FailureKind.cancelled, 'cancelled');
  }
}

typedef Sleeper = Future<void> Function(Duration d);

Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

/// 시간 제한 + 재시도(최대 [maxAttempts] 회, 간격은 점점 늘림).
/// 재시도할 수 있는 오류(네트워크, 시간 초과, 잠시 요청이 많음)만 다시 시도한다.
Future<T> withRetry<T>(
  Future<T> Function() action, {
  int maxAttempts = 3,
  Duration timeout = const Duration(seconds: 30),
  Duration baseDelay = const Duration(seconds: 1),
  Sleeper sleep = _realSleep,
  CancelToken? cancel,
}) async {
  var attempt = 0;
  while (true) {
    attempt++;
    cancel?.throwIfCancelled();
    try {
      return await action().timeout(timeout, onTimeout: () => throw AppFailure(FailureKind.timeout, 'timeout'));
    } catch (e) {
      final failure = toFailure(e);
      if (!failure.isRetryable || attempt >= maxAttempts) throw failure;
      // 1초, 2초, 4초 ... 로 간격을 늘린다.
      await sleep(baseDelay * (1 << (attempt - 1)));
    }
  }
}
