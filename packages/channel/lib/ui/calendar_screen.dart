import 'package:flutter/material.dart';

import '../app/services.dart';
import '../core/db.dart';
import '../core/strings.dart';
import '../features/production/calendar.dart';
import 'common.dart';
import 'produce_screen.dart';

/// 일의 종류 → 공통 상태 색 (만듦=파랑, 예약·확인 대기=노랑, 공개함=초록).
Status calStatus(CalKind k) => switch (k) {
  CalKind.made => Status.progress,
  CalKind.scheduled || CalKind.waiting || CalKind.blogWaiting => Status.check,
  CalKind.published || CalKind.blogDone => Status.done,
};

String calLabel(CalKind k) => switch (k) {
  CalKind.made => S.calMade,
  CalKind.scheduled => S.calScheduled,
  CalKind.waiting => S.calWaiting,
  CalKind.published => S.calPublished,
  CalKind.blogWaiting => S.calBlogWaiting,
  CalKind.blogDone => S.calBlogDone,
};

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.user});
  final UserContext user;
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  UserContext get u => widget.user;
  late DateTime month = DateTime(u.env.now().year, u.env.now().month);
  late String selected = dayKey(u.env.now());

  void _move(int delta) => setState(() {
    month = DateTime(month.year, month.month + delta);
    selected = dayKey(month);
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final events = CalendarService(u.db).byDay(month.year, month.month);
    final first = DateTime(month.year, month.month, 1);
    final daysIn = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday % 7; // 일요일 시작
    final today = dayKey(u.env.now());
    final dayEvents = events[selected] ?? const [];
    return Scaffold(
      appBar: pageBar(context, S.calTitle),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.pagePad,
            AppTokens.gapS,
            AppTokens.pagePad,
            AppTokens.bottomSpace,
          ),
          children: [
            Row(
              children: [
                IconButton(
                  key: const Key('cal-prev'),
                  tooltip: S.calPrev,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _move(-1),
                ),
                Expanded(
                  child: Text(
                    S.calMonth(month.year, month.month),
                    key: const Key('cal-month'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  key: const Key('cal-next'),
                  tooltip: S.calNext,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _move(1),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.gapS),
            Row(
              children: [
                for (final w in S.calWeekdays)
                  Expanded(
                    child: Text(
                      w,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.textSoft, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.gapXs),
            for (var week = 0; week * 7 < lead + daysIn; week++)
              Row(
                children: [
                  for (var dow = 0; dow < 7; dow++)
                    Expanded(child: _cell(t, week * 7 + dow - lead + 1, daysIn, events, today)),
                ],
              ),
            const SizedBox(height: AppTokens.gapM),
            const Wrap(
              spacing: AppTokens.gapS,
              runSpacing: AppTokens.gapS,
              children: [
                StatusBadge(Status.progress, S.calMade),
                StatusBadge(Status.check, S.calCheckLegend),
                StatusBadge(Status.done, S.calPublished),
              ],
            ),
            const SizedBox(height: AppTokens.gapL),
            Text(S.calDay(selected), style: Theme.of(context).textTheme.titleLarge),
            if (dayEvents.isEmpty) const EmptyHint(S.calNothing),
            for (var i = 0; i < dayEvents.length; i++)
              Appear(
                index: i,
                child: ListCard(
                  key: Key('cal-event-$i'),
                  icon: dayEvents[i].kind == CalKind.blogWaiting || dayEvents[i].kind == CalKind.blogDone
                      ? 'blog'
                      : 'create',
                  title: dayEvents[i].title,
                  status: calStatus(dayEvents[i].kind),
                  badge: StatusBadge(calStatus(dayEvents[i].kind), calLabel(dayEvents[i].kind)),
                  onTap: dayEvents[i].productionId == null
                      ? null
                      : () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ProductionDetailScreen(user: u, id: dayEvents[i].productionId!),
                            ),
                          );
                          if (mounted) setState(() {});
                        },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(AppTokens t, int d, int daysIn, Map<String, List<CalEvent>> events, String today) {
    if (d < 1 || d > daysIn) return const SizedBox(height: 56);
    final key = dayKey(DateTime(month.year, month.month, d));
    final list = events[key] ?? const [];
    final isSel = key == selected;
    final isToday = key == today;
    final statuses = {for (final e in list) calStatus(e.kind)}.toList()..sort((a, b) => a.index.compareTo(b.index));
    return Semantics(
      button: true,
      label: S.calCellLabel(d, list.length),
      child: InkWell(
        key: Key('cal-day-$d'),
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        onTap: () => setState(() => selected = key),
        child: Container(
          height: 56,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isSel ? t.primary : (list.isEmpty ? null : t.tonal),
            borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
            border: isToday ? Border.all(color: t.accent, width: 2) : null,
          ),
          child: FittedBox(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.gapXs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$d',
                    style: TextStyle(fontWeight: FontWeight.w800, color: isSel ? t.onPrimary : t.text),
                  ),
                  if (list.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final s in statuses)
                          Container(
                            width: 9,
                            height: 9,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: t.statusColor(s),
                              shape: BoxShape.circle,
                              border: Border.all(color: isSel ? t.onPrimary : t.card, width: 1),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
