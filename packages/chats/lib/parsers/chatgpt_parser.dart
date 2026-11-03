import '../models/models.dart';
import 'parser_common.dart';

/// ChatGPT 내보내기(conversations.json / conversations-000.json …) 파서.
/// mapping 트리에서 current_node부터 부모로 거슬러 올라가 실제로 이어진 대화만 읽습니다.
class ChatGptParser {
  static bool looksLike(dynamic decoded) {
    if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
      return (decoded.first as Map).containsKey('mapping');
    }
    return false;
  }

  static ParseResult parse(dynamic decoded) {
    if (decoded is! List) {
      throw UnreadableFileException('챗GPT 형식 아님: ${describeStructure(decoded)}');
    }
    final out = <ParsedConversation>[];
    var skipped = 0;
    for (final item in decoded) {
      try {
        if (item is! Map || item['mapping'] is! Map) {
          skipped++;
          continue;
        }
        final id = (item['conversation_id'] ?? item['id'])?.toString();
        if (id == null || id.isEmpty) {
          skipped++;
          continue;
        }
        final mapping = item['mapping'] as Map;
        final msgs = _thread(mapping, item['current_node']?.toString());
        final created = parseAnyTime(item['create_time']) ?? msgs.firstOrNull?.time ?? DateTime.now();
        final updated = parseAnyTime(item['update_time']) ?? created;
        out.add(
          ParsedConversation(
            source: AiSource.chatgpt,
            externalId: id,
            title: makeTitle(item['title']?.toString(), msgs),
            createdAt: created,
            updatedAt: updated,
            messages: msgs,
            link: 'https://chatgpt.com/c/$id',
          ),
        );
      } catch (_) {
        skipped++;
      }
    }
    return ParseResult(source: AiSource.chatgpt, conversations: out, skipped: skipped);
  }

  static List<Message> _thread(Map mapping, String? currentNode) {
    final ids = <String>[];
    var node = currentNode;
    if (node == null || !mapping.containsKey(node)) {
      // current_node가 없으면 가장 마지막 잎 노드를 찾음
      node = _lastLeaf(mapping);
    }
    final seen = <String>{};
    while (node != null && mapping[node] is Map && seen.add(node)) {
      ids.add(node);
      node = (mapping[node] as Map)['parent']?.toString();
    }
    final msgs = <Message>[];
    for (final nid in ids.reversed) {
      final n = mapping[nid] as Map;
      final m = n['message'];
      if (m is! Map) continue;
      Message? parsed;
      try {
        parsed = _message(m);
      } catch (_) {
        continue; // 메시지 하나가 이상해도 대화는 살림
      }
      if (parsed != null) msgs.add(parsed);
    }
    return msgs;
  }

  static String? _lastLeaf(Map mapping) {
    String? best;
    double bestTime = -1;
    mapping.forEach((k, v) {
      if (v is Map && (v['children'] is! List || (v['children'] as List).isEmpty)) {
        final t = (v['message'] is Map ? (v['message'] as Map)['create_time'] : null);
        final tv = t is num ? t.toDouble() : 0.0;
        if (tv >= bestTime) {
          bestTime = tv;
          best = k.toString();
        }
      }
    });
    return best;
  }

  static Message? _message(Map m) {
    final roleStr = (m['author'] is Map ? (m['author'] as Map)['role'] : null)?.toString();
    final role = switch (roleStr) {
      'user' => Role.user,
      'assistant' => Role.assistant,
      _ => null,
    };
    if (role == null) return null; // system, tool 메시지는 숨김
    final meta = m['metadata'];
    if (meta is Map && meta['is_visually_hidden_from_conversation'] == true) {
      return null;
    }
    final content = m['content'];
    final buf = StringBuffer();
    final attachments = <String>[];
    if (content is Map) {
      final type = content['content_type']?.toString();
      if (type == 'thoughts' || type == 'reasoning_recap' || type == 'user_editable_context') {
        return null;
      }
      final parts = content['parts'];
      if (parts is List) {
        for (final p in parts) {
          if (p is String) {
            if (p.trim().isEmpty) continue;
            if (buf.isNotEmpty) buf.write('\n');
            buf.write(p);
          } else if (p is Map) {
            if (p['asset_pointer'] != null || p['content_type'] == 'image_asset_pointer') {
              attachments.add('그림');
            } else if (p['text'] is String) {
              if (buf.isNotEmpty) buf.write('\n');
              buf.write(p['text']);
            }
          }
        }
      } else if (content['text'] is String) {
        buf.write(content['text']);
      }
    }
    if (meta is Map && meta['attachments'] is List) {
      for (final a in meta['attachments'] as List) {
        if (a is Map && a['name'] != null) attachments.add(a['name'].toString());
      }
    }
    final text = buf.toString().trim();
    if (text.isEmpty && attachments.isEmpty) return null;
    return Message(role: role, text: text, time: parseAnyTime(m['create_time']), attachments: attachments);
  }
}
