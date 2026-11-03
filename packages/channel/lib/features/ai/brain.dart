import 'dart:convert';

import '../../core/failure.dart';
import '../../core/logger.dart';
import '../youtube/models.dart';
import 'ai_service.dart';

/// 채널(또는 블로그)의 분위기·말투·스타일.
class StyleCard {
  StyleCard({
    this.mood = '',
    this.tone = '',
    this.topics = const [],
    this.titlePattern = '',
    this.audience = '',
    this.notes = '',
    this.editedByUser = false,
  });

  final String mood;
  final String tone;
  final List<String> topics;
  final String titlePattern;
  final String audience;
  final String notes;
  final bool editedByUser;

  Map<String, dynamic> toJson() => {
    'mood': mood,
    'tone': tone,
    'topics': topics,
    'titlePattern': titlePattern,
    'audience': audience,
    'notes': notes,
    'editedByUser': editedByUser,
  };

  factory StyleCard.fromJson(Map<String, dynamic> j) => StyleCard(
    mood: '${j['mood'] ?? ''}',
    tone: '${j['tone'] ?? ''}',
    topics: ((j['topics'] as List<dynamic>?) ?? const []).map((e) => '$e').toList(),
    titlePattern: '${j['titlePattern'] ?? ''}',
    audience: '${j['audience'] ?? ''}',
    notes: '${j['notes'] ?? ''}',
    editedByUser: j['editedByUser'] == true,
  );

  String encode() => jsonEncode(toJson());
  static StyleCard? decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return StyleCard.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  String describe() =>
      '분위기: $mood / 말투: $tone / 주제: ${topics.join(', ')} / 제목 스타일: $titlePattern / 시청자: $audience / 메모: $notes';
}

enum ContentFormat { shorts, long, docu, image, talk }

class ContentPlan {
  ContentPlan({
    required this.title,
    required this.description,
    required this.tags,
    required this.thumbnailText,
    required this.script,
  });
  final String title;
  final String description;
  final List<String> tags;
  final String thumbnailText;
  final String script;

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'tags': tags,
    'thumbnailText': thumbnailText,
    'script': script,
  };

  factory ContentPlan.fromJson(Map<String, dynamic> j) => ContentPlan(
    title: '${j['title'] ?? ''}',
    description: '${j['description'] ?? ''}',
    tags: ((j['tags'] as List<dynamic>?) ?? const []).map((e) => '$e').toList(),
    thumbnailText: '${j['thumbnailText'] ?? ''}',
    script: '${j['script'] ?? ''}',
  );
}

class BlogDraft {
  BlogDraft({required this.title, required this.html, required this.tags});
  final String title;
  final String html;
  final List<String> tags;
}

/// "AI 두뇌". 실제 AI 를 쓸 수 있으면 Claude 에게, 아니면(연습 모드) 기기 안 규칙으로 만든다.
/// AI 답을 읽지 못하면 규칙 결과로 대신하고 기록을 남긴다 → 흐름이 멈추지 않는다.
class Brain {
  Brain(this.ai, {this.logger});
  final AiService ai;
  final AppLogger? logger;

  static const _system =
      '당신은 한국어 유튜브·블로그 운영을 돕는 비서입니다. 과장·낚시성 표현, 허위 정보, 다른 채널 베끼기를 피하고 '
      '채널의 원래 분위기와 말투를 지킵니다. 요청한 JSON 만 출력합니다.';

  Future<T> _ask<T>(
    String task,
    String prompt,
    T Function(Map<String, dynamic>) parse,
    T Function() fallback, {
    int maxTokens = 2000,
  }) async {
    if (ai.isPracticeMode) return fallback();
    try {
      final reply = await ai.complete(AiRequest(task: task, system: _system, prompt: prompt, maxTokens: maxTokens));
      return parse(extractJson(reply.text));
    } on AppFailure catch (e) {
      if (e.kind == FailureKind.costLimit || e.kind == FailureKind.notConnected) return fallback();
      rethrow;
    } on FormatException catch (e) {
      logger?.warn('AI 답을 읽지 못해 기본 규칙 사용: $task $e');
      return fallback();
    } on TypeError catch (e) {
      logger?.warn('AI 답 형식이 달라 기본 규칙 사용: $task $e');
      return fallback();
    }
  }

  // ---------- 채널 스타일 분석 ----------
  Future<StyleCard> analyzeStyle(String channelTitle, List<YtVideo> videos) {
    final sample = videos.take(30).map((v) => '- ${v.title} | ${_cut(v.description, 80)}').join('\n');
    return _ask(
      'style',
      '채널 이름: $channelTitle\n최근 영상:\n$sample\n\n'
          '이 채널의 스타일을 분석해 JSON 으로: {"mood":"","tone":"","topics":[""],"titlePattern":"","audience":"","notes":""}',
      StyleCard.fromJson,
      () => mockStyle(channelTitle, videos.map((v) => v.title).toList()),
    );
  }

  static StyleCard mockStyle(String channelTitle, List<String> titles) {
    final topics = topWords([channelTitle, ...titles], 5);
    final avgLen = titles.isEmpty ? 0 : titles.map((t) => t.length).reduce((a, b) => a + b) ~/ titles.length;
    final hasNumbers = titles.where((t) => RegExp(r'\d').hasMatch(t)).length > titles.length / 2;
    return StyleCard(
      mood: '따뜻하고 차분함',
      tone: '친근한 존댓말',
      topics: topics,
      titlePattern: '평균 $avgLen자${hasNumbers ? ', 숫자(편수) 자주 사용' : ''}',
      audience: '${topics.isNotEmpty ? topics.first : '이 주제'}에 관심 있는 일반 시청자',
      notes: '연습 모드에서 제목만 보고 만든 카드예요. 직접 고쳐 주세요.',
    );
  }

  // ---------- 기존 영상 제목·설명·키워드 다듬기 ----------
  /// 바꿀 필요가 없으면 null.
  Future<VideoMeta?> suggestMeta(YtVideo v, StyleCard style) async {
    final r = await _ask<VideoMeta?>(
      'suggestMeta',
      '채널 스타일: ${style.describe()}\n\n현재 제목: ${v.title}\n현재 설명: ${_cut(v.description, 1500)}\n'
          '현재 키워드: ${v.tags.join(', ')}\n\n검색에 잘 걸리고 채널 스타일에 맞게 다듬어 주세요. 낚시성 금지. 제목 100자 이내. '
          '바꿀 필요가 없으면 {"skip":true}. JSON: {"title":"","description":"","tags":[""]}',
      (j) => j['skip'] == true ? null : VideoMeta.fromJson(j),
      () => mockSuggestMeta(v, style),
    );
    if (r == null) return null;
    final cleaned = VideoMeta(
      title: r.title.trim().isEmpty ? v.title : _cut(r.title.trim(), 100),
      description: _cut(r.description, 5000),
      tags: _cleanTags(r.tags),
    );
    return cleaned.sameAs(v.meta) ? null : cleaned;
  }

  static VideoMeta? mockSuggestMeta(YtVideo v, StyleCard style) {
    final topic = style.topics.isNotEmpty ? style.topics.first : '';
    var title = v.title;
    if (!title.contains('|') && topic.isNotEmpty && !title.contains(topic)) {
      title = _cut('$title | $topic', 100);
    } else if (!title.contains('|') && !title.contains('쉽게')) {
      title = _cut('$title | 쉽게 따라하기', 100);
    }
    var desc = v.description;
    if (desc.trim().length < 30) {
      final tagLine = [...v.tags, ...style.topics].take(3).map((t) => '#${t.replaceAll(' ', '')}').join(' ');
      desc =
          '${desc.trim().isEmpty ? v.title : desc.trim()}\n\n'
          '이 영상에서는 ${v.title.split(' ').first} 이야기를 차근차근 소개해요. 도움이 되셨다면 구독과 좋아요 부탁드려요.\n\n$tagLine';
    }
    final tags = _cleanTags([
      ...v.tags,
      ...style.topics.take(4),
      ...topWords([v.title], 2),
    ]);
    final m = VideoMeta(title: title, description: desc, tags: tags);
    return m.sameAs(v.meta) ? null : m;
  }

  // ---------- 새 콘텐츠 기획 ----------
  Future<ContentPlan> planContent(StyleCard style, ContentFormat format, String topic, {String memo = ''}) {
    return _ask(
      'plan_${format.name}',
      '채널 스타일: ${style.describe()}\n형식: ${formatGuide(format)}\n주제: ${topic.isEmpty ? '(채널에 맞게 정해 주세요)' : topic}\n'
          '${memo.isNotEmpty ? '사용자 메모: $memo\n' : ''}'
          '제목·설명·키워드·썸네일 문구·대본(구성)을 함께 만들어 주세요. JSON: '
          '{"title":"","description":"","tags":[""],"thumbnailText":"","script":""}',
      ContentPlan.fromJson,
      () => mockPlan(style, format, topic, memo: memo),
      maxTokens: 4000,
    );
  }

  static String formatGuide(ContentFormat f) {
    switch (f) {
      case ContentFormat.shorts:
        return '쇼츠 (세로 60초 이내, 첫 3초에 핵심)';
      case ContentFormat.long:
        return '롱폼 (8~15분, 도입-본론-정리)';
      case ContentFormat.docu:
        return '다큐멘터리 (15분 이상, 이야기 흐름과 내레이션 중심)';
      case ContentFormat.image:
        return '사진·이미지 게시물 (커뮤니티 게시물, 짧은 글 + 이미지 설명)';
      case ContentFormat.talk:
        return '음성 대화형 (두 사람이 대화하는 형식의 대본)';
    }
  }

  static ContentPlan mockPlan(StyleCard style, ContentFormat format, String topic, {String memo = ''}) {
    final t = topic.trim().isNotEmpty
        ? topic.trim()
        : (memo.trim().isNotEmpty ? _cut(memo.trim(), 20) : (style.topics.isNotEmpty ? style.topics.first : '오늘의 이야기'));
    final head = {
      ContentFormat.shorts: '60초 만에 알아보는',
      ContentFormat.long: '처음부터 차근차근',
      ContentFormat.docu: '이야기로 보는',
      ContentFormat.image: '사진으로 보는',
      ContentFormat.talk: '둘이 나누는',
    }[format]!;
    final lines = switch (format) {
      ContentFormat.shorts => ['[0~3초] $t, 이것만 기억하세요!', '[4~40초] 핵심 세 가지 소개', '[41~60초] 정리 + 구독 부탁'],
      ContentFormat.long => ['1. 인사와 오늘의 주제: $t', '2. 준비물·배경 설명', '3. 본론 (단계별)', '4. 자주 하는 실수', '5. 정리와 다음 영상 예고'],
      ContentFormat.docu => ['프롤로그: $t 이야기의 시작', '1장: 배경', '2장: 사람들', '3장: 변화', '에필로그: 남은 이야기'],
      ContentFormat.image => ['이미지 1: $t 대표 사진', '이미지 2: 과정', '이미지 3: 결과', '글: 짧은 소감과 질문'],
      ContentFormat.talk => ['A: 오늘은 $t 이야기 해 볼까요?', 'B: 좋아요, 저도 궁금했어요.', 'A: 먼저 기본부터…', 'B: 아, 그렇군요!'],
    };
    return ContentPlan(
      title: _cut('$head $t', 100),
      description:
          '$t 에 대한 ${formatGuide(format).split(' ').first} 콘텐츠예요.${memo.isNotEmpty ? '\n\n${_cut(memo, 300)}' : ''}\n\n'
          '#${t.replaceAll(' ', '')} ${style.topics.take(2).map((e) => '#${e.replaceAll(' ', '')}').join(' ')}',
      tags: _cleanTags([t, ...style.topics.take(5)]),
      thumbnailText: _cut(t, 12),
      script: lines.join('\n'),
    );
  }

  // ---------- 검색어 추천 ----------
  /// 제목·키워드를 고칠 때 넣으면 좋은 관련 검색어 (이미 있는 키워드는 빼고).
  Future<List<String>> suggestKeywords(String title, List<String> tags, StyleCard style) async {
    final r = await _ask<List<String>>(
      'keywords',
      '채널 스타일: ${style.describe()}\n제목: $title\n지금 키워드: ${tags.join(', ')}\n'
          '시청자가 유튜브에서 실제로 검색할 만한 관련 검색어 8개를 추천해 주세요. 지금 키워드와 겹치지 않게. '
          'JSON: {"keywords":[""]}',
      (j) => ((j['keywords'] as List<dynamic>?) ?? const []).map((e) => '$e').toList(),
      () => mockKeywords(title, tags, style),
      maxTokens: 600,
    );
    final have = tags.map((e) => e.trim()).toSet();
    return _cleanTags(r).where((k) => !have.contains(k)).take(8).toList();
  }

  static List<String> mockKeywords(String title, List<String> tags, StyleCard style) {
    final base = [
      ...topWords([title], 2),
      ...style.topics.take(2),
    ];
    const suffix = ['만들기', '쉽게', '초보', '꿀팁', '방법', '추천'];
    final out = <String>[];
    for (final b in base) {
      for (final s in suffix) {
        out.add('$b $s');
      }
    }
    return out;
  }

  // ---------- 블로그 ----------
  Future<BlogDraft> writeBlogPost(StyleCard style, String topic) {
    return _ask(
      'blogPost',
      '블로그 스타일: ${style.describe()}\n주제: ${topic.isEmpty ? '(블로그에 맞게)' : topic}\n'
          '1500자 안팎의 블로그 글을 HTML(<h2>,<p>,<ul>)로. JSON: {"title":"","html":"","tags":[""]}',
      (j) => BlogDraft(
        title: '${j['title'] ?? ''}',
        html: '${j['html'] ?? ''}',
        tags: _cleanTags(((j['tags'] as List<dynamic>?) ?? const []).map((e) => '$e').toList()),
      ),
      () {
        final t = topic.trim().isNotEmpty ? topic.trim() : (style.topics.isNotEmpty ? style.topics.first : '오늘의 기록');
        return BlogDraft(
          title: '$t, 직접 해 보고 정리했어요',
          html:
              '<h2>$t 시작하며</h2><p>오늘은 $t 이야기를 정리해 보려고 해요.</p>'
              '<h2>핵심 정리</h2><ul><li>첫째, 기본을 지키기</li><li>둘째, 꾸준히 하기</li><li>셋째, 기록 남기기</li></ul>'
              '<h2>마치며</h2><p>도움이 되셨다면 댓글로 의견 남겨 주세요.</p>',
          tags: _cleanTags([t, ...style.topics.take(4)]),
        );
      },
      maxTokens: 4000,
    );
  }

  Future<({String title, List<String> labels})?> suggestPostMeta(
    String title,
    List<String> labels,
    StyleCard style,
  ) async {
    final r = await _ask<({String title, List<String> labels})?>(
      'suggestPostMeta',
      '블로그 스타일: ${style.describe()}\n현재 글 제목: $title\n현재 라벨: ${labels.join(', ')}\n'
          '검색에 잘 걸리게 제목과 라벨을 다듬어 주세요. 바꿀 필요 없으면 {"skip":true}. JSON: {"title":"","labels":[""]}',
      (j) => j['skip'] == true
          ? null
          : (
              title: '${j['title'] ?? title}',
              labels: ((j['labels'] as List<dynamic>?) ?? const []).map((e) => '$e').toList(),
            ),
      () {
        final topic = style.topics.isNotEmpty ? style.topics.first : '';
        final nt = (!title.contains(topic) && topic.isNotEmpty) ? '$title ($topic)' : title;
        final nl = _cleanTags([...labels, ...style.topics.take(3)]);
        if (nt == title && nl.join() == labels.join()) return null;
        return (title: nt, labels: nl);
      },
    );
    return r;
  }

  // ---------- 사용자 코너: 자막 ----------
  /// 대본/음성 메모 글을 문장 단위로 나눠 영상 길이에 맞춘 SRT 자막.
  static String makeSrt(String text, Duration total) {
    final sentences = text
        .split(RegExp(r'(?<=[.!?。])\s+|\n+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (sentences.isEmpty) return '';
    final totalChars = sentences.fold<int>(0, (s, e) => s + e.length);
    final totalMs = total.inMilliseconds <= 0 ? sentences.length * 3000 : total.inMilliseconds;
    var t = 0;
    final buf = StringBuffer();
    for (var i = 0; i < sentences.length; i++) {
      final dur = (totalMs * sentences[i].length / totalChars).round();
      final end = i == sentences.length - 1 ? totalMs : t + dur;
      buf
        ..writeln(i + 1)
        ..writeln('${_srtTime(t)} --> ${_srtTime(end)}')
        ..writeln(sentences[i])
        ..writeln();
      t = end;
    }
    return buf.toString();
  }

  static String _srtTime(int ms) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = ms ~/ 3600000, m = (ms ~/ 60000) % 60, s = (ms ~/ 1000) % 60, r = ms % 1000;
    return '${two(h)}:${two(m)}:${two(s)},${r.toString().padLeft(3, '0')}';
  }

  // ---------- 공통 도우미 ----------
  static List<String> topWords(List<String> texts, int n) {
    const stop = {'만들기', '영상', '오늘', '이야기', '하는', '방법', '그리고', '정말', '편', '쉽게', '따라하기'};
    final counts = <String, int>{};
    for (final t in texts) {
      for (final raw in t.split(RegExp(r'[\s|()\[\],.!?#:~\-]+'))) {
        final w = raw.replaceAll(RegExp(r'\d+'), '').trim();
        if (w.length < 2 || stop.contains(w)) continue;
        counts[w] = (counts[w] ?? 0) + 1;
      }
    }
    final list = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list.take(n).map((e) => e.key).toList();
  }

  static List<String> _cleanTags(List<String> tags) {
    final seen = <String>{};
    final out = <String>[];
    var total = 0;
    for (final t in tags) {
      final c = t.trim().replaceAll(RegExp(r'[<>]'), '');
      if (c.isEmpty || seen.contains(c)) continue;
      // 유튜브 키워드는 모두 합쳐 500자 제한
      if (total + c.length > 450) break;
      seen.add(c);
      out.add(c);
      total += c.length;
      if (out.length >= 15) break;
    }
    return out;
  }

  static String _cut(String s, int n) => s.length <= n ? s : s.substring(0, n);
}
