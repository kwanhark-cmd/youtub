/// 앱 전체에서 쓰는 데이터 모양.
library;

enum AiSource { claude, chatgpt, gemini }

extension AiSourceInfo on AiSource {
  String get label => switch (this) {
    AiSource.claude => '클로드',
    AiSource.chatgpt => '챗GPT',
    AiSource.gemini => '제미나이',
  };

  String get key => name;

  static AiSource? fromKey(String? k) {
    for (final s in AiSource.values) {
      if (s.name == k) return s;
    }
    return null;
  }
}

enum Role { user, assistant, system }

class Message {
  final Role role;
  final String text;
  final DateTime? time;
  final List<String> attachments;

  const Message({required this.role, required this.text, this.time, this.attachments = const []});

  Map<String, dynamic> toJson() => {
    'r': role.name,
    't': text,
    if (time != null) 'd': time!.millisecondsSinceEpoch,
    if (attachments.isNotEmpty) 'a': attachments,
  };

  factory Message.fromJson(Map<String, dynamic> j) => Message(
    role: Role.values.firstWhere((r) => r.name == j['r'], orElse: () => Role.user),
    text: (j['t'] ?? '') as String,
    time: j['d'] is int ? DateTime.fromMillisecondsSinceEpoch(j['d'] as int) : null,
    attachments: (j['a'] as List?)?.map((e) => e.toString()).toList() ?? const [],
  );
}

/// 파서가 만든 대화(아직 저장 전).
class ParsedConversation {
  final AiSource source;
  final String externalId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Message> messages;
  final String? link;

  const ParsedConversation({
    required this.source,
    required this.externalId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.link,
  });

  bool get hasAttachments => messages.any((m) => m.attachments.isNotEmpty);
}

/// 저장된 대화의 목록용 정보(본문 제외).
class ConversationSummary {
  final int id;
  final AiSource source;
  final String externalId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;
  final bool starred;
  final String? summary;
  final String? link;
  final bool hasAttachments;
  final DateTime importedAt;

  const ConversationSummary({
    required this.id,
    required this.source,
    required this.externalId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messageCount,
    required this.starred,
    required this.summary,
    required this.link,
    required this.hasAttachments,
    required this.importedAt,
  });
}

class Topic {
  final int id;
  final String name;
  final int? parentId;
  final int count;

  const Topic({required this.id, required this.name, this.parentId, this.count = 0});
}

class Note {
  final int id;
  final int conversationId;
  final DateTime createdAt;
  final String text;
  final bool byVoice;

  const Note({required this.id, required this.conversationId, required this.createdAt, required this.text, required this.byVoice});
}

class UserProfile {
  final String id;
  final String name;
  final String emoji;
  final String? pinHash;
  final DateTime createdAt;

  const UserProfile({required this.id, required this.name, required this.emoji, this.pinHash, required this.createdAt});

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    if (pinHash != null) 'pin': pinHash,
    'created': createdAt.toIso8601String(),
  };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    id: j['id'] as String,
    name: j['name'] as String,
    emoji: (j['emoji'] ?? '🙂') as String,
    pinHash: j['pin'] as String?,
    createdAt: DateTime.tryParse(j['created'] ?? '') ?? DateTime.now(),
  );
}
