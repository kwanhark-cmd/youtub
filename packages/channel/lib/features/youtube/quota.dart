import '../../core/db.dart';
import '../../core/failure.dart';

/// 유튜브 하루 한도는 미국 태평양 시간 자정에 초기화된다.
/// 간단한 미국 서머타임 규칙(3월 둘째 일요일 ~ 11월 첫째 일요일)으로 계산한다.
DateTime pacificTime(DateTime utcOrLocal) {
  final utc = utcOrLocal.toUtc();
  final year = utc.year;
  DateTime nthSunday(int month, int n) {
    var d = DateTime.utc(year, month, 1);
    while (d.weekday != DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return d.add(Duration(days: 7 * (n - 1)));
  }

  // 서머타임 시작: 3월 둘째 일요일 02:00 PST(=10:00 UTC), 끝: 11월 첫째 일요일 02:00 PDT(=09:00 UTC)
  final dstStart = nthSunday(3, 2).add(const Duration(hours: 10));
  final dstEnd = nthSunday(11, 1).add(const Duration(hours: 9));
  final isDst = !utc.isBefore(dstStart) && utc.isBefore(dstEnd);
  return utc.subtract(Duration(hours: isDst ? 7 : 8));
}

String quotaDay(DateTime now) => dayKey(pacificTime(now));

/// 남은 한도 관리. 호출 전에 [reserve] 로 미리 확인·차감한다.
class QuotaTracker {
  QuotaTracker(this.db, {required this.limit, required this.now});
  final AppDatabase db;
  final int Function() limit;
  final DateTime Function() now;

  String get today => quotaDay(now());

  int get used {
    final r = db.select('SELECT used FROM quota_usage WHERE day = ?', [today]);
    return r.isEmpty ? 0 : r.first['used'] as int;
  }

  int get remaining {
    final left = limit() - used;
    return left < 0 ? 0 : left;
  }

  bool canSpend(int units) => remaining >= units;

  /// 한도가 모자라면 [FailureKind.quotaExceeded] 를 던진다.
  void reserve(int units) {
    if (!canSpend(units)) {
      throw AppFailure(FailureKind.quotaExceeded, 'local quota: need $units, left $remaining');
    }
    _add(units);
  }

  /// 호출이 실패해 실제로 쓰이지 않았을 때 되돌려 준다 (네트워크 오류 등).
  void refund(int units) => _add(-units);

  /// 유튜브가 "한도 초과" 라고 답하면 오늘 남은 한도를 0 으로 만든다.
  void markExhausted() {
    final need = limit() - used;
    if (need > 0) _add(need);
  }

  void _add(int units) {
    db.execute(
      'INSERT INTO quota_usage(day, used) VALUES(?, ?) '
      'ON CONFLICT(day) DO UPDATE SET used = MAX(0, used + excluded.used)',
      [today, units < 0 ? 0 : units],
    );
    if (units < 0) {
      db.execute('UPDATE quota_usage SET used = MAX(0, used + ?) WHERE day = ?', [units, today]);
    }
  }
}
