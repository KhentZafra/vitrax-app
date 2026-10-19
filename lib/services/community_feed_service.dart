import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/feed_item.dart';

/// One page of feed items plus what is needed to ask for the next page.
class FeedPage {
  final List<FeedItem> items;
  final String? cursor; // database created_at of the last item
  final bool hasMore;
  const FeedPage({required this.items, required this.cursor, required this.hasMore});
}

class _Dated {
  final FeedItem item;
  final String createdAtRaw;
  _Dated(this.item, this.createdAtRaw);
}

/// Fetches the community feed — shared activities AND standalone
/// photo/video posts, merged and sorted newest-first — and handles
/// toggling likes on either kind.
class CommunityFeedService {
  static final _supabase = Supabase.instance.client;

  /// First page of the feed (kept for older callers).
  static Future<List<FeedItem>> fetchFeed() async => (await fetchFeedPage()).items;

  /// One page of the feed, newest first. Pass the previous page's
  /// [FeedPage.cursor] as [before] to get the next 20.
  static Future<FeedPage> fetchFeedPage({String? before, int limit = 20}) async {
    final currentUserId = _supabase.auth.currentUser?.id;

    // Fetched independently and defensively — a problem with one table
    // (e.g. a missing FK, an RLS issue) should never blank out the other
    // half of the feed. This is what silently hid the whole feed before
    // 010_community_posts_profiles_fk.sql was added.
    final activityShares = await _safeFetch(() => _fetchActivityShares(currentUserId, before, limit), label: 'activity shares');
    final standalonePosts = await _safeFetch(() => _fetchStandalonePosts(currentUserId, before, limit), label: 'standalone posts');

    // Merge both sources by database time, keep the newest [limit]. What is
    // left over is older than the cursor, so the next page picks it up.
    final all = [...activityShares, ...standalonePosts];
    all.sort((a, b) => DateTime.parse(b.createdAtRaw).compareTo(DateTime.parse(a.createdAtRaw)));
    final hasMore = all.length > limit || activityShares.length >= limit || standalonePosts.length >= limit;
    final page = all.take(limit).toList();
    return FeedPage(
      items: page.map((d) => d.item).toList(),
      cursor: page.isEmpty ? null : page.last.createdAtRaw,
      hasMore: hasMore && page.isNotEmpty,
    );
  }

  static Future<List<_Dated>> _safeFetch(Future<List<_Dated>> Function() fetch, {required String label}) async {
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

  static Future<List<_Dated>> _fetchActivityShares(String? currentUserId, String? before, int limit) async {
    var query = _supabase
        .from('activities')
        .select('*, profiles(first_name, last_name, avatar_url)')
        .eq('shared', true);
    if (before != null) query = query.lt('created_at', before);
    final rows = await query.order('created_at', ascending: false).limit(limit);

    final activityRows = (rows as List).cast<Map<String, dynamic>>();
    if (activityRows.isEmpty) return [];

    // Privacy: other people's posts show the trimmed route (first/last
    // metres hidden). Your own posts keep the full route.
    for (final row in activityRows) {
      if (row['user_id'] != currentUserId && row['public_route'] != null) {
        row['route'] = row['public_route'];
      }
    }

    final ids = activityRows.map((r) => r['id'] as String).toList();
    final likeRows = await _supabase.from('activity_likes').select('activity_id, user_id').inFilter('activity_id', ids);

    final commentCounts = await _fetchCommentCounts('activity', ids);
    final counts = <String, int>{};
    final likedByMe = <String>{};
    for (final row in (likeRows as List).cast<Map<String, dynamic>>()) {
      final id = row['activity_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
      if (row['user_id'] == currentUserId) likedByMe.add(id);
    }

    return activityRows
        .map((row) => _Dated(
              FeedItem.fromActivityRow(
                row,
                likeCount: counts[row['id']] ?? 0,
                likedByMe: likedByMe.contains(row['id']),
                commentCount: commentCounts[row['id']] ?? 0,
              ),
              row['created_at'].toString(),
            ))
        .toList();
  }

  /// comment count per post id. Returns {} (instead of throwing) if the
  /// comments table isn't set up yet, so the feed still loads.
  static Future<Map<String, int>> _fetchCommentCounts(String kind, List<String> ids) async {
    try {
      final rows = await _supabase.from('feed_comments').select('post_id').eq('post_kind', kind).inFilter('post_id', ids);
      final counts = <String, int>{};
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final id = row['post_id'] as String;
        counts[id] = (counts[id] ?? 0) + 1;
      }
      return counts;
    } catch (e) {
      // ignore: avoid_print
      print('CommunityFeedService: comment counts failed: $e');
      return {};
    }
  }

  /// Display names of the original posters of reshared posts.
  static Future<Map<String, String>> _fetchProfileNames(Set<String> userIds) async {
    if (userIds.isEmpty) return {};
    try {
      final rows = await _supabase.from('profiles').select('id, first_name, last_name').inFilter('id', userIds.toList());
      final names = <String, String>{};
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final name = ('${row['first_name'] ?? ''} ${row['last_name'] ?? ''}').trim();
        names[row['id'] as String] = name.isEmpty ? 'A Vitrax user' : name;
      }
      return names;
    } catch (_) {
      return {};
    }
  }

  static Future<List<_Dated>> _fetchStandalonePosts(String? currentUserId, String? before, int limit) async {
    var query = _supabase
        .from('community_posts')
        .select('*, profiles(first_name, last_name, avatar_url)');
    if (before != null) query = query.lt('created_at', before);
    final rows = await query.order('created_at', ascending: false).limit(limit);

    final postRows = (rows as List).cast<Map<String, dynamic>>();
    if (postRows.isEmpty) return [];

    final ids = postRows.map((r) => r['id'] as String).toList();
    final likeRows = await _supabase.from('post_likes').select('post_id, user_id').inFilter('post_id', ids);

    final commentCounts = await _fetchCommentCounts('post', ids);
    final originalIds = <String>{
      for (final r in postRows)
        if (r['original_user_id'] != null) r['original_user_id'] as String,
    };
    final originalNames = await _fetchProfileNames(originalIds);
    final counts = <String, int>{};
    final likedByMe = <String>{};
    for (final row in (likeRows as List).cast<Map<String, dynamic>>()) {
      final id = row['post_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
      if (row['user_id'] == currentUserId) likedByMe.add(id);
    }

    return postRows
        .map((row) => _Dated(
              FeedItem.fromPostRow(
                row,
                likeCount: counts[row['id']] ?? 0,
                likedByMe: likedByMe.contains(row['id']),
                commentCount: commentCounts[row['id']] ?? 0,
                originalName: originalNames[row['original_user_id']],
              ),
              row['created_at'].toString(),
            ))
        .toList();
  }

  /// Reshares [item] to the community feed as a new post by the current
  /// user, crediting the ORIGINAL poster (even when [item] is itself a
  /// reshare). [note] is the resharer's optional own caption.
  static Future<bool> reshare(FeedItem item, {String? note}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    final String originalKind;
    final String originalId;
    final String originalUserId;
    final String? originalCaption;
    if (item.isReshare) {
      originalKind = item.originalKind ?? 'post';
      originalId = item.originalId ?? item.id;
      originalUserId = item.originalUserId!;
      originalCaption = item.originalCaption;
    } else {
      originalKind = item.kind == FeedItemKind.activityShare ? 'activity' : 'post';
      originalId = item.id;
      originalUserId = item.posterUserId;
      final a = item.activity;
      final fallback = a != null ? '${a.title} · ${a.distanceKm.toStringAsFixed(1)} km' : null;
      originalCaption = (item.caption ?? '').trim().isNotEmpty ? item.caption : fallback;
    }

    if (originalUserId == user.id) return false;

    try {
      await _supabase.from('community_posts').insert({
        'user_id': user.id,
        'media_url': item.mediaUrl,
        'media_type': item.mediaType == null ? null : (item.mediaType == FeedMediaType.photo ? 'photo' : 'video'),
        'caption': (note ?? '').trim().isEmpty ? null : note!.trim(),
        'original_kind': originalKind,
        'original_id': originalId,
        'original_user_id': originalUserId,
        'original_caption': originalCaption,
      });
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('CommunityFeedService.reshare failed: $e');
      return false;
    }
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
