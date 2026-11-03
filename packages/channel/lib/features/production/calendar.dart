import '../../core/db.dart';

/// 달력에 보이는 일 하나.
enum CalKind { made, scheduled, waiting, published, blogWaiting, blogDone }

class CalEvent {
  CalEvent(this.day, this.title, this.kind, {this.productionId});
  final String day; // yyyy-MM-dd
  final String title;
  final CalKind kind;
  final int? productionId;
}

/// 게시 달력: 만든 것·예약(내일 올리기)·확인 대기·공개한 콘텐츠, 블로그 새 글을 날짜별로.
class CalendarService {
  CalendarService(this.db);
  final AppDatabase db;

  static String _d(String iso) => iso.length >= 10 ? iso.substring(0, 10) : iso;

  List<CalEvent> month(int year, int month) {
    final from = dayKey(DateTime(year, month, 1));
    final to = dayKey(DateTime(year, month + 1, 0));
    final out = <CalEvent>[];
    for (final r in db.select('SELECT id, title, status, day, upload_day, updated_at FROM productions')) {
      final status = r['status'] as String;
      final (String day, CalKind kind) = switch (status) {
        'uploadTomorrow' => (
          (r['upload_day'] as String).isEmpty ? r['day'] as String : r['upload_day'] as String,
          CalKind.scheduled,
        ),
        'uploadedPrivate' => (_d(r['updated_at'] as String), CalKind.waiting),
        'doneByUser' => (_d(r['updated_at'] as String), CalKind.published),
        _ => (r['day'] as String, CalKind.made),
      };
      if (day.compareTo(from) >= 0 && day.compareTo(to) <= 0) {
        out.add(CalEvent(day, r['title'] as String, kind, productionId: r['id'] as int));
      }
    }
    final hasBlog = db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='blog_drafts'").isNotEmpty;
    if (hasBlog) {
      for (final r in db.select('SELECT title, status, day FROM blog_drafts WHERE day >= ? AND day <= ?', [from, to])) {
        final s = r['status'] as String;
        out.add(
          CalEvent(
            r['day'] as String,
            r['title'] as String,
            s == 'copyReady' || s == 'draftOnBlogger' ? CalKind.blogWaiting : CalKind.blogDone,
          ),
        );
      }
    }
    out.sort((a, b) => a.day.compareTo(b.day));
    return out;
  }

  Map<String, List<CalEvent>> byDay(int year, int month) {
    final m = <String, List<CalEvent>>{};
    for (final e in this.month(year, month)) {
      m.putIfAbsent(e.day, () => []).add(e);
    }
    return m;
  }
}
