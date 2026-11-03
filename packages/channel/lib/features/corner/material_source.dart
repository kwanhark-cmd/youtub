import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 소재 한 개 (영상·음성·사진·글).
class MaterialItem {
  MaterialItem({
    required this.path,
    required this.kind,
    this.title = '',
    this.note = '',
    this.copyright = 'unknown',
    this.sourceApp = '',
  });

  final String path;

  /// 'video' | 'audio' | 'image' | 'text'
  final String kind;
  final String title;
  final String note;

  /// 'own'(직접 찍음) | 'licensed'(사용 허락 받음) | 'unknown'(확인 필요)
  final String copyright;
  final String sourceApp;

  bool get needsCopyrightCheck => copyright != 'own' && copyright != 'licensed';
}

/// "폴더에서 소재 가져오기" 공통 틀.
/// 3번 앱(하드 자료 검색), 4번 앱(집안 비우기)도 폴더에 파일과 manifest.json 을 넣어 주기만 하면 연동된다.
///
/// manifest.json 형식 (없어도 됨):
/// ```json
/// {"source": "하드 자료 검색", "items": [
///   {"file": "여행.mp4", "title": "제주 여행", "note": "2019년 여름", "copyright": "own"}
/// ]}
/// ```
abstract class MaterialSource {
  String get name;
  Future<List<MaterialItem>> list();
}

const _videoExt = {'.mp4', '.mov', '.m4v', '.avi', '.mkv', '.webm'};
const _audioExt = {'.m4a', '.mp3', '.wav', '.aac', '.ogg'};
const _imageExt = {'.jpg', '.jpeg', '.png', '.heic', '.webp', '.gif'};
const _textExt = {'.txt', '.md'};

String? kindOf(String path) {
  final e = p.extension(path).toLowerCase();
  if (_videoExt.contains(e)) return 'video';
  if (_audioExt.contains(e)) return 'audio';
  if (_imageExt.contains(e)) return 'image';
  if (_textExt.contains(e)) return 'text';
  return null;
}

/// 파일 이름만 보고 저작권이 있을 수 있는 소재인지 짐작 (방송·영화·음원·내려받은 영상 등).
bool looksCopyrighted(String path) {
  final n = p.basename(path).toLowerCase();
  const hints = [
    'mv',
    '뮤직비디오',
    'music video',
    'official',
    '방송',
    '드라마',
    'drama',
    '영화',
    'movie',
    'trailer',
    '예고편',
    '다운로드',
    'download',
    'ytdl',
    'youtube',
    '유튜브',
    '캡처',
    'capture',
    'netflix',
    '넷플릭스',
    '음원',
    'kbs',
    'mbc',
    'sbs',
    'jtbc',
    'tvn',
  ];
  return hints.any(
    (h) => RegExp('(^|[^a-z가-힣])${RegExp.escape(h)}([^a-z가-힣]|\$)').hasMatch(n) || (h.length > 2 && n.contains(h)),
  );
}

class FolderMaterialSource implements MaterialSource {
  FolderMaterialSource(this.dir);
  final String dir;

  @override
  String get name => p.basename(dir);

  @override
  Future<List<MaterialItem>> list() async {
    final d = Directory(dir);
    if (!d.existsSync()) return [];
    final manifest = <String, Map<String, dynamic>>{};
    var sourceApp = '';
    final mf = File(p.join(dir, 'manifest.json'));
    if (mf.existsSync()) {
      try {
        final j = jsonDecode(await mf.readAsString()) as Map<String, dynamic>;
        sourceApp = '${j['source'] ?? ''}';
        for (final it in (j['items'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>()) {
          manifest['${it['file']}'] = it;
        }
      } catch (_) {
        // 설명 파일이 잘못돼도 파일 목록은 가져온다.
      }
    }
    final out = <MaterialItem>[];
    final files = d.listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final kind = kindOf(f.path);
      if (kind == null) continue;
      final m = manifest[p.basename(f.path)];
      var copyright = '${m?['copyright'] ?? 'unknown'}';
      // 설명에 "직접 찍음" 이라고 해도 이름이 의심스러우면 확인을 받는다.
      if (looksCopyrighted(f.path)) copyright = 'unknown';
      String note = '${m?['note'] ?? ''}';
      if (kind == 'text' && note.isEmpty) {
        try {
          note = await f.readAsString();
        } catch (_) {}
      }
      out.add(
        MaterialItem(
          path: f.path,
          kind: kind,
          title: '${m?['title'] ?? p.basenameWithoutExtension(f.path)}',
          note: note,
          copyright: copyright,
          sourceApp: sourceApp,
        ),
      );
    }
    return out;
  }
}
