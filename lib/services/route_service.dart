import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/hazard_report.dart';
import '../models/shared_route.dart';

/// Fetches routes shared to the community — any user's activity with
/// `shared = true`, along with who shared it and any shared hazard
/// reports linked to it.
class RouteService {
  static final _supabase = Supabase.instance.client;

  /// Likes or unlikes a shared route. Returns true on success.
  static Future<bool> setLike(String routeId, {required bool like}) async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) return false;
    try {
      if (like) {
        await _supabase.from('route_likes').upsert({'route_id': routeId, 'user_id': me});
      } else {
        await _supabase.from('route_likes').delete().eq('route_id', routeId).eq('user_id', me);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<SharedRoute>> fetchSharedRoutes() async {
    try {
      final activityRows = await _supabase
          .from('activities')
          .select('*, profiles(first_name, last_name, avatar_url)')
          .eq('shared', true)
          .order('created_at', ascending: false);

      final rows = (activityRows as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return [];

      final activityIds = rows.map((r) => r['id'] as String).toList();

      final hazardRows = await _supabase
          .from('hazards')
          .select()
          .eq('shared', true)
          .inFilter('activity_id', activityIds);

      final hazardsByActivity = <String, List<HazardReport>>{};
      for (final row in (hazardRows as List).cast<Map<String, dynamic>>()) {
        final hazard = HazardReport.fromMap(row);
        final activityId = row['activity_id'] as String?;
        if (activityId == null) continue;
        hazardsByActivity.putIfAbsent(activityId, () => []).add(hazard);
      }

      // Likes (best effort: if the table isn't there yet, routes still load).
      final likeCounts = <String, int>{};
      final likedByMe = <String>{};
      try {
        final me = _supabase.auth.currentUser?.id;
        final likeRows = await _supabase.from('route_likes').select('route_id, user_id').inFilter('route_id', activityIds);
        for (final row in (likeRows as List).cast<Map<String, dynamic>>()) {
          final id = row['route_id'] as String;
          likeCounts[id] = (likeCounts[id] ?? 0) + 1;
          if (row['user_id'] == me) likedByMe.add(id);
        }
      } catch (_) {}

      return rows.map((row) {
        final id = row['id'] as String;
        return SharedRoute.fromMap(row, hazards: hazardsByActivity[id] ?? [], likeCount: likeCounts[id] ?? 0, likedByMe: likedByMe.contains(id));
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
