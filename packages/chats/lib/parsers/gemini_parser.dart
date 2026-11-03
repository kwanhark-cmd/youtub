import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/models.dart';
import 'parser_common.dart';

/// 구글 테이크아웃 "내 활동 > Gemini 앱" 기록 파서(JSON 또는 HTML).
/// 기록은 질문 하나씩 따로 있고 대화 ID가 없으므로, 30분 안에 이어진 질문을 한 대화로 묶습니다.
class GeminiParser {
  static const groupGap = Duration(minutes: 30);
  static const notice = '제미나이 기록은 구글 테이크아웃에 일부만 담길 수 있어요(첨부 그림, 지운 기록, 일부 답변이 빠질 수 있음).';

  static final _prefixes = ['Prompted ', 'Prompted: ', '다음 내용으로 질문함: ', '질문함: ', '입력함: ', '프롬프트: '];

  static bool looksLikeJson(dynamic decoded) {
    if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
      final m = decoded.first as Map;
      final header = m['header']?.toString() ?? '';
      final products = m['products'];
      return header.contains('Gemini') ||
          header.contains('제미나이') ||
          (products is List && products.any((p) => p.toString().contains('Gemini'))) ||
          (m.containsKey('title') && m.containsKey('time') && m.containsKey('safeHtmlItem'));
    }
    return false;
  }

  static bool looksLikeHtml(String text) => text.contains('outer-cell') && (text.contains('Gemini') || text.contains('제미나이'));

  static ParseResult parseJson(dynamic decoded) {
    if (decoded is! List) {
      throw UnreadableFileException('제미나이 형식 아님: ${describeStructure(decoded)}');
    }
    final turns = <_Turn>[];
    var skipped = 0;
    for (final item in decoded) {
      try {
        if (item is! Map) {
          skipped++;
          continue;
        }
        final time = parseAnyTime(item['time']);
        final prompt = _stripPrefix(item['title']?.toString() ?? '');
        if (time == null || prompt.isEmpty) {
          skipped++;
          continue;
        }
        final buf = StringBuffer();
        final safe = item['safeHtmlItem'];
        if (safe is List) {
          for (final s in safe) {
            if (s is Map && s['html'] is String) {
              if (buf.isNotEmpty) buf.write('\n');
              buf.write(htmlToText(s['html'] as String));
            }
          }
        }
        final files = <String>[];
        if (item['attachedFiles'] is List) {
          files.addAll((item['attachedFiles'] as List).map((e) => e.toString()));
        }
        if (item['imageFile'] != null) files.add(item['imageFile'].toString());
        turns.add(_Turn(time, prompt, buf.toString().trim(), files));
      } catch (_) {
        skipped++;
      }
    }
    return _group(turns, skipped);
  }

  static ParseResult parseHtml(String text) {
    final doc = html_parser.parse(text);
    final cells = doc.querySelectorAll('div.outer-cell');
    if (cells.isEmpty) {
      throw const UnreadableFileException('제미나이 HTML에 활동 칸(outer-cell)이 없음');
    }
    final turns = <_Turn>[];
    var skipped = 0;
    for (final cell in cells) {
      try {
        final header = cell.querySelector('.header-cell')?.text ?? cell.querySelector('p.mdl-typography--title')?.text ?? '';
        if (header.isNotEmpty && !header.contains('Gemini') && !header.contains('제미나이')) {
          skipped++;
          continue;
        }
        final body = cell
            .querySelectorAll('div.content-cell')
            .firstWhere((e) => !e.classes.contains('mdl-typography--caption'), orElse: () => dom.Element.tag('div'));
        final textNodes = <String>[];
        final responseParts = <String>[];
        for (final node in body.nodes) {
          if (node is dom.Text) {
            final t = node.text.trim();
            if (t.isNotEmpty) textNodes.add(t);
          } else if (node is dom.Element && node.localName != 'br') {
            final t = htmlToText(node.outerHtml);
            if (t.isNotEmpty) responseParts.add(t);
          }
        }
        if (textNodes.isEmpty) {
          skipped++;
          continue;
        }
        DateTime? time;
        var dateIndex = -1;
        for (var i = textNodes.length - 1; i >= 0; i--) {
          time = parseTakeoutDate(textNodes[i]);
          if (time != null) {
            dateIndex = i;
            break;
          }
        }
        if (time == null) {
          skipped++;
          continue;
        }
        final promptParts = <String>[
          for (var i = 0; i < textNodes.length; i++)
            if (i != dateIndex) textNodes[i],
        ];
        final prompt = _stripPrefix(promptParts.isEmpty ? '' : promptParts.first);
        final extra = promptParts.skip(1).join('\n');
        if (prompt.isEmpty) {
          skipped++;
          continue;
        }
        final response = [extra, ...responseParts].where((e) => e.isNotEmpty).join('\n');
        turns.add(_Turn(time, prompt, response, const []));
      } catch (_) {
        skipped++;
      }
    }
    return _group(turns, skipped);
  }

  static String _stripPrefix(String s) {
    var t = s.trim();
    for (final p in _prefixes) {
      if (t.startsWith(p)) {
        t = t.substring(p.length).trim();
        break;
      }
    }
    return t;
  }

  static ParseResult _group(List<_Turn> turns, int skipped) {
    turns.sort((a, b) => a.time.compareTo(b.time));
    final out = <ParsedConversation>[];
    List<_Turn> current = [];
    void flush() {
      if (current.isEmpty) return;
      final msgs = <Message>[];
      for (final t in current) {
        msgs.add(Message(role: Role.user, text: t.prompt, time: t.time, attachments: t.files));
        if (t.response.isNotEmpty) {
          msgs.add(Message(role: Role.assistant, text: t.response, time: t.time));
        }
      }
      out.add(
        ParsedConversation(
          source: AiSource.gemini,
          externalId: 'gemini-${current.first.time.toUtc().millisecondsSinceEpoch}',
          title: makeTitle(null, msgs),
          createdAt: current.first.time,
          updatedAt: current.last.time,
          messages: msgs,
          link: null,
        ),
      );
      current = [];
    }

    for (final t in turns) {
      if (current.isNotEmpty && t.time.difference(current.last.time) > groupGap) {
        flush();
      }
      current.add(t);
    }
    flush();
    return ParseResult(source: AiSource.gemini, conversations: out, skipped: skipped, notices: const [notice]);
  }

  static String htmlToText(String html) {
    final frag = html_parser.parseFragment(
      html
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</(p|div|li|h[1-6])>', caseSensitive: false), '</\$1>\n'),
    );
    return frag.text?.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim() ?? '';
  }

  static const _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  /// 테이크아웃 HTML의 날짜 글자를 읽습니다(영어·한국어).
  static DateTime? parseTakeoutDate(String s) {
    final t = s.replaceAll(' ', ' ').replaceAll(' ', ' ').trim();
    // 한국어: 2025. 10. 3. 오후 4:12:33 KST
    final ko = RegExp(r'(\d{4})\.\s*(\d{1,2})\.\s*(\d{1,2})\.?\s*(오전|오후)?\s*(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(t);
    if (ko != null) {
      var h = int.parse(ko.group(5)!);
      final ap = ko.group(4);
      if (ap == '오후' && h < 12) h += 12;
      if (ap == '오전' && h == 12) h = 0;
      return DateTime(
        int.parse(ko.group(1)!),
        int.parse(ko.group(2)!),
        int.parse(ko.group(3)!),
        h,
        int.parse(ko.group(6)!),
        int.parse(ko.group(7) ?? '0'),
      );
    }
    // 영어: Oct 3, 2025, 4:12:33 PM KST
    final en = RegExp(
      r'([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2}),\s*(\d{4}),?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?',
      caseSensitive: false,
    ).firstMatch(t);
    if (en != null) {
      final mon = _months[en.group(1)!.toLowerCase()];
      if (mon == null) return null;
      var h = int.parse(en.group(4)!);
      final ap = en.group(7)?.toUpperCase();
      if (ap == 'PM' && h < 12) h += 12;
      if (ap == 'AM' && h == 12) h = 0;
      return DateTime(int.parse(en.group(3)!), mon, int.parse(en.group(2)!), h, int.parse(en.group(5)!), int.parse(en.group(6) ?? '0'));
    }
    // 2025-10-03 16:12:33 같은 형식
    final iso = DateTime.tryParse(t);
    return iso;
  }
}

class _Turn {
  final DateTime time;
  final String prompt;
  final String response;
  final List<String> files;
  _Turn(this.time, this.prompt, this.response, this.files);
}
