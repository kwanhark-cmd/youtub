import '../../core/db.dart';
import 'youtube_service.dart';

class TrendingVideo {
  TrendingVideo({
    required this.videoId,
    required this.channelId,
    required this.title,
    required this.perDay,
    required this.ratio,
  });
  final String videoId;
  final String channelId;
  final String title;

  /// 최근 하루 평균 늘어난 조회수
  final int perDay;

  /// 같은 채널의 보통 영상보다 몇 배 빠른지
  final double ratio;
}

/// 주목할 영상: 평소보다 조회수가 갑자기 많이 늘어난 내 영상.
/// 영상마다 가장 최근 두 기록 사이의 하루 증가량을 같은 채널 영상들의 중간값과 비교한다.
class TrendingService {
  TrendingService(this.db, this.youtube);
  final AppDatabase db;
  final YouTubeService youtube;

  static const minGainPerDay = 50;
  static const minRatio = 3.0;

  List<TrendingVideo> find({int limit = 3}) {
    final rows = db.select('''
      SELECT s.video_id, s.day, s.view_count, v.channel_id, v.title
      FROM video_stats s JOIN videos v ON v.video_id = s.video_id
      ORDER BY s.video_id, s.day DESC''');
    // 영상별 최근 두 기록
    final latest = <String, List<Map<String, Object?>>>{};
    for (final r in rows) {
      final list = latest.putIfAbsent(r['video_id'] as String, () => []);
      if (list.length < 2) list.add({...r});
    }
    final gains = <String, ({String channelId, String title, double perDay})>{};
    latest.forEach((id, l) {
      if (l.length < 2) return;
      final d1 = DateTime.parse(l[0]['day'] as String), d0 = DateTime.parse(l[1]['day'] as String);
      final days = d1.difference(d0).inDays.clamp(1, 365);
      final g = ((l[0]['view_count'] as int) - (l[1]['view_count'] as int)) / days;
      gains[id] = (channelId: l[0]['channel_id'] as String, title: l[0]['title'] as String, perDay: g);
    });
    // 채널별 보통 증가량 (중간값)
    final byChannel = <String, List<double>>{};
    for (final g in gains.values) {
      byChannel.putIfAbsent(g.channelId, () => []).add(g.perDay);
    }
    double median(List<double> l) {
      final s = [...l]..sort();
      return s.isEmpty ? 0 : s[s.length ~/ 2];
    }

    final base = {for (final e in byChannel.entries) e.key: median(e.value) < 1 ? 1.0 : median(e.value)};
    final out = <TrendingVideo>[];
    gains.forEach((id, g) {
      final b = base[g.channelId] ?? 1;
      final ratio = g.perDay / b;
      if (g.perDay >= minGainPerDay && ratio >= minRatio) {
        out.add(
          TrendingVideo(videoId: id, channelId: g.channelId, title: g.title, perDay: g.perDay.round(), ratio: ratio),
        );
      }
    });
    out.sort((a, b) => b.ratio.compareTo(a.ratio));
    return out.take(limit).toList();
  }

  /// 오래된 기록 정리 (90일 넘은 것).
  void prune(DateTime now) =>
      db.execute('DELETE FROM video_stats WHERE day < ?', [dayKey(now.subtract(const Duration(days: 90)))]);
}
