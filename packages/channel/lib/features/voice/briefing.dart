import '../../core/db.dart';
import '../../core/strings.dart';
import '../ai/ai_service.dart';
import '../edits/edit_service.dart';
import '../settings/user_settings.dart';
import '../youtube/quota.dart';
import '../youtube/youtube_service.dart';

/// 브리핑에 "오늘 할 일" 이나 "만료 임박" 항목을 더하는 곳 (2~4단계 기능이 등록).
typedef BriefingItems = List<String> Function();

class Briefing {
  Briefing(this.yesterday, this.today, this.expiring);
  final List<String> yesterday;
  final List<String> today;
  final List<String> expiring;

  String get spoken {
    final b = StringBuffer('좋은 아침이에요. ');
    b.write('${S.briefingYesterday}. ');
    b.write(yesterday.isEmpty ? '아직 비교할 기록이 없어요. ' : '${yesterday.join('. ')}. ');
    b.write('${S.briefingToday}. ');
    b.write(today.isEmpty ? '특별히 할 일은 없어요. ' : '${today.join('. ')}. ');
    if (expiring.isNotEmpty) b.write('${S.briefingExpiring}. ${expiring.join('. ')}.');
    return b.toString().trim();
  }
}

class BriefingService {
  BriefingService({
    required this.youtube,
    required this.edits,
    required this.ai,
    required this.quota,
    required this.settings,
    required this.now,
  });

  final YouTubeService youtube;
  final EditService edits;
  final AiService ai;
  final QuotaTracker quota;
  final UserSettings settings;
  final DateTime Function() now;
  final List<BriefingItems> todaySources = [];
  final List<BriefingItems> expiringSources = [];

  Briefing compose() {
    final y = <String>[];
    for (final c in youtube.yesterdayChanges()) {
      y.add('${c.title} 조회수 ${c.delta >= 0 ? '+' : ''}${S.num(c.delta)}');
    }
    final yDay = dayKey(now().subtract(const Duration(days: 1)));
    final yEdits = edits.log.countOn(yDay);
    if (yEdits > 0) y.add('어제 영상 $yEdits개를 수정했어요');

    final t = <String>[];
    final chans = youtube.channels();
    final canEdit = chans.fold<int>(0, (s, c) => s + edits.remainingToday(c.channelId));
    if (chans.isEmpty) t.add('먼저 채널을 등록해 주세요');
    if (canEdit > 0) t.add('오늘 영상 $canEdit개까지 다듬을 수 있어요');
    t.add('오늘 남은 유튜브 사용량은 ${S.num(quota.remaining)}이에요');
    for (final s in todaySources) {
      t.addAll(s());
    }

    final e = <String>[];
    for (final a in youtube.expiringAccounts()) {
      final left = 7 - now().difference(a.connectedAt).inDays;
      e.add('${a.label} 연결이 ${left <= 0 ? '오늘' : '$left일 뒤'} 만료돼요. 설정에서 다시 연결해 주세요');
    }
    for (final a in youtube.brokenAccounts()) {
      e.add('${a.label} 연결이 끊어졌어요. 다시 연결해 주세요');
    }
    final limit = settings.monthlyCostLimitUsd;
    if (limit > 0 && ai.hasKey && ai.monthCostUsd >= limit * 0.8) {
      e.add('이번 달 AI 비용이 한도의 80%를 넘었어요');
    }
    for (final s in expiringSources) {
      e.addAll(s());
    }
    return Briefing(y, t, e);
  }

  /// 정한 시간이 지났고 오늘 아직 안 했으면 true.
  bool isDue() {
    if (!settings.briefingEnabled) return false;
    final t = now();
    if (settings.lastBriefingDay == dayKey(t)) return false;
    return t.hour > settings.briefingHour || (t.hour == settings.briefingHour && t.minute >= settings.briefingMinute);
  }

  void markDone() => settings.lastBriefingDay = dayKey(now());
}
