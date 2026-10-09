/// One "someone interacted with your post" notification.
class FeedNotification {
  final String id;
  final String actorId;
  final String actorName;
  final String? actorAvatarUrl;
  final String type; // like | comment | reply | reshare
  final String postKind; // activity | post
  final String postId;
  final String? body;
  final bool isRead;
  final DateTime createdAt;

  FeedNotification({
    required this.id,
    required this.actorId,
    required this.actorName,
    this.actorAvatarUrl,
    required this.type,
    required this.postKind,
    required this.postId,
    this.body,
    required this.isRead,
    required this.createdAt,
  });

  String get message {
    switch (type) {
      case 'like':
        return 'liked your post.';
      case 'comment':
        return 'commented on your post.';
      case 'reply':
        return 'replied to your comment.';
      case 'reshare':
        return 'reshared your post.';
      default:
        return 'interacted with your post.';
    }
  }

  factory FeedNotification.fromMap(Map<String, dynamic> row, Map<String, Map<String, dynamic>> profiles) {
    final actorId = row['actor_id'] as String;
    final p = profiles[actorId];
    final name = ('${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}').trim();
    return FeedNotification(
      id: row['id'] as String,
      actorId: actorId,
      actorName: name.isEmpty ? 'A Vitrax user' : name,
      actorAvatarUrl: p?['avatar_url'] as String?,
      type: row['type'] as String,
      postKind: row['post_kind'] as String,
      postId: row['post_id'] as String,
      body: row['body'] as String?,
      isRead: row['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
