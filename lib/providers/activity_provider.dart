import 'package:flutter/foundation.dart';
import '../services/badge_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/activity.dart';
import '../services/connectivity_service.dart';
import '../services/location_service.dart';
import '../services/offline_activity_queue.dart';

/// Single source of truth for a user's activities, backed by Supabase —
/// with an offline-first fallback for recording without connectivity.
///
/// - [loadActivities] pulls the current user's rows, then attempts to
///   sync anything queued locally from a previous offline session.
/// - [saveActivity] tries a direct Supabase insert first. If that fails
///   for any reason (no connection, a transient error, Supabase itself
///   being paused) the recording is queued locally via
///   [OfflineActivityQueue] instead of being lost — this is what makes
///   the app usable in Bohol's unstable provincial connectivity.
/// - [syncPending] is called automatically on load and whenever
///   connectivity comes back online (see main.dart wiring), and pushes
///   every locally-queued activity to Supabase, replacing each local
///   placeholder with its real synced row on success.
class ActivityProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;

  List<Activity> _activities = [];
  bool isLoading = false;
  String? errorMessage;

  int pendingSyncCount = 0;
  bool isSyncing = false;

  List<Activity> get allActivities => List.unmodifiable(_activities);

  Future<void> loadActivities() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final rows = await _supabase
          .from('activities')
          .select()
          .eq('user_id', user.id)
          .order('started_at', ascending: false);

      final synced = (rows as List<dynamic>).map((row) => Activity.fromMap(row as Map<String, dynamic>)).toList();
      final pending = await OfflineActivityQueue.loadAll();
      pendingSyncCount = pending.length;

      // Pending-local activities show up in lists immediately (sorted in
      // with everything else by start time) even before they've synced.
      _activities = [...synced, ...pending]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    } catch (e) {
      errorMessage = 'Unable to load activities.';
    } finally {
      isLoading = false;
      notifyListeners();
    }

    // Fire-and-forget: try to clear the queue now that we're loading
    // (implies the app is at least attempting a network round-trip).
    syncPending();
  }

  /// Inserts a finished recording and refreshes local state. Returns the
  /// saved Activity on success (real Supabase id if synced immediately,
  /// or a `local_...` id with `pendingSync: true` if it had to be queued)
  /// — this method effectively never "fails" from the recording screen's
  /// point of view; a GPS session's data is never silently discarded.
  /// Check [errorMessage] only if you specifically need to know whether
  /// the last save synced immediately or was queued.
  Future<Activity?> saveActivity({
    required ActivityType type,
    String? subtype,
    required double distanceKm,
    required Duration duration,
    required DateTime startedAt,
    List<GpsPoint> route = const [],
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      errorMessage = 'You must be signed in to save an activity.';
      notifyListeners();
      return null;
    }

    // Reverse-geocode the route's starting point into a short place name
    // (e.g. "Panglao, Bohol") for display on route cards. Best-effort —
    // reverseGeocode() already swallows its own errors and returns null
    // on any failure (no connectivity, no result, etc.), so this never
    // blocks or fails the save itself; a missing location is fine.
    String? location;
    if (route.isNotEmpty) {
      location = await LocationService.reverseGeocode(route.first.lat, route.first.lng);
    }

    final activity = Activity(
      userId: user.id,
      type: type,
      subtype: subtype,
      distanceKm: distanceKm,
      duration: duration,
      startedAt: startedAt,
      route: route,
      location: location,
    );

    try {
      final inserted = await _supabase.from('activities').insert(activity.toInsertMap()).select().single();

      final saved = Activity.fromMap(inserted);
      _activities = [saved, ..._activities];
      errorMessage = null;
      notifyListeners();
      BadgeService.check(); // did this ride earn a badge?
      return saved;
    } catch (e) {
      // Network/Supabase problem — queue locally instead of losing the
      // recording. This is the offline-first fallback: the GPS data
      // itself was already captured by RecordScreen regardless of
      // connectivity, so this is purely about not losing it on save.
      debugPrint('saveActivity: direct insert failed ($e), queueing locally');
      final queued = await OfflineActivityQueue.enqueue(activity);
      _activities = [queued, ..._activities];
      pendingSyncCount++;
      errorMessage = 'Saved locally, Will sync when you\'re back online.';
      notifyListeners();
      return queued;
    }
  }

  /// Pushes every locally-queued activity to Supabase. Safe to call
  /// often (app start, connectivity restored, pull-to-refresh) — each
  /// activity is only removed from the local queue after a confirmed
  /// successful insert, so a failure or interruption just leaves it
  /// queued for the next attempt.
  Future<void> syncPending() async {
    if (isSyncing) return; // avoid overlapping sync runs
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final pending = await OfflineActivityQueue.loadAll();
    if (pending.isEmpty) {
      pendingSyncCount = 0;
      return;
    }

    isSyncing = true;
    notifyListeners();

    var syncedCount = 0;
    for (final local in pending) {
      try {
        final inserted = await _supabase.from('activities').insert(local.toInsertMap()).select().single();
        final saved = Activity.fromMap(inserted);

        await OfflineActivityQueue.remove(local.id!);

        _activities = _activities.map((a) => a.id == local.id ? saved : a).toList();
        syncedCount++;
      } catch (e) {
        debugPrint('syncPending: failed to sync ${local.id}: $e');
        // Leave it queued — will retry on the next syncPending() call.
      }
    }

    pendingSyncCount = (await OfflineActivityQueue.loadAll()).length;
    isSyncing = false;
    notifyListeners();

    if (syncedCount > 0) {
      debugPrint('syncPending: synced $syncedCount activit${syncedCount == 1 ? 'y' : 'ies'}');
    }
  }

  /// Marks a saved activity as shared to the community feed, optionally
  /// with a caption and/or a photo URL (already uploaded via
  /// PhotoUploadService before this is called). Updates both Supabase
  /// and local state so HomeScreen/RoutesScreen/CommunityFeedScreen all
  /// stay in sync.
  ///
  /// Not available for an activity that's still `pendingSync` — there's
  /// no real Supabase row to attach a share to yet. Callers should check
  /// `activity.pendingSync` and disable the Share button until it syncs.
  Future<bool> markActivityShared(String activityId, {String? caption, String? photoUrl}) async {
    if (activityId.startsWith('local_')) {
      errorMessage = 'This activity is still syncing, Try sharing again once it\'s back online.';
      notifyListeners();
      return false;
    }

    try {
      final updates = <String, dynamic>{'shared': true};
      if (caption != null) updates['caption'] = caption;
      if (photoUrl != null) updates['photo_url'] = photoUrl;

      await _supabase.from('activities').update(updates).eq('id', activityId);

      _activities = _activities.map((a) {
        if (a.id != activityId) return a;
        return a.copyWith(shared: true, caption: caption ?? a.caption, photoUrl: photoUrl ?? a.photoUrl);
      }).toList();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('markActivityShared failed: $e');
      return false;
    }
  }

  List<Activity> get thisWeekActivities {
    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    return _activities.where((a) => a.startedAt.isAfter(startOfWeek)).toList();
  }

  double get weeklyDistanceKm => thisWeekActivities.fold(0.0, (sum, a) => sum + a.distanceKm);

  Duration get weeklyTotalTime => thisWeekActivities.fold(Duration.zero, (sum, a) => sum + a.duration);

  String get formattedWeeklyTime {
    final d = weeklyTotalTime;
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }

  List<Activity> recentActivities({int limit = 5}) => _activities.take(limit).toList();

  /// Resolves a possibly-stale activity reference (e.g. one captured by
  /// the completion popup right after saveActivity() returned) to
  /// whatever this provider currently knows about it.
  ///
  /// A locally-queued activity's id changes once it successfully syncs
  /// — the temporary `local_...` id is replaced by the real Supabase id
  /// (see syncPending()) — so a stale reference can't be found by id
  /// alone. `startedAt` stays stable across that transition and,
  /// combined with the user, is effectively unique for one recording,
  /// so it's used as the match key instead. Falls back to the original
  /// reference if nothing matches (e.g. it was somehow removed).
  Activity resolveCurrent(Activity stale) {
    for (final a in _activities) {
      if (a.userId == stale.userId && a.startedAt == stale.startedAt) return a;
    }
    return stale;
  }
}
