import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_theme.dart';
import 'docs/doc_meta.dart';

class _Job {
  const _Job(this.bytes, this.edit);
  final Uint8List bytes;
  final DocEdit? edit;
}

class _JobResult {
  const _JobResult(this.bytes, this.notes, this.after);
  final Uint8List bytes;
  final List<String> notes;
  final Map<String, String> after;
}

/// 큰 문서도 화면이 멈추지 않게 따로 돌린다.
_JobResult _work(_Job job) {
  final out = cleanDocument(job.bytes, edit: job.edit);
  return _JobResult(out.bytes, out.notes, readDocMeta(out.bytes));
}

Map<String, String> _read(Uint8List bytes) => readDocMeta(bytes);

/// 문서(PDF·한글·워드)의 메타데이터를 지우거나 일부만 고친다.
class DocScreen extends StatefulWidget {
  const DocScreen({super.key});

  @override
  State<DocScreen> createState() => _DocScreenState();
}

class _DocScreenState extends State<DocScreen> {
  final _titleCtrl = TextEditingController();
  final _authorCtrl = TextEditingController();
  final _programCtrl = TextEditingController();

  String? _name;
  Uint8List? _bytes;
  String? _kindLabel;
  Map<String, String> _before = const {};

  bool _editMode = false;
  bool _setTitle = false;
  bool _setAuthor = false;
  bool _setDate = false;
  bool _setProgram = false;
  DateTime _date = DateTime.now();

  bool _busy = false;
  String? _outPath;
  Uint8List? _outBytes;
  Map<String, String> _after = const {};
  List<String> _notes = const [];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _programCtrl.dispose();
    super.dispose();
  }

  void _say(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    final f = files.first;
    Uint8List? bytes;
    try {
      bytes = await f.readAsBytes();
    } catch (_) {
      final path = f.path;
      if (path != null) bytes = await File(path).readAsBytes();
    }
    if (!mounted) return;
    if (bytes == null) {
      _say('파일을 읽지 못했어요');
      return;
    }
    final kind = detectDocKind(bytes);
    if (kind == null) {
      _say('지원하지 않는 파일이에요. PDF·한글(hwp, hwpx)·워드(docx, doc) 문서를 골라 주세요.');
      return;
    }
    setState(() => _busy = true);
    Map<String, String> before = const {};
    String? error;
    try {
      before = await compute(_read, bytes);
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error != null) return;
      _name = f.name;
      _bytes = bytes;
      _kindLabel = docKindLabel(kind, f.name);
      _before = before;
      _titleCtrl.text = before['제목'] ?? '';
      _authorCtrl.text = before['작성자'] ?? '';
      _programCtrl.text = before['만든 프로그램'] ??
          before['프로그램'] ??
          before['버전 정보'] ??
          '';
      _setTitle = _setAuthor = _setDate = _setProgram = false;
      _date = DateTime.now();
      _outPath = null;
      _outBytes = null;
      _after = const {};
      _notes = const [];
    });
    if (error != null) _say(error);
  }

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (!mounted) return;
    setState(() {
      _date = DateTime(d.year, d.month, d.day, t?.hour ?? _date.hour,
          t?.minute ?? _date.minute);
    });
  }

  Future<void> _run() async {
    final bytes = _bytes;
    final name = _name;
    if (bytes == null || name == null) return;
    DocEdit? edit;
    if (_editMode) {
      edit = DocEdit(
        title: _setTitle ? _titleCtrl.text.trim() : null,
        author: _setAuthor ? _authorCtrl.text.trim() : null,
        date: _setDate ? _date : null,
        program: _setProgram ? _programCtrl.text.trim() : null,
      );
      if (edit.isEmpty) {
        _say('고칠 항목을 하나 이상 체크해 주세요');
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final r = await compute(_work, _Job(bytes, edit));
      final tmp = await getTemporaryDirectory();
      final dir = Directory(
          '${tmp.path}/doc_${DateTime.now().millisecondsSinceEpoch}');
      await dir.create(recursive: true);
      final outPath = '${dir.path}/${_editMode ? '수정' : '클린'}_$name';
      await File(outPath).writeAsBytes(r.bytes, flush: true);
      if (!mounted) return;
      setState(() {
        _outPath = outPath;
        _outBytes = r.bytes;
        _after = r.after;
        _notes = r.notes;
      });
    } catch (e) {
      if (mounted) _say('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAs() async {
    final path = _outPath;
    final bytes = _outBytes;
    if (path == null || bytes == null) return;
    try {
      final saved = await FilePicker.saveFile(
        fileName: path.split('/').last,
        bytes: bytes,
      );
      if (saved != null && mounted) _say('저장했어요');
    } catch (e) {
      if (mounted) _say('저장하지 못했어요: $e');
    }
  }

  Widget _metaTable(Map<String, String> meta, String emptyText) {
    if (meta.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(emptyText),
      );
    }
    return Column(
      children: [
        for (final e in meta.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(e.key,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Expanded(child: Text(e.value)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _editRow({
    required bool on,
    required ValueChanged<bool> onChanged,
    required Widget child,
  }) {
    return Row(
      children: [
        Checkbox(value: on, onChanged: (v) => onChanged(v ?? false)),
        Expanded(child: Opacity(opacity: on ? 1 : 0.5, child: child)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final picked = _bytes != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        const Text(
          '사용설명서 같은 문서에도 작성자 이름·회사·만든 날짜가 숨어 있어요. '
          'PDF, 한글(hwp·hwpx), 워드(docx·doc) 문서에서 지우거나 일부만 고친 사본을 만들어요.',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.description),
          label: const Text('문서 고르기'),
        ),
        if (_busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (picked) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_name!, style: const TextStyle(fontSize: 16)),
                  Text(_kindLabel!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary)),
                  const Divider(),
                  const Text('지금 들어 있는 정보'),
                  const SizedBox(height: 4),
                  _metaTable(_before, '숨은 정보가 없어요'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: SegmentLabel('전부 지우기')),
              ButtonSegment(value: true, label: SegmentLabel('일부만 고치기')),
            ],
            selected: {_editMode},
            onSelectionChanged: (s) => setState(() => _editMode = s.first),
          ),
          if (_editMode)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 12, bottom: 4),
                      child: Text('체크한 항목만 바뀌고, 나머지는 그대로 둬요.'),
                    ),
                    _editRow(
                      on: _setTitle,
                      onChanged: (v) => setState(() => _setTitle = v),
                      child: TextField(
                        controller: _titleCtrl,
                        enabled: _setTitle,
                        decoration: const InputDecoration(
                          labelText: '제목',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _editRow(
                      on: _setAuthor,
                      onChanged: (v) => setState(() => _setAuthor = v),
                      child: TextField(
                        controller: _authorCtrl,
                        enabled: _setAuthor,
                        decoration: const InputDecoration(
                          labelText: '작성자 (마지막 저장한 사람도 함께 바뀜)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _editRow(
                      on: _setProgram,
                      onChanged: (v) => setState(() => _setProgram = v),
                      child: TextField(
                        controller: _programCtrl,
                        enabled: _setProgram,
                        decoration: const InputDecoration(
                          labelText: '만든 프로그램·기기 (어디서 작성했는지)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _editRow(
                      on: _setDate,
                      onChanged: (v) => setState(() => _setDate = v),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '날짜: ${DateFormat('yyyy년 M월 d일 HH:mm').format(_date)}'),
                        subtitle: const Text('만든 날짜·수정한 날짜에 함께 적용'),
                        trailing: const Icon(Icons.calendar_month),
                        onTap: _setDate ? _pickDateTime : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: const Icon(Icons.cleaning_services),
            label: Text(_editMode ? '고친 사본 만들기' : '깨끗한 사본 만들기'),
          ),
        ],
        if (_outPath != null) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('완료: ${_outPath!.split('/').last}',
                      style: const TextStyle(fontSize: 16)),
                  const Divider(),
                  const Text('사본에 남아 있는 정보'),
                  const SizedBox(height: 4),
                  _metaTable(_after, '없음 (모두 지워졌어요)'),
                  for (final n in _notes)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('ℹ️ $n'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => SharePlus.instance
                .share(ShareParams(files: [XFile(_outPath!)])),
            icon: const Icon(Icons.send),
            label: const Text('카톡·문자·메일로 보내기'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _saveAs,
            icon: const Icon(Icons.save_alt),
            label: const Text('내 폰에 저장'),
          ),
        ],
      ],
    );
  }
}
