import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'item_detail_screen.dart';

/// 알림 모음 (기기 알림을 놓쳐도 여기서 볼 수 있음)
class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});
  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  List<Notice>? list;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    s.allNotices().then((l) {
      if (mounted) setState(() => list = l);
      s.readAllNotices();
    });
  }

  String _emoji(String kind) => switch (kind) {
    'daily' => 'calendar',
    'price_drop' => 'sell',
    'one_year_warn' => 'hourglass',
    'one_year_moved' => 'warning',
    _ => 'bell',
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = list;
    return AppPage(
      title: '알림',
      body: l == null
          ? const Center(child: CircularProgressIndicator())
          : l.isEmpty
          ? const Center(child: EmptyState(message: '아직 알림이 없어요.'))
          : ListView(
              key: const PageStorageKey('notices_1'),
              padding: const EdgeInsets.all(AppSizes.page),
              children: [
                for (final n in l)
                  InkWell(
                    onTap: n.itemId == null ? null : () => go(context, ItemDetailScreen(itemId: n.itemId!)),
                    child: Panel(
                      border: n.readAt == null ? p.attention : null,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Emoji3D(_emoji(n.kind), size: 40),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(n.title, style: Theme.of(context).textTheme.titleMedium),
                                Text(n.body, style: const TextStyle(fontSize: 16)),
                                Text(dateKo(n.createdAt), style: TextStyle(color: p.muted, fontSize: 14)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
