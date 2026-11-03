import 'dart:async';

import 'log.dart';
import 'module_api.dart';
import 'redact.dart';

/// 홈 검색창 하나로 다섯 모듈을 한 번에 찾는다. 비밀번호·열쇠처럼 보이는 결과는 버린다.
class UnifiedSearch {
  UnifiedSearch(this.modules, {this.timeout = const Duration(seconds: 6)});
  final List<AssistantModule> modules;
  final Duration timeout;

  Future<Map<ModuleId, List<SearchHit>>> run(String query) async {
    final q = query.trim();
    if (q.isEmpty) return {};
    final out = <ModuleId, List<SearchHit>>{};
    await Future.wait(modules.map((m) async {
      try {
        final hits = await m.search(q).timeout(timeout);
        final safe = hits.where(isSafe).toList();
        if (safe.isNotEmpty) out[m.id] = safe;
      } catch (e) {
        CoreLog.warn('${m.id.title} 검색 실패: $e');
      }
    }));
    return out;
  }

  static bool isSafe(SearchHit h) {
    if (h.kind == 'password' || h.kind == 'secret') return false;
    return !Redact.looksSecret(h.title) && !Redact.looksSecret(h.subtitle ?? '');
  }
}
