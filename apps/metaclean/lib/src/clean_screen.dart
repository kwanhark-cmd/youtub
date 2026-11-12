import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'out_name.dart';
import 'strip.dart';

/// 판매용: 사진의 메타데이터를 지워 깨끗한 사본을 만들고 공유한다.
class CleanScreen extends StatefulWidget {
  const CleanScreen({super.key});

  @override
  State<CleanScreen> createState() => _CleanScreenState();
}

class _Item {
  _Item(this.name);
  final String name;
  int beforeCount = 0;
  bool hadGps = false;
  String? takenAt;
  String? cleanedPath;
  int afterCount = 0;
  bool hiddenDataRemoved = false;
  bool reEncoded = false;
  String? error;
}

class _CleanScreenState extends State<CleanScreen> {
  final _picker = ImagePicker();
  final List<_Item> _items = [];
  bool _busy = false;

  Future<void> _pickAndClean() async {
    final files = await _picker.pickMultiImage();
    if (files.isEmpty) return;
    setState(() {
      _busy = true;
      _items.clear();
    });
    final runDir = await freshRunDir(await getTemporaryDirectory(), 'clean_');
    for (final f in files) {
      final item = _Item(f.name);
      _items.add(item);
      try {
        final src = await f.readAsBytes();

        // 1) 원본의 메타데이터 확인
        try {
          final tags = await readExifFromBytes(src);
          item.beforeCount = tags.length;
          item.hadGps = tags.keys.any((k) => k.contains('GPS'));
          item.takenAt = tags['EXIF DateTimeOriginal']?.printable ??
              tags['Image DateTime']?.printable;
        } catch (_) {
          // 읽기 실패해도 지우기는 계속한다.
        }

        // 2) 무손실 제거 (JPEG/PNG). 다른 형식은 JPEG로 다시 저장.
        Uint8List cleaned;
        String ext;
        final r = stripMetadata(src);
        if (r != null) {
          cleaned = r.bytes;
          ext = r.format == 'png' ? 'png' : 'jpg';
          item.hiddenDataRemoved = r.trailingDataRemoved;
        } else {
          final decoded = img.decodeImage(src);
          if (decoded == null) {
            item.error = '지원하지 않는 사진 형식';
            continue;
          }
          decoded.exif = img.ExifData();
          cleaned = Uint8List.fromList(img.encodeJpg(decoded, quality: 95));
          ext = 'jpg';
          item.reEncoded = true;
        }
        // 원본 이름에는 촬영 날짜(예: 20261112_143000)나 기기 표시가 들어 있어
        // 이름도 새로 짓는다.
        final outPath = uniquePathIn(runDir, cleanStem(cleaned), ext);
        await File(outPath).writeAsBytes(cleaned, flush: true);
        item.cleanedPath = outPath;

        // 3) 결과 검증: 남은 메타데이터 수
        try {
          final tags2 = await readExifFromBytes(cleaned);
          item.afterCount = tags2.length;
        } catch (_) {
          item.afterCount = 0;
        }
      } catch (e) {
        item.error = '처리 실패: $e';
      }
      if (mounted) setState(() {});
    }
    if (mounted) setState(() => _busy = false);
  }

  List<XFile> get _cleanedFiles => [
        for (final it in _items)
          if (it.cleanedPath != null) XFile(it.cleanedPath!),
      ];

  Future<void> _share() async {
    final files = _cleanedFiles;
    if (files.isEmpty) return;
    await Share.shareXFiles(files);
  }

  Future<void> _saveAll() async {
    try {
      await Gal.requestAccess();
    } catch (_) {}
    var ok = 0;
    for (final f in _cleanedFiles) {
      try {
        await Gal.putImage(f.path, album: '메타지우개');
        ok++;
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('깨끗한 사본 $ok장을 갤러리(메타지우개 앨범)에 저장했어요')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _cleanedFiles.isNotEmpty && !_busy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '중고 물건 사진을 고르면, 위치·날짜·기기 정보 등 모든 메타데이터를 지운 '
            '깨끗한 사본을 만들어요. 원본은 그대로 남습니다.',
            style: TextStyle(fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _pickAndClean,
            icon: const Icon(Icons.photo_library),
            label: const Text('사진 고르기 (여러 장 가능)', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text('아직 고른 사진이 없어요'))
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final it = _items[i];
                      final sub = StringBuffer();
                      if (it.error != null) {
                        sub.write('⚠️ ${it.error}');
                      } else if (it.cleanedPath == null) {
                        sub.write('처리 중…');
                      } else {
                        sub.write('메타데이터 ${it.beforeCount}개 → ${it.afterCount}개');
                        if (it.takenAt != null) {
                          sub.write(' · 원본 촬영일 ${it.takenAt}');
                        }
                        if (it.hadGps) sub.write(' · 위치정보(GPS) 제거됨');
                        if (it.hiddenDataRemoved) sub.write(' · 숨은 데이터(모션포토) 제거됨');
                        if (it.reEncoded) sub.write(' · JPEG로 변환됨');
                      }
                      return ListTile(
                        dense: true,
                        leading: it.cleanedPath != null
                            ? Image.file(File(it.cleanedPath!),
                                width: 48, height: 48, fit: BoxFit.cover)
                            : const Icon(Icons.image),
                        title: Text(it.name, overflow: TextOverflow.ellipsis),
                        subtitle: Text(sub.toString()),
                      );
                    },
                  ),
          ),
          if (done) ...[
            FilledButton.icon(
              onPressed: _share,
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
      ),
    );
  }
}
