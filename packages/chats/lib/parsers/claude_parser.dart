import '../models/models.dart';
import 'parser_common.dart';

/// Claude 내보내기(conversations.json) 파서.
/// 형식: [{uuid, name, created_at, updated_at, chat_messages:[{sender, text, content[], attachments[], files[]}]}]
class ClaudeParser {
  static bool looksLike(dynamic decoded) {
    if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
      final m = decoded.first as Map;
      return m.containsKey('chat_messages') || (m.containsKey('uuid') && m.containsKey('name') && !m.containsKey('mapping'));
    }
    return false;
  }

  static ParseResult parse(dynamic decoded) {
    if (decoded is! List) {
      throw UnreadableFileException('클로드 형식 아님: ${describeStructure(decoded)}');
    }
    final out = <ParsedConversation>[];
    var skipped = 0;
    for (final item in decoded) {
      try {
        if (item is! Map) {
          skipped++;
          continue;
        }
        final id = item['uuid']?.toString();
        if (id == null || id.isEmpty) {
          skipped++;
          continue;
        }
        final msgs = <Message>[];
        final rawMsgs = item['chat_messages'];
        if (rawMsgs is List) {
          for (final rm in rawMsgs) {
            if (rm is! Map) continue;
            Message? m;
            try {
              m = _message(rm);
            } catch (_) {
              continue; // 메시지 하나가 이상해도 대화는 살림
            }
            if (m != null) msgs.add(m);
          }
        }
        final created = parseAnyTime(item['created_at']) ?? msgs.firstOrNull?.time ?? DateTime.now();
        final updated = parseAnyTime(item['updated_at']) ?? created;
        out.add(
          ParsedConversation(
            source: AiSource.claude,
            externalId: id,
            title: makeTitle(item['name']?.toString(), msgs),
            createdAt: created,
            updatedAt: updated,
            messages: msgs,
            link: 'https://claude.ai/chat/$id',
          ),
        );
      } catch (_) {
        skipped++;
      }
    }
    return ParseResult(source: AiSource.claude, conversations: out, skipped: skipped);
  }

  static Message? _message(Map rm) {
    final sender = rm['sender']?.toString();
    final role = sender == 'human'
        ? Role.user
        : sender == 'assistant'
        ? Role.assistant
        : Role.system;
    final buf = StringBuffer();
    final content = rm['content'];
    if (content is List && content.isNotEmpty) {
      for (final c in content) {
        if (c is! Map) continue;
        final type = c['type'];
        if (type == 'text' && c['text'] is String) {
          if (buf.isNotEmpty) buf.write('\n');
          buf.write(c['text']);
        } else if (type == 'tool_use' && c['input'] is Map) {
          // 아티팩트(문서·코드)는 제목과 내용을 함께 보여줌
          final input = c['input'] as Map;
          final title = input['title']?.toString();
          final body = input['content']?.toString();
          if (body != null && body.isNotEmpty) {
            if (buf.isNotEmpty) buf.write('\n');
            if (title != null) buf.write('[$title]\n');
            buf.write(body);
          }
        }
        // thinking, tool_result, token_budget 등은 건너뜀
      }
    }
    if (buf.isEmpty && rm['text'] is String) buf.write(rm['text']);
    final attachments = <String>[];
    for (final key in ['attachments', 'files']) {
      final list = rm[key];
      if (list is List) {
        for (final a in list) {
          if (a is Map && a['file_name'] != null) {
            final name = a['file_name'].toString();
            if (!attachments.contains(name)) attachments.add(name);
          }
        }
      }
    }
    final text = buf.toString().trim();
    if (text.isEmpty && attachments.isEmpty) return null;
    return Message(role: role, text: text, time: parseAnyTime(rm['created_at']), attachments: attachments);
  }
}
