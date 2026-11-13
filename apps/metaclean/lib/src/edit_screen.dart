import 'dart:io';

import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'device_info.dart';
import 'out_name.dart';
import 'photo_edit.dart';
import 'plus_code.dart';

/// 사진의 날짜·위치만 골라서 고친다. 나머지 정보는 그대로 둔다.
class EditScreen extends StatefulWidget {
  const EditScreen({super.key, this.deviceLookup = currentDeviceName});

  /// 지금 쓰는 폰의 제조사·기종을 알아내는 방법 (테스트에서 바꿔 끼움).
  final DeviceLookup deviceLookup;

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
  final _locCtrl = TextEditingController();
  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();

  DeviceAction _device = DeviceAction.keep;
  DateAction _dateAction = DateAction.keep;
  DateTime _date = DateTime.now();
  GpsAction _gps = GpsAction.keep;
  bool _busy = false;
  final List<_Done> _items = [];

  @override
  void dispose() {
    _locCtrl.dispose();
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      // 옛 인화 사진(1980년대 이전)의 날짜도 고를 수 있어야 한다.
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      // 옛 날짜를 고르기 쉽게 연도 목록부터 보여 준다.
      initialDatePickerMode: DatePickerMode.year,
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

  /// 제조사·기종 칸을 지금 이 폰의 정보로 채운다.
  /// [asked]는 사용자가 버튼을 직접 눌렀을 때 참이고, 그때만 실패를 알린다.
  Future<void> _fillThisPhone({required bool asked}) async {
    final d = await widget.deviceLookup();
    if (!mounted) return;
    if (d == null) {
      if (asked) _say('이 폰의 기종을 읽지 못했어요. 직접 적어 주세요.');
      return;
    }
    setState(() {
      _makeCtrl.text = d.make;
      _modelCtrl.text = d.model;
    });
  }

  void _onDeviceAction(DeviceAction a) {
    setState(() => _device = a);
    // 바꾸기를 처음 골랐고 칸이 비어 있으면, 이 폰 정보를 미리 넣어 준다.
    if (a == DeviceAction.change &&
        _makeCtrl.text.trim().isEmpty &&
        _modelCtrl.text.trim().isEmpty) {
      _fillThisPhone(asked: false);
    }
  }

  List<String> get _tags => _tagCtrl.text
      .split(RegExp(r'[,\n]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  bool get _hasDesc =>
      _titleCtrl.text.trim().isNotEmpty ||
      _descCtrl.text.trim().isNotEmpty ||
      _tags.isNotEmpty;

  Future<void> _run() async {
    double? lat;
    double? lng;
    if (_dateAction == DateAction.keep &&
        _gps == GpsAction.keep &&
        _device == DeviceAction.keep &&
        !_hasDesc) {
      _say('바꿀 항목을 하나 이상 골라 주세요 (날짜·위치·기기·설명)');
      return;
    }
    if (_device == DeviceAction.change &&
        _makeCtrl.text.trim().isEmpty &&
        _modelCtrl.text.trim().isEmpty) {
      _say('바꿀 기기의 제조사나 기종을 적어 주세요');
      return;
    }
    if (_gps == GpsAction.change) {
      final parsed = parseLocation(_locCtrl.text);
      if (!parsed.ok) {
        _say(parsed.error!);
        return;
      }
      lat = parsed.lat;
      lng = parsed.lng;
    }
    final files = await _picker.pickMultiImage();
    if (files.isEmpty) return;
    setState(() {
      _busy = true;
      _items.clear();
    });
    final runDir = await freshRunDir(await getTemporaryDirectory(), 'edit_');
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
          title: _titleCtrl.text,
          description: _descCtrl.text,
          keywords: _tags,
        );
        if (r == null) {
          item.error = '지원하지 않는 사진 형식';
          continue;
        }
        // 파일 이름도 사진 속 날짜와 맞춘다 (바꿨으면 바꾼 날짜로, 지웠으면 날짜 없이).
        final stem = editStem(
          dateAction: _dateAction,
          date: _date,
          originalName: f.name,
          out: r.bytes,
        );
        final out = uniquePathIn(runDir, stem, 'jpg');
        await File(out).writeAsBytes(r.bytes, flush: true);
        item.path = out;

        // 결과 확인: 실제로 들어간 값을 다시 읽어 보여 준다.
        final tags = await readExifFromBytes(r.bytes);
        final deviceName = [
          tags['Image Make']?.printable,
          tags['Image Model']?.printable,
        ].whereType<String>().join(' ').trim();
        // "그대로"를 골랐는데 결과에 없으면, 원본에 처음부터 없던 것이다
        // (이미 전부 지운 사진 등). 헷갈리지 않게 그렇게 적어 준다.
        String missing(bool kept) => kept ? '없음(원본에도 없음)' : '없음';
        final takenAt = tags['EXIF DateTimeOriginal']?.printable;
        final hasGps = tags.keys.any((k) => k.startsWith('GPS GPSLatitude'));
        final parts = <String>[
          '촬영일 ${takenAt ?? missing(_dateAction == DateAction.keep)}',
          '위치 ${hasGps ? '있음' : missing(_gps == GpsAction.keep)}',
          '기기 ${deviceName.isEmpty ? missing(_device == DeviceAction.keep) : deviceName}',
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
                if (_dateAction == DateAction.change) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_month),
                    title: Text(DateFormat('yyyy년 M월 d일 HH:mm').format(_date)),
                    subtitle: const Text('눌러서 날짜와 시각 고르기'),
                    onTap: _pickDateTime,
                  ),
                  const Text(
                    '인화·현상된 옛 사진을 찍었다면, 그 사진의 실제 날짜로 지정해 두면 '
                    '갤러리에서 제 날짜에 정리돼요. (오늘 찍은 날짜 대신 원하는 날짜가 들어갑니다.)',
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
                  TextField(
                    controller: _locCtrl,
                    decoration: const InputDecoration(
                      labelText: '좌표 또는 플러스코드',
                      hintText: '37.2954, 127.1518  또는  75W2+4PV 용인',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '구글 지도에서 원하는 곳을 길게 누른 뒤, 아래에 뜨는 좌표나 '
                    '플러스코드(예: 75W2+4PV 용인)를 그대로 복사해 붙여넣으세요. '
                    '짧은 플러스코드는 뒤에 도시 이름이 있어야 풀 수 있어요.',
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
                  onSelectionChanged: (s) => _onDeviceAction(s.first),
                ),
                if (_device == DeviceAction.change) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _makeCtrl,
                          decoration: const InputDecoration(
                            labelText: '제조사',
                            hintText: '예: Canon',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _modelCtrl,
                          decoration: const InputDecoration(
                            labelText: '기종',
                            hintText: '예: AE-1',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _fillThisPhone(asked: true),
                      icon: const Icon(Icons.smartphone),
                      label: const Text('이 폰 정보로 채우기'),
                    ),
                  ),
                  const Text(
                    '지금 쓰는 폰의 제조사·기종이 자동으로 들어가요. 다른 기기로 적고 싶으면 '
                    '고쳐 쓰면 됩니다. (필름 카메라로 찍어 스캔한 사진이면 예: Canon AE-1)',
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
                const Text('설명 (정리·검색용, 선택)',
                    style: TextStyle(fontSize: 16)),
                const SizedBox(height: 4),
                const Text(
                  '나중에 사진을 찾기 쉽도록 제목·설명·태그를 적어 둘 수 있어요. '
                  '한글도 안전하게 저장되고, 갤러리·사진 앱에서 검색에 쓰입니다.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: '제목',
                    hintText: '예: 할머니 칠순 기념사진',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '설명',
                    hintText: '예: 1980년 부산에서 인화한 가족사진을 스캔',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tagCtrl,
                  decoration: const InputDecoration(
                    labelText: '태그 (쉼표로 구분)',
                    hintText: '예: 가족, 1980, 부산, 필름사진',
                    border: OutlineInputBorder(),
                  ),
                ),
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
            onPressed: () =>
                SharePlus.instance.share(ShareParams(files: _outFiles)),
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
