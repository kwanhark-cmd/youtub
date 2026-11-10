import 'dart:io';

import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'photo_edit.dart';

/// 사진의 날짜·위치만 골라서 고친다. 나머지 정보는 그대로 둔다.
class EditScreen extends StatefulWidget {
  const EditScreen({super.key});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _Done {
  _Done(this.name);
  final String name;
  String? path;
  String? summary;
  String? error;
}

class _EditScreenState extends State<EditScreen> {
  final _picker = ImagePicker();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();

  DeviceAction _device = DeviceAction.keep;
  DateAction _dateAction = DateAction.keep;
  DateTime _date = DateTime.now();
  GpsAction _gps = GpsAction.keep;
  bool _busy = false;
  final List<_Done> _items = [];

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1990),
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

  void _say(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _run() async {
    double? lat;
    double? lng;
    if (_dateAction == DateAction.keep &&
        _gps == GpsAction.keep &&
        _device == DeviceAction.keep) {
      _say('바꿀 항목을 하나 이상 골라 주세요 (날짜·위치·촬영 기기)');
      return;
    }
    if (_device == DeviceAction.change &&
        _makeCtrl.text.trim().isEmpty &&
        _modelCtrl.text.trim().isEmpty) {
      _say('바꿀 기기의 제조사나 기종을 적어 주세요');
      return;
    }
    if (_gps == GpsAction.change) {
      lat = double.tryParse(_latCtrl.text.trim());
      lng = double.tryParse(_lngCtrl.text.trim());
      if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
        _say('위도(-90~90)와 경도(-180~180)를 숫자로 적어 주세요');
        return;
      }
    }
    final files = await _picker.pickMultiImage();
    if (files.isEmpty) return;
    setState(() {
      _busy = true;
      _items.clear();
    });
    final tmp = await getTemporaryDirectory();
    for (final f in files) {
      final item = _Done(f.name);
      _items.add(item);
      try {
        final src = await f.readAsBytes();
        final r = editPhotoMeta(
          src,
          dateAction: _dateAction,
          date: _date,
          gps: _gps,
          lat: lat,
          lng: lng,
          device: _device,
          make: _makeCtrl.text,
          model: _modelCtrl.text,
        );
        if (r == null) {
          item.error = '지원하지 않는 사진 형식';
          continue;
        }
        final base = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
        final out =
            '${tmp.path}/수정_${base}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(out).writeAsBytes(r.bytes, flush: true);
        item.path = out;

        // 결과 확인: 실제로 들어간 값을 다시 읽어 보여 준다.
        final tags = await readExifFromBytes(r.bytes);
        final deviceName = [
          tags['Image Make']?.printable,
          tags['Image Model']?.printable,
        ].whereType<String>().join(' ').trim();
        final parts = <String>[
          '촬영일 ${tags['EXIF DateTimeOriginal']?.printable ?? '없음'}',
          tags.keys.any((k) => k.startsWith('GPS GPSLatitude'))
              ? '위치 있음'
              : '위치 없음',
          '기기 ${deviceName.isEmpty ? '정보 없음' : deviceName}',
          if (r.reEncoded) 'JPEG로 변환됨',
        ];
        item.summary = parts.join(' · ');
      } catch (e) {
        item.error = '처리 실패: $e';
      }
      if (mounted) setState(() {});
    }
    if (mounted) setState(() => _busy = false);
  }

  List<XFile> get _outFiles => [
        for (final it in _items)
          if (it.path != null) XFile(it.path!),
      ];

  Future<void> _saveAll() async {
    try {
      await Gal.requestAccess();
    } catch (_) {}
    var ok = 0;
    for (final f in _outFiles) {
      try {
        await Gal.putImage(f.path, album: '메타지우개');
        ok++;
      } catch (_) {}
    }
    if (mounted) _say('수정한 사본 $ok장을 갤러리(메타지우개 앨범)에 저장했어요');
  }

  @override
  Widget build(BuildContext context) {
    final done = _outFiles.isNotEmpty && !_busy;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        const Text(
          '사진 정보를 전부 지우지 않고 날짜·위치·촬영 기기 중 고른 것만 바꿔요. '
          '나머지 정보와 화질은 그대로 두고, 사본을 새로 만듭니다.',
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('촬영 날짜', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                SegmentedButton<DateAction>(
                  segments: const [
                    ButtonSegment(value: DateAction.keep, label: Text('그대로')),
                    ButtonSegment(value: DateAction.remove, label: Text('지우기')),
                    ButtonSegment(value: DateAction.change, label: Text('바꾸기')),
                  ],
                  selected: {_dateAction},
                  onSelectionChanged: (s) => setState(() => _dateAction = s.first),
                ),
                if (_dateAction == DateAction.change)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_month),
                    title: Text(DateFormat('yyyy년 M월 d일 HH:mm').format(_date)),
                    subtitle: const Text('눌러서 날짜와 시각 고르기'),
                    onTap: _pickDateTime,
                  ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('촬영 위치', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                SegmentedButton<GpsAction>(
                  segments: const [
                    ButtonSegment(value: GpsAction.keep, label: Text('그대로')),
                    ButtonSegment(value: GpsAction.remove, label: Text('지우기')),
                    ButtonSegment(value: GpsAction.change, label: Text('바꾸기')),
                  ],
                  selected: {_gps},
                  onSelectionChanged: (s) => setState(() => _gps = s.first),
                ),
                if (_gps == GpsAction.change) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _latCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration: const InputDecoration(
                            labelText: '위도 (예: 37.5665)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _lngCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration: const InputDecoration(
                            labelText: '경도 (예: 126.9780)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '지도 앱에서 원하는 곳을 길게 누르면 위도·경도 숫자가 나와요.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('촬영 기기 (스마트폰 제조사·기종)',
                    style: TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                SegmentedButton<DeviceAction>(
                  segments: const [
                    ButtonSegment(
                        value: DeviceAction.keep, label: Text('그대로')),
                    ButtonSegment(
                        value: DeviceAction.remove, label: Text('지우기')),
                    ButtonSegment(
                        value: DeviceAction.change, label: Text('바꾸기')),
                  ],
                  selected: {_device},
                  onSelectionChanged: (s) => setState(() => _device = s.first),
                ),
                if (_device == DeviceAction.change) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _makeCtrl,
                          decoration: const InputDecoration(
                            labelText: '제조사 (예: samsung)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _modelCtrl,
                          decoration: const InputDecoration(
                            labelText: '기종 (예: SM-S921N)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _run,
          icon: const Icon(Icons.photo_library),
          label: const Text('사진 고르고 수정하기 (여러 장 가능)',
              style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 8),
        for (final it in _items)
          ListTile(
            dense: true,
            leading: it.path != null
                ? Image.file(File(it.path!),
                    width: 48, height: 48, fit: BoxFit.cover)
                : const Icon(Icons.image),
            title: Text(it.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(it.error != null
                ? '⚠️ ${it.error}'
                : it.summary ?? '처리 중…'),
          ),
        if (done) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => Share.shareXFiles(_outFiles),
            icon: const Icon(Icons.send),
            label: const Text('카톡·문자로 보내기', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _saveAll,
            icon: const Icon(Icons.save_alt),
            label: const Text('갤러리에 저장'),
          ),
        ],
      ],
    );
  }
}
