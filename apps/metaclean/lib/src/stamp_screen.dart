import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'exif_utils.dart';
import 'out_name.dart';
import 'photo_gps.dart';
import 'photo_library.dart';
import 'photo_pick.dart';

/// 구매용: 받은 사진에 날짜·물건·메모·위치 메타데이터를 기록해 보관한다.
class StampScreen extends StatefulWidget {
  const StampScreen({
    super.key,
    this.pickPhotos = pickOriginalPhotos,
    this.library = const PhotoLibrary(),
  });

  /// 사진을 고르는 방법·사진 보관함 (테스트에서 바꿔 끼움).
  final PickPhotos pickPhotos;
  final PhotoLibrary library;

  @override
  State<StampScreen> createState() => _StampScreenState();
}

class _StampScreenState extends State<StampScreen> {
  final _formKey = GlobalKey<FormState>();
  final _itemCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  final _placeCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

  Uint8List? _picked;
  GpsState _gps = GpsState.none;
  ({double lat, double lng})? _latLng;
  int _existingCount = 0;
  String? _existingDate;
  DateTime _date = DateTime.now();
  bool _busy = false;
  String? _savedPath;

  @override
  void dispose() {
    _itemCtrl.dispose();
    _memoCtrl.dispose();
    _placeCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked =
        await widget.pickPhotos(context, widget.library, multiple: false);
    if (picked.isEmpty || !mounted) return;
    final Uint8List bytes;
    try {
      bytes = await picked.first.read();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('사진을 읽지 못했어요: $e')));
      }
      return;
    }
    var count = 0;
    String? dateStr;
    try {
      final tags = await readExifFromBytes(bytes);
      count = tags.length;
      dateStr = tags['EXIF DateTimeOriginal']?.printable ??
          tags['Image DateTime']?.printable;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _picked = bytes;
      _gps = gpsStateOfBytes(bytes);
      _latLng = gpsLatLngOfBytes(bytes);
      _existingCount = count;
      _existingDate = dateStr;
      _savedPath = null;
      _date = DateTime.now();
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute);
      });
    }
  }

  Future<void> _save() async {
    final picked = _picked;
    if (picked == null || !_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final decoded = img.decodeImage(picked);
      if (decoded == null) {
        throw '지원하지 않는 사진 형식이에요';
      }
      final lat = double.tryParse(_latCtrl.text.trim());
      final lng = double.tryParse(_lngCtrl.text.trim());
      applyStamp(
        decoded,
        date: _date,
        itemName: _itemCtrl.text,
        memo: _memoCtrl.text,
        place: _placeCtrl.text,
        lat: lat,
        lng: lng,
      );
      final out = Uint8List.fromList(img.encodeJpg(decoded, quality: 95));

      final dir = await getApplicationDocumentsDirectory();
      final name = safeFileName(_itemCtrl.text);
      // 이름도 사진에 새긴 기록 날짜와 맞춘다.
      final outPath = uniquePathIn(
          dir, '기록_${name}_${DateFormat('yyyyMMdd').format(_date)}', 'jpg');
      await File(outPath).writeAsBytes(out, flush: true);

      try {
        await Gal.requestAccess();
        await Gal.putImage(outPath, album: '중고거래 기록');
      } catch (_) {}

      setState(() => _savedPath = outPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('기록을 새겨 갤러리(중고거래 기록 앨범)에 저장했어요')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '판매자에게 받은 사진에 받은 날짜·물건 이름·메모·위치를 기록해 두면, '
              '나중에 언제 어떤 물건이었는지 찾기 쉬워요.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.image_search),
              label: const Text('받은 사진 고르기'),
            ),
            if (_picked != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_picked!, height: 180, fit: BoxFit.cover),
              ),
              const SizedBox(height: 8),
              Text(
                _existingCount == 0
                    ? '현재 메타데이터: 없음 (판매자가 지우고 보냈어요)'
                    : '현재 메타데이터: $_existingCount개'
                        '${_existingDate != null ? " · 촬영일 $_existingDate" : ""}',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              if (_latLng != null) ...[
                const SizedBox(height: 4),
                Text('사진 속 위치: ${shortLatLng(_latLng!)} (기록할 때 그대로 둬요)'),
              ],
              if (_gps == GpsState.blank) ...[
                const SizedBox(height: 8),
                GpsHiddenNotice(
                  count: 1,
                  library: widget.library,
                  kind: GpsNoticeKind.stamp,
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _itemCtrl,
                decoration: const InputDecoration(
                  labelText: '물건 이름 (필수)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '물건 이름을 적어 주세요' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _memoCtrl,
                decoration: const InputDecoration(
                  labelText: '메모 (판매자·가격 등, 선택)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(4),
                ),
                title:
                    Text('기록 날짜: ${DateFormat('yyyy년 M월 d일').format(_date)}'),
                trailing: const Icon(Icons.calendar_month),
                onTap: _pickDate,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _placeCtrl,
                decoration: const InputDecoration(
                  labelText: '거래 장소 (예: 강남역 2번 출구, 선택)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: '위도 (선택)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _lngCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: '경도 (선택)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.verified),
                label: const Text('기록 새겨서 보관하기'),
              ),
              if (_savedPath != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => SharePlus.instance
                      .share(ShareParams(files: [XFile(_savedPath!)])),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('기록된 사진 공유'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
