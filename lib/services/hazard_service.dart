import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/hazard_report.dart';

/// Supabase calls for hazard reports: reporting, undoing, linking to the
/// activity they were reported during, and sharing them community-wide.
class HazardService {
  static final _supabase = Supabase.instance.client;

  static Future<HazardReport?> report(HazardReport hazard, {String? activityId}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final inserted = await _supabase
          .from('hazards')
          .insert(hazard.toInsertMap(userId: user.id, activityId: activityId))
          .select()
          .single();

      return hazard.copyWith(id: inserted['id'] as String);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> delete(String hazardId) async {
    try {
      await _supabase.from('hazards').delete().eq('id', hazardId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Associates hazard reports made during a recording with the activity
  /// they belong to, once that activity is saved. Doesn't affect
  /// visibility on its own — see [shareHazards] for that.
  static Future<void> linkToActivity(List<String> hazardIds, String activityId) async {
    if (hazardIds.isEmpty) return;
    try {
      await _supabase.from('hazards').update({'activity_id': activityId}).inFilter('id', hazardIds);
    } catch (e) {
      // ignore: avoid_print
      print('HazardService.linkToActivity failed: $e');
      // Non-critical — hazards still exist and are still owned by the
      // user even if this link fails; just won't be grouped under the
      // activity for reference.
    }
  }

  /// Makes the given hazard reports visible to other users. Called when
  /// the user taps "Share to Community" on the post-recording modal.
  static Future<bool> shareHazards(List<String> hazardIds) async {
    if (hazardIds.isEmpty) return true;
    try {
      await _supabase.from('hazards').update({'shared': true}).inFilter('id', hazardIds);
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('HazardService.shareHazards failed: $e');
      return false;
    }
  }

  /// Fetches every hazard report that's been shared community-wide.
  /// No PostGIS/geo-query extension is set up, so this pulls all shared
  /// rows and the caller filters by distance client-side — fine for a
  /// small-to-medium dataset; revisit with a bounding-box query or
  /// PostGIS if hazard volume grows large.
  static Future<List<HazardReport>> fetchShared() async {
    try {
      final rows = await _supabase.from('hazards').select().eq('shared', true);
      return (rows as List<dynamic>).map((r) => HazardReport.fromMap(r as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Confirms "this is clear now" for [hazardId] as the current user.
  /// Per the panel's spec, once a hazard reaches 3 distinct confirmations
  /// it's automatically deleted server-side (see
  /// 012_hazard_clear_now.sql's trigger) — this call doesn't need to
  /// handle that itself, it just registers one vote. Returns false if
  /// the confirmation couldn't be recorded — most commonly because
  /// you're the original reporter (blocked by RLS; the reporter has
  /// their own "Undo" flow instead) or you already confirmed this one.
  static Future<bool> confirmClear(String hazardId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    try {
      await _supabase.from('hazard_clear_confirmations').insert({'hazard_id': hazardId, 'user_id': user.id});
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('HazardService.confirmClear failed: $e');
      return false;
    }
  }

  /// Confirmation counts and "did I already confirm this" for a set of
  /// hazard ids — used to show "2/3 confirmed clear" and disable the
  /// button for hazards you've already voted on.
  static Future<Map<String, ({int count, bool byMe})>> fetchClearStatus(List<String> hazardIds) async {
    if (hazardIds.isEmpty) return {};
    final currentUserId = _supabase.auth.currentUser?.id;

    try {
      final rows = await _supabase.from('hazard_clear_confirmations').select('hazard_id, user_id').inFilter('hazard_id', hazardIds);

      final counts = <String, int>{};
      final byMe = <String>{};
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final id = row['hazard_id'] as String;
        counts[id] = (counts[id] ?? 0) + 1;
        if (row['user_id'] == currentUserId) byMe.add(id);
      }

      return {for (final id in hazardIds) id: (count: counts[id] ?? 0, byMe: byMe.contains(id))};
    } catch (e) {
      // ignore: avoid_print
      print('HazardService.fetchClearStatus failed: $e');
      return {};
    }
  }
}