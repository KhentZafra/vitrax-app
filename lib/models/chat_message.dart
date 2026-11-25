/// A single message within a conversation.
class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final bool isMine;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    required this.isMine,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map, {required String currentUserId}) {
    return ChatMessage(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      isMine: map['sender_id'] == currentUserId,
    );
  }
}

/// One emoji reaction on a message (one per person per message).
class ChatReaction {
  final String messageId;
  final String userId;
  final String emoji;
  ChatReaction({required this.messageId, required this.userId, required this.emoji});

  factory ChatReaction.fromMap(Map<String, dynamic> m) =>
      ChatReaction(messageId: m['message_id'] as String, userId: m['user_id'] as String, emoji: m['emoji'] as String);
}

/// One row in the chat list — a conversation with the other participant
/// and a preview of the most recent message.
class ChatConversation {
  final String id;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatarUrl;
  final String? lastMessageBody;
  final DateTime? lastMessageAt;
  // True only when the most recent message is from the OTHER person and
  // you haven't opened this conversation since it arrived — sending the
  // last message yourself never counts as "unread" for you.
  final bool isUnread;
  // True while this chat sits in "Archived chats" (per person).
  final bool isArchived;

  ChatConversation({
    required this.id,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatarUrl,
    this.lastMessageBody,
    this.lastMessageAt,
    this.isUnread = false,
    this.isArchived = false,
  });
}
