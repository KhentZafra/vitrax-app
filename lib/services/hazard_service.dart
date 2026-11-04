import 'dart:io';
import 'dart:math' as math;

import 'badge_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/hazard_report.dart';

/// Supabase calls for hazard reports: reporting, undoing, linking to the
/// activity they were reported during, and sharing them community-wide.
class HazardService {
  static final _supabase = Supabase.instance.client;

  /// True when the last [report] failed because the user hit the hourly or
  /// daily hazard limit (see supabase/025_hazard_rate_limit.sql).
  static bool lastReportRateLimited = false;

  static Future<HazardReport?> report(HazardReport hazard, {String? activityId}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    lastReportRateLimited = false;

    try {
      final inserted = await _supabase
          .from('hazards')
          .insert(hazard.toInsertMap(userId: user.id, activityId: activityId))
          .select()
          .single();

      return hazard.copyWith(id: inserted['id'] as String);
    } catch (e) {
      lastReportRateLimited = e.toString().contains('hazard_rate_limit');
      return null;
    }
  }

  // ---------------------------------------------------------------- photos
  static const maxPhotos = 5;
  static const _photoBucket = 'hazard-photos';

  /// Uploads [files] as photos of [hazardId] (stored under the user's folder, then the hazard's) and
  /// returns how many were saved. Stops quietly at the 5-photo limit.
  static Future<int> uploadPhotos(String hazardId, List<File> files) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return 0;
    var saved = 0;
    for (final file in files) {
      try {
        final path = '${user.id}/$hazardId/${const Uuid().v4()}.jpg';
        await _supabase.storage.from(_photoBucket).upload(path, file, fileOptions: const FileOptions(contentType: 'image/jpeg'));
        await _supabase.from('hazard_photos').insert({'hazard_id': hazardId, 'user_id': user.id, 'path': path});
        saved++;
      } catch (e) {
        // ignore: avoid_print
        print('HazardService.uploadPhotos failed: $e');
        if (e.toString().contains('at most 5')) break;
      }
    }
    return saved;
  }

  /// Short-lived viewing links for a hazard's photos (empty if none).
  static Future<List<String>> photoUrls(String hazardId) async {
    try {
      final rows = await _supabase.from('hazard_photos').select('path').eq('hazard_id', hazardId).order('created_at');
      final paths = (rows as List).map((r) => (r as Map<String, dynamic>)['path'] as String).toList();
      if (paths.isEmpty) return [];
      final urls = <String>[];
      for (final path in paths) {
        try {
          urls.add(await _supabase.storage.from(_photoBucket).createSignedUrl(path, 3600));
        } catch (_) {}
      }
      return urls;
    } catch (_) {
      return [];
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