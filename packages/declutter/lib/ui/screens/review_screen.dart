import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../services/image_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/celebrate.dart';
import '../widgets/common.dart';

class DetectionBatch {
  final SavedPhoto? photo;
  final List<DetectedItem> items;
  final String? error;
  DetectionBatch(this.photo, this.items, {this.error});
}

/// AI가 찾은 물건 확인: 잘못 본 것 고치기, 놓친 것 추가하기
class ReviewScreen extends StatefulWidget {
  final List<DetectionBatch> batches;
  final String room;
  final String spot;
  final String description;
  final String source;
  const ReviewScreen({super.key, required this.batches, this.room = '', this.spot = '', this.description = '', this.source = 'photo'});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool saving = false;

  int get selectedCount => widget.batches.fold(0, (s, b) => s + b.items.where((i) => i.selected).length);

  Future<void> _save() async {
    final s = context.read<AppState>();
    setState(() => saving = true);
    var n = 0;
    for (final b in widget.batches) {
      for (final d in b.items.where((i) => i.selected)) {
        if (d.name.trim().isEmpty) continue;
        await s.addItem(
          name: d.name,
          kind: d.kind,
          condition: d.condition,
          room: widget.room,
          spot: widget.spot,
          description: widget.description,
          source: widget.source,
          photo: b.photo,
          suggestion: d.suggestion,
          reason: d.reason,
          // 연습 결과 이름을 그대로 쓰면 연습 물건 (실제 물건이 생기면 자동 숨김)
          isPractice: d.practice && d.name.trim() == d.originalName.trim(),
        );
        n++;
      }
    }
    if (!mounted) return;
    celebrate(context, message: '$n개 등록했어요');
    await s.say('$n개를 등록했어요.');
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.read<AppState>();
    return AppPage(
      title: '찾은 물건 확인',
      body: ListView(
        key: const PageStorageKey('review_1'),
        padding: const EdgeInsets.all(AppSizes.page),
        children: [
          const FirstTimeTip(id: 'review', text: '이름이 틀렸으면 눌러서 고치고, 빠진 물건은 "놓친 물건 추가"로 넣으세요. 체크를 끄면 등록하지 않아요.'),
          for (final b in widget.batches) _batch(context, b, p, s),
        ],
      ),
      bottom: BigButton(label: saving ? '저장하는 중…' : '$selectedCount개 등록하기', emoji: 'check', color: p.sell, onTap: saving || selectedCount == 0 ? null : _save),
    );
  }

  Widget _batch(BuildContext context, DetectionBatch b, AppPalette p, AppState s) {
    return Panel(
      border: b.error != null ? p.attention : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (b.photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radiusSmall),
              child: SizedBox(
                height: 180,
                child: ItemPhoto(
                  Item(userId: 0, name: '', createdAt: DateTime(2000), photoPath: b.photo!.photoPath, thumbPath: b.photo!.thumbPath),
                  height: 180,
                  full: true,
                ),
              ),
            ),
          if (b.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Emoji3D('warning', size: 32),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(b.error!, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          for (final d in b.items) _row(d, b, p),
          const SizedBox(height: 8),
          BigButton(
            label: '놓친 물건 추가',
            icon: Icons.add_rounded,
            color: p.primary,
            onTap: () => setState(() => b.items.add(DetectedItem(name: ''))),
          ),
        ],
      ),
    );
  }

  Widget _row(DetectedItem d, DetectionBatch b, AppPalette p) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Checkbox(value: d.selected, onChanged: (v) => setState(() => d.selected = v ?? false)),
              Expanded(
                child: TextFormField(
                  initialValue: d.name,
                  autofocus: d.name.isEmpty && b.error != null,
                  decoration: const InputDecoration(labelText: '이름 (직접 적어 주세요)'),
                  onChanged: (v) => setState(() => d.name = v),
                ),
              ),
              IconButton(tooltip: '빼기', icon: const Icon(Icons.delete_outline_rounded, size: 30), onPressed: () => setState(() => b.items.remove(d))),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 48, top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  initialValue: d.condition,
                  decoration: const InputDecoration(labelText: '상태'),
                  onChanged: (v) => d.condition = v,
                ),
                if (d.suggestion != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('추천:', style: TextStyle(fontSize: 16)),
                        decisionChip(context, d.suggestion),
                        if (d.reason.isNotEmpty) Text(d.reason, style: TextStyle(color: p.muted, fontSize: 15)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
