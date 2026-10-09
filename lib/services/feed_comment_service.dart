import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/feed_comment.dart';
import '../models/feed_item.dart';

/// Comments and replies on feed posts (both activity-shares and
/// standalone posts).
class FeedCommentService {
  static final _supabase = Supabase.instance.client;

  static String kindKey(FeedItemKind kind) => kind == FeedItemKind.activityShare ? 'activity' : 'post';

  /// All comments for [item], oldest first.
  static Future<List<FeedComment>> fetch(FeedItem item) async {
    try {
      final rows = await _supabase
          .from('feed_comments')
          .select('*, profiles(first_name, last_name, avatar_url)')
          .eq('post_kind', kindKey(item.kind))
          .eq('post_id', item.id)
          .order('created_at', ascending: true);
      return (rows as List).cast<Map<String, dynamic>>().map(FeedComment.fromMap).toList();
    } catch (e) {
      // ignore: avoid_print
      print('FeedCommentService.fetch failed: $e');
      return [];
    }
  }

  /// Adds a comment; pass [parentId] to reply to a specific comment.
  static Future<bool> add(FeedItem item, String body, {String? parentId}) async {
    final user = _supabase.auth.currentUser;
    final text = body.trim();
    if (user == null || text.isEmpty) return false;
    try {
      await _supabase.from('feed_comments').insert({
        'post_kind': kindKey(item.kind),
        'post_id': item.id,
        'user_id': user.id,
        'parent_id': parentId,
        'body': text,
      });
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('FeedCommentService.add failed: $e');
      return false;
    }
  }

  /// Deletes your own comment (its replies go with it).
  static Future<bool> delete(String commentId) async {
    try {
      await _supabase.from('feed_comments').delete().eq('id', commentId);
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('FeedCommentService.delete failed: $e');
      return false;
    }
  }
}
