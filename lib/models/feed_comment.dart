/// One comment (or reply) on a feed post.
class FeedComment {
  final String id;
  final String userId;
  final String userName;
  final String? avatarUrl;
  final String body;
  final DateTime createdAt;

  /// The specific comment this one replies to (null = top-level comment).
  final String? parentId;

  FeedComment({
    required this.id,
    required this.userId,
    required this.userName,
    this.avatarUrl,
    required this.body,
    required this.createdAt,
    this.parentId,
  });

  factory FeedComment.fromMap(Map<String, dynamic> row) {
    final profile = row['profiles'] as Map<String, dynamic>?;
    final first = profile?['first_name'] as String? ?? '';
    final last = profile?['last_name'] as String? ?? '';
    final name = ('$first $last').trim();
    return FeedComment(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      userName: name.isEmpty ? 'A Vitrax user' : name,
      avatarUrl: profile?['avatar_url'] as String?,
      body: row['body'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      parentId: row['parent_id'] as String?,
    );
  }
}
