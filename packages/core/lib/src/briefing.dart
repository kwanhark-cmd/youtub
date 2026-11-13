import 'module_api.dart';
import 'redact.dart';

/// 아침 브리핑: 모든 모듈의 오늘 할 일을 한 번에 읽을 말로.
class Briefing {
  static const order = [ModuleId.channel, ModuleId.vault, ModuleId.harddisk, ModuleId.declutter, ModuleId.chats, ModuleId.metaclean];

  static String compose(Map<ModuleId, List<TodayItem>> items, {String userName = '', DateTime? now}) {
    final t = now ?? DateTime.now();
    final hello = t.hour < 12 ? '좋은 아침이에요' : (t.hour < 18 ? '안녕하세요' : '좋은 저녁이에요');
    final b = StringBuffer('$hello${userName.isEmpty ? '' : ', $userName님'}. ');
    var any = false;
    for (final m in order) {
      final list = [...?items[m]]..sort((a, b) => b.urgency.compareTo(a.urgency));
      if (list.isEmpty) continue;
      any = true;
      b.write('${m.title}: ');
      b.write(list.take(3).map((e) => e.text).join(', '));
      b.write('. ');
    }
    if (!any) b.write('오늘은 급한 일이 없어요. 편안한 하루 보내세요.');
    return Redact.text(b.toString().trim());
  }

  /// 가장 급한 것 하나 + 나머지
  static (TodayItem?, List<TodayItem>) pickTop(Iterable<TodayItem> all) {
    final list = all.toList()..sort((a, b) => b.urgency.compareTo(a.urgency));
    if (list.isEmpty) return (null, const []);
    return (list.first, list.sublist(1));
  }
}
