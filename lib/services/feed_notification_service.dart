import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/feed_notification.dart';

class FeedNotificationService {
  static final _supabase = Supabase.instance.client;

  /// Types that belong to the Community feed. Everything else (route likes,
  /// retraces, badges) only shows in the general Home bell.
  static const communityTypes = ['like', 'comment', 'reply', 'reshare'];

  static Future<List<FeedNotification>> fetch({bool communityOnly = false}) async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) return [];
    try {
      var q = _supabase.from('feed_notifications').select().eq('user_id', me);
      if (communityOnly) q = q.inFilter('type', communityTypes);
      final rows = await q
          .order('created_at', ascending: false)
          .limit(100);
      final list = (rows as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) return [];
      final actorIds = list.map((r) => r['actor_id'] as String).toSet().toList();
      final profileRows = await _supabase.from('profiles').select('id, first_name, last_name, avatar_url').inFilter('id', actorIds);
      final profiles = {for (final p in (profileRows as List).cast<Map<String, dynamic>>()) p['id'] as String: p};
      return list.map((r) => FeedNotification.fromMap(r, profiles)).toList();
    } catch (e) {
      // ignore: avoid_print
      print('FeedNotificationService.fetch failed: $e');
      return [];
    }
  }

  static Future<int> unreadCount({bool communityOnly = false}) async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) return 0;
    try {
      var q = _supabase.from('feed_notifications').select('id').eq('user_id', me).eq('is_read', false);
      if (communityOnly) q = q.inFilter('type', communityTypes);
      final rows = await q;
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> markAllRead({bool communityOnly = false}) async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) return;
    try {
      var q = _supabase.from('feed_notifications').update({'is_read': true}).eq('user_id', me).eq('is_read', false);
      if (communityOnly) q = q.inFilter('type', communityTypes);
      await q;
    } catch (e) {
      // ignore: avoid_print
      print('FeedNotificationService.markAllRead failed: $e');
    }
  }
}
