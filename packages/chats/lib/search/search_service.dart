import '../data/conversation_store.dart';
import '../data/korean_tokenizer.dart';
import '../models/models.dart';
import 'keywords.dart';
import 'query_parser.dart';
import 'synonyms.dart';

class SearchHit {
  final ConversationSummary conversation;
  final String snippet;
  final int messageIndex;
  final List<String> highlight;

  const SearchHit({required this.conversation, required this.snippet, required this.messageIndex, required this.highlight});
}

class SearchPage {
  final List<SearchHit> hits;
  final int nextCursor;
  final bool hasMore;
  const SearchPage(this.hits, this.nextCursor, this.hasMore);
}

/// 세 AI 대화를 한꺼번에 찾는 본문 전체 검색. 인터넷 없이 동작합니다.
class SearchService {
  final ConversationStore store;
  SearchService(this.store);

  String? buildMatch(SearchQuery q) {
    final parts = <String>[];
    for (final kw in q.keywords) {
      final variants = q.similar && !q.exact ? Synonyms.expand(kw) : [kw];
      final exprs = variants.map(KoreanTokenizer.termQuery).where((e) => e.isNotEmpty).toSet().toList();
      if (exprs.isEmpty) continue;
      parts.add(exprs.length == 1 ? exprs.first : '(${exprs.join(' OR ')})');
    }
    if (parts.isEmpty) return null;
    return parts.join(' AND ');
  }

  List<String> highlightWords(SearchQuery q) {
    if (q.exact) return [q.keywords.join(' ')];
    final out = <String>{};
    for (final k in q.keywords) {
      out.addAll(q.similar ? Synonyms.expand(k) : [k]);
    }
    return out.toList();
  }

  Future<SearchPage> search(SearchQuery q, {int cursor = 0, int limit = 30}) async {
    final match = buildMatch(q);
    final where = <String>[store.sampleCond()];
    final args = <Object?>[];
    if (q.source != null) {
      where.add('c.source=?');
      args.add(q.source!.key);
    }
    if (q.from != null) {
      where.add('c.created_at>=?');
      args.add(q.from!.millisecondsSinceEpoch);
    }
    if (q.to != null) {
      where.add('c.created_at<?');
      args.add(q.to!.millisecondsSinceEpoch);
    }
    final words = highlightWords(q);
    if (match == null) {
      final w = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
      final rows = store.db.select(
        'SELECT ${ConversationStore.summaryColumns} FROM conversations c $w ORDER BY c.created_at DESC LIMIT ? OFFSET ?',
        [...args, limit + 1, cursor],
      );
      final list = rows.map(ConversationStore.rowToSummary).toList();
      final hits = <SearchHit>[];
      for (final c in list.take(limit)) {
        hits.add(SearchHit(conversation: c, snippet: c.summary ?? '', messageIndex: 0, highlight: const []));
      }
      return SearchPage(hits, cursor + hits.length, list.length > limit);
    }

    final w = where.isEmpty ? '' : 'AND ${where.join(' AND ')}';
    final sql =
        'SELECT ${ConversationStore.summaryColumns}, bm25(conv_fts, 6.0, 1.0, 0.5) AS rank '
        'FROM conv_fts JOIN conversations c ON c.id = conv_fts.rowid WHERE conv_fts MATCH ? $w '
        'ORDER BY rank, c.created_at DESC LIMIT ? OFFSET ?';
    final hits = <SearchHit>[];
    var pos = cursor;
    const chunk = 60;
    var exhausted = false;
    var leftover = false;
    while (hits.length < limit && !exhausted) {
      final rows = store.db.select(sql, [match, ...args, chunk, pos]);
      if (rows.length < chunk) exhausted = true;
      for (var ri = 0; ri < rows.length; ri++) {
        final r = rows[ri];
        pos++;
        if (hits.length >= limit) {
          pos--;
          leftover = true;
          break;
        }
        final c = ConversationStore.rowToSummary(r);
        final msgs = await store.messages(c.id);
        if (q.exact) {
          final phrase = q.keywords.join(' ').toLowerCase();
          final inTitle = c.title.toLowerCase().contains(phrase);
          final idx = msgs.indexWhere((m) => m.text.toLowerCase().contains(phrase));
          if (!inTitle && idx < 0) continue;
          hits.add(
            SearchHit(
              conversation: c,
              snippet: idx >= 0 ? makeSnippet(msgs[idx].text, [phrase]) : c.title,
              messageIndex: idx < 0 ? 0 : idx,
              highlight: [phrase],
            ),
          );
        } else {
          final (idx, snip) = _bestSnippet(msgs, words, c.title);
          hits.add(SearchHit(conversation: c, snippet: snip, messageIndex: idx, highlight: words));
        }
        if (hits.length >= limit && ri < rows.length - 1) leftover = true;
        if (hits.length >= limit) break;
      }
    }
    return SearchPage(hits, pos, !exhausted || leftover);
  }

  (int, String) _bestSnippet(List<Message> msgs, List<String> words, String title) {
    final lw = words.map((e) => e.toLowerCase()).toList();
    var bestIdx = -1;
    var bestScore = 0;
    for (var i = 0; i < msgs.length; i++) {
      final t = msgs[i].text.toLowerCase();
      var score = 0;
      for (final w in lw) {
        if (t.contains(w)) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        bestIdx = i;
      }
    }
    if (bestIdx < 0) {
      return (0, msgs.isEmpty ? title : makeSnippet(msgs.first.text, const []));
    }
    return (bestIdx, makeSnippet(msgs[bestIdx].text, lw));
  }

  /// 찾은 낱말 주변 글자만 짧게 보여줍니다.
  static String makeSnippet(String text, List<String> words, {int radius = 45}) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lower = flat.toLowerCase();
    var at = -1;
    for (final w in words) {
      if (w.isEmpty) continue;
      final i = lower.indexOf(w.toLowerCase());
      if (i >= 0 && (at < 0 || i < at)) at = i;
    }
    if (at < 0) return flat.length > radius * 2 ? '${flat.substring(0, radius * 2)}…' : flat;
    final start = (at - radius).clamp(0, flat.length);
    final end = (at + radius * 2).clamp(0, flat.length);
    return '${start > 0 ? '…' : ''}${flat.substring(start, end)}${end < flat.length ? '…' : ''}';
  }

  /// "이 주제와 관련된 지난 대화" — 같은 주제와 비슷한 낱말로 고릅니다.
  Future<List<ConversationSummary>> related(int convId, {int limit = 5, List<int> topicIds = const []}) async {
    final c = store.get(convId);
    if (c == null) return const [];
    final msgs = await store.messages(convId);
    final words = KeywordExtractor.top('${c.title} ${c.title} ${msgs.map((m) => m.text).join(' ')}', count: 6);
    final scores = <int, double>{};
    if (words.isNotEmpty) {
      final expr = words.map(KoreanTokenizer.termQuery).where((e) => e.isNotEmpty).join(' OR ');
      if (expr.isNotEmpty) {
        final rows = store.db.select(
          'SELECT rowid AS id, bm25(conv_fts, 6.0, 1.0, 0.5) AS rank FROM conv_fts WHERE conv_fts MATCH ? ORDER BY rank LIMIT 40',
          [expr],
        );
        for (final r in rows) {
          final id = r['id'] as int;
          if (id == convId) continue;
          if (store.isHiddenSample(id)) continue;
          scores[id] = (scores[id] ?? 0) + (-(r['rank'] as num).toDouble()).clamp(0, 50);
        }
      }
    }
    if (topicIds.isNotEmpty) {
      final rows = store.db.select(
        "SELECT conv_id, COUNT(*) AS n FROM conversation_topics WHERE origin!='removed' AND topic_id IN (${topicIds.map((_) => '?').join(',')}) AND conv_id!=? GROUP BY conv_id",
        [...topicIds, convId],
      );
      for (final r in rows) {
        final id = r['conv_id'] as int;
        scores[id] = (scores[id] ?? 0) + 3.0 * (r['n'] as int);
      }
    }
    final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return ranked.take(limit).map((e) => store.get(e.key)).whereType<ConversationSummary>().toList();
  }
}
