/// 시간을 바꿔 끼울 수 있게(테스트용) 한 작은 창구.
abstract class Clock {
  const Clock();
  DateTime now();
}

class SystemClock extends Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
}

class FixedClock extends Clock {
  FixedClock(this.current);
  DateTime current;
  @override
  DateTime now() => current;
  void advance(Duration d) => current = current.add(d);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
