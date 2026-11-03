/// 시간 공급자. 테스트에서는 가짜 시계를 넣어 "1년 경과"를 흉내냅니다.
abstract class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
}

class FakeClock implements Clock {
  DateTime current;
  FakeClock(this.current);
  void advance(Duration d) => current = current.add(d);
  @override
  DateTime now() => current;
}

/// 두 시점 사이의 경과 일수. 기기 시간이 뒤로 가도 0 미만이 되지 않음.
int elapsedDays(DateTime from, DateTime now) {
  final d = now.difference(from).inDays;
  return d < 0 ? 0 : d;
}
