import 'dart:convert';

import '../../core/db.dart';

/// 채널별 설명 템플릿: 고정 문구, 링크, 해시태그 묶음. 새 영상 설명 끝에 자동으로 붙는다.
class DescTemplate {
  DescTemplate({this.fixed = '', this.links = const [], this.hashtags = const []});

  final String fixed;
  final List<String> links;
  final List<String> hashtags;

  bool get isEmpty => fixed.trim().isEmpty && links.isEmpty && hashtags.isEmpty;

  /// 해시태그는 '#' 과 띄어쓰기를 정리해 같은 것은 한 번만.
  static List<String> cleanTags(Iterable<String> raw) {
    final out = <String>[];
    for (final r in raw) {
      for (final part in r.split(RegExp(r'[\s,]+'))) {
        final t = part.replaceAll('#', '').trim();
        if (t.isNotEmpty && !out.contains(t)) out.add(t);
      }
    }
    return out;
  }

  String get block {
    final parts = <String>[
      if (fixed.trim().isNotEmpty) fixed.trim(),
      if (links.isNotEmpty) links.map((l) => l.trim()).where((l) => l.isNotEmpty).join('\n'),
      if (hashtags.isNotEmpty) hashtags.map((h) => '#$h').join(' '),
    ];
    return parts.join('\n\n');
  }

  /// 설명에 템플릿을 붙인다. 이미 붙어 있으면 그대로 (두 번 붙지 않게).
  String applyTo(String description) {
    if (isEmpty) return description;
    final b = block;
    if (description.contains(b)) return description;
    final d = description.trimRight();
    return d.isEmpty ? b : '$d\n\n$b';
  }

  Map<String, dynamic> toJson() => {'fixed': fixed, 'links': links, 'hashtags': hashtags};

  factory DescTemplate.fromJson(Map<String, dynamic> j) => DescTemplate(
    fixed: '${j['fixed'] ?? ''}',
    links: ((j['links'] as List<dynamic>?) ?? const []).map((e) => '$e').toList(),
    hashtags: ((j['hashtags'] as List<dynamic>?) ?? const []).map((e) => '$e').toList(),
  );
}

class DescTemplateStore {
  DescTemplateStore(this.db);
  final AppDatabase db;

  String _key(String channelId) => 'descTemplate:$channelId';

  DescTemplate get(String channelId) {
    final raw = db.getSetting<String>(_key(channelId));
    if (raw == null) return DescTemplate();
    try {
      return DescTemplate.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return DescTemplate();
    }
  }

  void save(String channelId, DescTemplate t) => db.setSetting(_key(channelId), jsonEncode(t.toJson()));
}
