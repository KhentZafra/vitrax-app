import 'dart:math' as math;

import 'badge_service.dart';
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

  /// Makes the given hazard reports visible to other users. Called
  /// automatically when a recorded activity is saved.
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

  /// Shared hazards inside [radiusMeters] of a point. The database only
  /// sends back hazards inside a latitude/longitude box around the point,
  /// so a user never downloads the whole country's hazards. Callers still
  /// apply an exact circular distance check on the small result.
  static Future<List<HazardReport>> fetchNear(double lat, double lng, double radiusMeters) async {
    try {
      final dLat = radiusMeters / 111320.0;
      final cosLat = math.cos(lat * math.pi / 180).abs().clamp(0.01, 1.0);
      final dLng = radiusMeters / (111320.0 * cosLat);
      final rows = await _supabase
          .from('hazards')
          .select()
          .eq('shared', true)
          .gte('lat', lat - dLat)
          .lte('lat', lat + dLat)
          .gte('lng', lng - dLng)
          .lte('lng', lng + dLng)
          .limit(500);
      return (rows as List<dynamic>).map((r) => HazardReport.fromMap(r as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Which of [hazardIds] were reported by the current user. Used so the
  /// app never asks you "is it still there?" about your own report.
  static Future<Set<String>> fetchMyReportedIds(List<String> hazardIds) async {
    final user = _supabase.auth.currentUser;
    if (user == null || hazardIds.isEmpty) return {};
    try {
      final rows = await _supabase.from('hazards').select('id').eq('user_id', user.id).inFilter('id', hazardIds);
      return (rows as List).map((r) => (r as Map<String, dynamic>)['id'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Every shared hazard. Avoid for map screens; use [fetchNear].
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
      BadgeService.check(); // Safety Warden progress
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