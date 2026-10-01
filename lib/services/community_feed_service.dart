import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/feed_item.dart';

/// Fetches the community feed — shared activities AND standalone
/// photo/video posts, merged and sorted newest-first — and handles
/// toggling likes on either kind.
class CommunityFeedService {
  static final _supabase = Supabase.instance.client;

  static Future<List<FeedItem>> fetchFeed() async {
    final currentUserId = _supabase.auth.currentUser?.id;

    // Fetched independently and defensively — a problem with one table
    // (e.g. a missing FK, an RLS issue) should never blank out the other
    // half of the feed. This is what silently hid the whole feed before
    // 010_community_posts_profiles_fk.sql was added.
    final activityShares = await _safeFetch(() => _fetchActivityShares(currentUserId), label: 'activity shares');
    final standalonePosts = await _safeFetch(() => _fetchStandalonePosts(currentUserId), label: 'standalone posts');

    final items = [...activityShares, ...standalonePosts];
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  static Future<List<FeedItem>> _safeFetch(Future<List<FeedItem>> Function() fetch, {required String label}) async {
    try {
      return await fetch();
    } catch (e) {
      // Logged instead of swallowed silently, so a broken query shows up
      // in your console the moment it happens instead of just looking
      // like "no posts."
      // ignore: avoid_print
      print('CommunityFeedService: failed to fetch $label: $e');
      return [];
    }
  }

  static Future<List<FeedItem>> _fetchActivityShares(String? currentUserId) async {
    final rows = await _supabase
        .from('activities')
        .select('*, profiles(first_name, last_name, avatar_url)')
        .eq('shared', true)
        .order('created_at', ascending: false);

    final activityRows = (rows as List).cast<Map<String, dynamic>>();
    if (activityRows.isEmpty) return [];

    final ids = activityRows.map((r) => r['id'] as String).toList();
    final likeRows = await _supabase.from('activity_likes').select('activity_id, user_id').inFilter('activity_id', ids);

    final counts = <String, int>{};
    final likedByMe = <String>{};
    for (final row in (likeRows as List).cast<Map<String, dynamic>>()) {
      final id = row['activity_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
      if (row['user_id'] == currentUserId) likedByMe.add(id);
    }

    return activityRows
        .map((row) => FeedItem.fromActivityRow(
              row,
              likeCount: counts[row['id']] ?? 0,
              likedByMe: likedByMe.contains(row['id']),
            ))
        .toList();
  }

  static Future<List<FeedItem>> _fetchStandalonePosts(String? currentUserId) async {
    final rows = await _supabase
        .from('community_posts')
        .select('*, profiles(first_name, last_name, avatar_url)')
        .order('created_at', ascending: false);

    final postRows = (rows as List).cast<Map<String, dynamic>>();
    if (postRows.isEmpty) return [];

    final ids = postRows.map((r) => r['id'] as String).toList();
    final likeRows = await _supabase.from('post_likes').select('post_id, user_id').inFilter('post_id', ids);

    final counts = <String, int>{};
    final likedByMe = <String>{};
    for (final row in (likeRows as List).cast<Map<String, dynamic>>()) {
      final id = row['post_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
      if (row['user_id'] == currentUserId) likedByMe.add(id);
    }

    return postRows
        .map((row) => FeedItem.fromPostRow(
              row,
              likeCount: counts[row['id']] ?? 0,
              likedByMe: likedByMe.contains(row['id']),
            ))
        .toList();
  }

  /// Toggles a like on either an activity-share or a standalone post.
  /// Returns the new liked state on success, null on failure.
  static Future<bool?> toggleLike(FeedItem item, {required bool currentlyLiked}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final table = item.kind == FeedItemKind.activityShare ? 'activity_likes' : 'post_likes';
    final column = item.kind == FeedItemKind.activityShare ? 'activity_id' : 'post_id';

    try {
      if (currentlyLiked) {
        await _supabase.from(table).delete().eq(column, item.id).eq('user_id', user.id);
        return false;
      } else {
        await _supabase.from(table).insert({column: item.id, 'user_id': user.id});
        return true;
      }
    } catch (_) {
      return null;
    }
  }

  /// Creates a standalone post (no linked activity) with an already
  /// -uploaded media URL.
  static Future<bool> createPost({
    required String mediaUrl,
    required FeedMediaType mediaType,
    String? caption,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      await _supabase.from('community_posts').insert({
        'user_id': user.id,
        'media_url': mediaUrl,
        'media_type': mediaType == FeedMediaType.photo ? 'photo' : 'video',
        'caption': caption,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
