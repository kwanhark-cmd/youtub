import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../services/gemini_import.dart';
import '../../services/media_picker.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// 제미나이 등에서 정리한 글을 붙여넣기·공유하기로 가져와 확인 후 등록
class ImportScreen extends StatefulWidget {
  final String initialText;
  const ImportScreen({super.key, this.initialText = ''});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  late final text = TextEditingController(text: widget.initialText);
  List<ImportedLine> lines = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialText.isNotEmpty) lines = parseImportText(widget.initialText);
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    var n = 0;
    for (final l in lines.where((l) => l.selected && l.name.trim().isNotEmpty)) {
      await s.addItem(name: l.name, description: l.note, room: l.room, source: 'gemini', suggestion: l.decision, reason: l.decision == null ? '' : '가져온 글의 분류');
      n++;
    }
    if (!mounted) return;
    toast(context, '$n개를 목록에 넣었어요. "정리하기"에서 확정해 주세요.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppPage(
      title: '정리 글 가져오기',
      body: ListView(
        key: const PageStorageKey('import_1'),
        padding: const EdgeInsets.all(AppSizes.page),
        children: [
          Text('제미나이에서 정리한 글이나 다른 앱의 물건 목록 파일을 넣거나, 제미나이 앱에서 "공유하기 → 이 앱"을 누르세요. 가져온 내용은 확인한 뒤에 등록돼요.', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: AppSizes.gap),
          BigButton(
            label: '복사한 글 붙여넣기',
            emoji: 'clipboard',
            color: p.primary,
            onTap: () async {
              final d = await Clipboard.getData('text/plain');
              if (d?.text != null) {
                text.text = d!.text!;
                setState(() => lines = parseImportText(text.text));
              }
            },
          ),
          const SizedBox(height: 8),
          BigButton(
            label: '목록 파일에서 가져오기 (txt·csv)',
            emoji: 'folder',
            color: p.muted,
            onTap: () async {
              final t = await context.read<MediaPicker>().pickTextFile();
              if (t != null) {
                text.text = t;
                setState(() => lines = parseImportText(t));
              }
            },
          ),
          const SizedBox(height: AppSizes.gap),
          TextField(
            controller: text,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(labelText: '정리 글', hintText: '- 커피 머신: 판매\n- 낡은 의자: 폐기'),
          ),
          const SizedBox(height: 8),
          BigButton(label: '글 읽어서 목록 만들기', emoji: 'idea', color: p.progress, onTap: () => setState(() => lines = parseImportText(text.text))),
          if (lines.isNotEmpty) SectionTitle('찾은 물건 ${lines.length}개'),
          for (final l in lines)
            Panel(
              child: Row(
                children: [
                  Checkbox(value: l.selected, onChanged: (v) => setState(() => l.selected = v ?? false)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          initialValue: l.name,
                          decoration: const InputDecoration(labelText: '이름'),
                          onChanged: (v) => l.name = v,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final d in Decision.values)
                              ChoiceChip(
                                label: Text(d.label, style: TextStyle(color: l.decision == d ? Colors.white : null)),
                                selected: l.decision == d,
                                selectedColor: decisionColor(context, d),
                                onSelected: (_) => setState(() => l.decision = l.decision == d ? null : d),
                              ),
                          ],
                        ),
                        if (l.note.isNotEmpty) Text(l.note, style: TextStyle(color: p.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottom: lines.isEmpty ? null : BigButton(label: '${lines.where((l) => l.selected).length}개 확인하고 등록', emoji: 'check', color: p.sell, onTap: _save),
    );
  }
}
