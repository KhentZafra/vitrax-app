import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/hazard_report.dart';
import '../models/shared_route.dart';

/// Fetches routes shared to the community — any user's activity with
/// `shared = true`, along with who shared it and any shared hazard
/// reports linked to it.
class RouteService {
  static final _supabase = Supabase.instance.client;

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

      return rows.map((row) {
        final id = row['id'] as String;
        return SharedRoute.fromMap(row, hazards: hazardsByActivity[id] ?? []);
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
