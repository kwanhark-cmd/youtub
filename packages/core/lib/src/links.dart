import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'log.dart';
import 'module_api.dart';
import 'redact.dart';

/// 모듈 사이 연결 종류. 설정에서 하나씩 켜고 끌 수 있다.
enum LinkKind {
  declutterToChannel('비우기 → 채널', '물건 사진·사연·타임랩스를 채널 "내 코너" 소재로 제안'),
  hardToChannel('하드 → 채널', '찾은 장면·예전 사진·N년 전 오늘을 채널 소재로 제안'),
  declutterToHard('비우기 → 하드', '"디지털로 남기고 버리기" 기록을 하드 개인 기록 타임라인에 제안'),
  vaultToChannel('금고 → 채널', '채널 도구에 필요한 비밀번호를 승인 후 불러오기'),
  chatsToAll('대화 → 모든 모듈', 'AI 대화에서 찾은 결정 사항을 해당 모듈 메모로 제안'),
  hardToVault('하드 → 금고', '하드에서 찾은 영수증·계약서를 구독 근거 문서로 제안');

  const LinkKind(this.title, this.detail);
  final String title;
  final String detail;
}

/// 다른 모듈로 보내는 "제안" 하나. 자동으로 올리거나 지우지 않고, 사용자가 확정해야 들어간다.
class Suggestion {
  Suggestion({
    required this.id,
    required this.kind,
    required this.from,
    required this.to,
    required this.title,
    this.detail = '',
    this.files = const [],
    this.status = 'pending',
    DateTime? created,
  }) : created = created ?? DateTime.now();

  final String id;
  final LinkKind kind;
  final ModuleId from;
  final ModuleId to;
  final String title;
  final String detail;
  final List<String> files;

  /// pending / accepted / dismissed
  String status;
  final DateTime created;

  Map<String, Object?> toJson() => {
        'id': id, 'kind': kind.name, 'from': from.name, 'to': to.name, 'title': title, 'detail': detail,
        'files': files, 'status': status, 'created': created.toIso8601String(),
      };

  static Suggestion fromJson(Map m) => Suggestion(
        id: m['id'] as String,
        kind: LinkKind.values.byName(m['kind'] as String),
        from: ModuleId.values.byName(m['from'] as String),
        to: ModuleId.values.byName(m['to'] as String),
        title: m['title'] as String,
        detail: (m['detail'] as String?) ?? '',
        files: ((m['files'] as List?) ?? const []).cast<String>(),
        status: (m['status'] as String?) ?? 'pending',
        created: DateTime.tryParse('${m['created']}'),
      );
}

/// 제안함. 파일(links.json)에 남겨 앱을 껐다 켜도 유지된다.
class LinkHub extends ChangeNotifier {
  LinkHub({this.file, bool Function(LinkKind)? enabled}) : _enabled = enabled ?? ((_) => true) {
    _load();
  }
  final File? file;
  final bool Function(LinkKind) _enabled;
  final List<Suggestion> _items = [];

  List<Suggestion> get all => List.unmodifiable(_items);
  List<Suggestion> pendingFor(ModuleId to) => _items.where((s) => s.to == to && s.status == 'pending').toList();
  List<Suggestion> get pending => _items.where((s) => s.status == 'pending').toList();

  void _load() {
    final f = file;
    if (f == null || !f.existsSync()) return;
    try {
      for (final m in (jsonDecode(f.readAsStringSync()) as List).cast<Map>()) {
        _items.add(Suggestion.fromJson(m));
      }
    } catch (e) {
      CoreLog.error('제안함을 읽지 못함', e);
    }
  }

  void _save() {
    final f = file;
    if (f != null) {
      try {
        f.parent.createSync(recursive: true);
        f.writeAsStringSync(jsonEncode(_items.map((e) => e.toJson()).toList()), flush: true);
      } catch (e) {
        CoreLog.error('제안함 저장 실패', e);
      }
    }
    notifyListeners();
  }

  /// 제안 넣기. 연결이 꺼져 있으면 넣지 않는다. 비밀 값은 가린다. 같은 id면 다시 넣지 않는다.
  bool propose(Suggestion s) {
    if (!_enabled(s.kind)) return false;
    if (_items.any((e) => e.id == s.id)) return false;
    _items.add(Suggestion(
      id: s.id, kind: s.kind, from: s.from, to: s.to, title: Redact.text(s.title), detail: Redact.text(s.detail),
      files: s.files, created: s.created,
    ));
    _save();
    return true;
  }

  void accept(String id) => _mark(id, 'accepted');
  void dismiss(String id) => _mark(id, 'dismissed');

  void _mark(String id, String status) {
    for (final s in _items) {
      if (s.id == id) s.status = status;
    }
    _save();
  }
}
