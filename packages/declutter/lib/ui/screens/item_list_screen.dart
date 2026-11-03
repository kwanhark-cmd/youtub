import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'item_detail_screen.dart';
import 'register_screen.dart';

/// 모든 물건: 분류별 보기, 찾기
class ItemListScreen extends StatefulWidget {
  final Decision? initial;
  final bool undecided;
  const ItemListScreen({super.key, this.initial, this.undecided = false});
  @override
  State<ItemListScreen> createState() => _ItemListScreenState();
}

class _ItemListScreenState extends State<ItemListScreen> {
  late Decision? filter = widget.initial;
  late bool undecided = widget.undecided;
  String query = '';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.palette;
    final q = query.trim();
    final list = s.items.where((i) {
      if (undecided && i.decision != null) return false;
      if (!undecided && filter != null && i.decision != filter) return false;
      if (q.isEmpty) return true;
      return '${i.name} ${i.room} ${i.spot} ${i.tags} ${i.kind}'.contains(q);
    }).toList();
    Widget chip(String label, bool on, Color color, VoidCallback tap) => Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 6),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(fontSize: 16, color: on ? Colors.white : p.onSurface, fontWeight: FontWeight.w700),
        ),
        selected: on,
        selectedColor: color,
        onSelected: (_) => tap(),
      ),
    );
    return AppPage(
      title: '모든 물건',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSizes.page, 0, AppSizes.page, 8),
            child: TextField(
              decoration: const InputDecoration(labelText: '찾기 (이름·방·자리)', prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.page),
            child: Wrap(
              children: [
                chip(
                  '전체',
                  filter == null && !undecided,
                  p.primary,
                  () => setState(() {
                    filter = null;
                    undecided = false;
                  }),
                ),
                chip(
                  '아직 안 정함',
                  undecided,
                  p.progress,
                  () => setState(() {
                    undecided = true;
                    filter = null;
                  }),
                ),
                for (final d in Decision.values)
                  chip(
                    d.label,
                    filter == d && !undecided,
                    decisionColor(context, d),
                    () => setState(() {
                      filter = d;
                      undecided = false;
                    }),
                  ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      child: EmptyState(
                        message: s.items.isEmpty ? '첫 물건을 찍어보세요' : '해당하는 물건이 없어요',
                        buttonLabel: '물건 찍기',
                        onButton: () => go(context, const RegisterScreen()),
                      ),
                    ),
                  )
                : ItemGrid(
                    storageKey: 'item_list_1',
                    items: list,
                    onTap: (it) => go(context, ItemDetailScreen(itemId: it.id!)),
                  ),
          ),
        ],
      ),
    );
  }
}
