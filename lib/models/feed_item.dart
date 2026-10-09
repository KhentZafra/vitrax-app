import 'activity.dart';

enum FeedItemKind { activityShare, standalonePost }

enum FeedMediaType { photo, video }

FeedMediaType? _mediaTypeFromString(String? s) {
  switch (s) {
    case 'photo':
      return FeedMediaType.photo;
    case 'video':
      return FeedMediaType.video;
    default:
      return null;
  }
}

/// A single card in the Community Feed. Either wraps a shared [Activity]
/// (kind == activityShare) or a standalone photo/video post that has no
/// linked activity (kind == standalonePost).
///
/// Both kinds share the same shape for display purposes (sharer, caption,
/// media, timestamp, likes) so the feed can render them with one widget —
/// [activity] is only non-null for the activityShare kind.
class FeedItem {
  final String id; // activity id or post id, depending on kind
  final FeedItemKind kind;
  final String posterUserId;
  final String sharerName;
  final String? sharerAvatarUrl;
  final String? caption;
  final String? mediaUrl;
  final FeedMediaType? mediaType; // null only for an activity-share with no photo (shows route sketch)
  final DateTime createdAt;
  final int likeCount;
  final bool likedByMe;
  final Activity? activity; // non-null only when kind == activityShare
  final int commentCount;

  // Reshare info: non-null originalUserId means this card is a reshare of
  // someone else's post, and credits that original poster.
  final String? originalKind; // 'activity' | 'post'
  final String? originalId;
  final String? originalUserId;
  final String? originalName;
  final String? originalCaption;

  bool get isReshare => originalUserId != null;

  FeedItem({
    required this.id,
    required this.kind,
    required this.posterUserId,
    required this.sharerName,
    this.sharerAvatarUrl,
    this.caption,
    this.mediaUrl,
    this.mediaType,
    required this.createdAt,
    required this.likeCount,
    required this.likedByMe,
    this.activity,
    this.commentCount = 0,
    this.originalKind,
    this.originalId,
    this.originalUserId,
    this.originalName,
    this.originalCaption,
  });

  factory FeedItem.fromActivityRow(Map<String, dynamic> row, {required int likeCount, required bool likedByMe, int commentCount = 0}) {
    final activity = Activity.fromMap(row);
    final profile = row['profiles'] as Map<String, dynamic>?;
    final first = profile?['first_name'] as String? ?? '';
    final last = profile?['last_name'] as String? ?? '';
    final name = ('$first $last').trim();

    return FeedItem(
      id: activity.id!,
      kind: FeedItemKind.activityShare,
      posterUserId: activity.userId,
      sharerName: name.isEmpty ? 'A Vitrax user' : name,
      sharerAvatarUrl: profile?['avatar_url'] as String?,
      caption: activity.caption,
      mediaUrl: activity.photoUrl,
      mediaType: activity.photoUrl != null ? FeedMediaType.photo : null,
      createdAt: activity.startedAt,
      likeCount: likeCount,
      likedByMe: likedByMe,
      activity: activity,
      commentCount: commentCount,
    );
  }

  factory FeedItem.fromPostRow(Map<String, dynamic> row, {required int likeCount, required bool likedByMe, int commentCount = 0, String? originalName}) {
    final profile = row['profiles'] as Map<String, dynamic>?;
    final first = profile?['first_name'] as String? ?? '';
    final last = profile?['last_name'] as String? ?? '';
    final name = ('$first $last').trim();

    return FeedItem(
      id: row['id'] as String,
      kind: FeedItemKind.standalonePost,
      posterUserId: row['user_id'] as String,
      sharerName: name.isEmpty ? 'A Vitrax user' : name,
      sharerAvatarUrl: profile?['avatar_url'] as String?,
      caption: row['caption'] as String?,
      mediaUrl: row['media_url'] as String?,
      mediaType: _mediaTypeFromString(row['media_type'] as String?),
      createdAt: DateTime.parse(row['created_at'] as String),
      likeCount: likeCount,
      likedByMe: likedByMe,
      commentCount: commentCount,
      originalKind: row['original_kind'] as String?,
      originalId: row['original_id'] as String?,
      originalUserId: row['original_user_id'] as String?,
      originalName: originalName,
      originalCaption: row['original_caption'] as String?,
    );
  }

  FeedItem copyWith({int? likeCount, bool? likedByMe, int? commentCount}) {
    return FeedItem(
      id: id,
      kind: kind,
      posterUserId: posterUserId,
      sharerName: sharerName,
      sharerAvatarUrl: sharerAvatarUrl,
      caption: caption,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      createdAt: createdAt,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe,
      activity: activity,
      commentCount: commentCount ?? this.commentCount,
      originalKind: originalKind,
      originalId: originalId,
      originalUserId: originalUserId,
      originalName: originalName,
      originalCaption: originalCaption,
    );
  }
}
