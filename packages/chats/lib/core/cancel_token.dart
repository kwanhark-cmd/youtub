/// 오래 걸리는 작업을 중간에 멈추기 위한 표시.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}
