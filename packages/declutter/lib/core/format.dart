import 'package:intl/intl.dart';

final _won = NumberFormat('#,###', 'ko');

String won(int? v) => v == null ? '-' : '${_won.format(v)}원';

String wonRange(int? lo, int? hi) {
  if (lo == null && hi == null) return '모름';
  if (lo == hi || hi == null) return won(lo);
  if (lo == null) return won(hi);
  return '${won(lo)} ~ ${won(hi)}';
}

/// 1,000원 단위 반올림
int roundTo1000(num v) => ((v / 1000).round() * 1000).toInt();

String dateKo(DateTime d) => '${d.year}년 ${d.month}월 ${d.day}일';
