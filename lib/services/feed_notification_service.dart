import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/feed_notification.dart';

class FeedNotificationService {
  static final _supabase = Supabase.instance.client;

  static Future<List<FeedNotification>> fetch() async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) return [];
    try {
      final rows = await _supabase
          .from('feed_notifications')
          .select()
          .eq('user_id', me)
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

  static Future<int> unreadCount() async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) return 0;
    try {
      final rows = await _supabase.from('feed_notifications').select('id').eq('user_id', me).eq('is_read', false);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> markAllRead() async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) return;
    try {
      await _supabase.from('feed_notifications').update({'is_read': true}).eq('user_id', me).eq('is_read', false);
    } catch (e) {
      // ignore: avoid_print
      print('FeedNotificationService.markAllRead failed: $e');
    }
  }
}
