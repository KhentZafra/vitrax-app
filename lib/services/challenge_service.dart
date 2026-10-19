import 'badge_service.dart';
import 'dart:io';

import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/activity.dart';
import '../models/challenge.dart';

/// Handles Community Challenges: browsing, creating, joining, leaving,
/// completion, and cash-prize determination/payment via GCash QR.
///
/// Deliberately does NOT compute or store cross-user progress numbers
/// for regular (non-prize) challenges — see the note on Challenge for
/// why. [determineWinner] is the one exception: a cash prize genuinely
/// requires comparing participants' performance against each other, so
/// it queries participants' own SHARED activities (the same "shared =
/// true" visibility the Community Feed already relies on) rather than
/// needing any new RLS policy that would expose unshared activity data.
class ChallengeService {
  /// Fastest average speed accepted as physically possible by bike (70 km/h)
  /// or on foot (45 km/h). Anything above is treated as driving a vehicle.
  static bool isPlausiblePace(ActivityType type, double avgSpeedKmh) {
    final maxKmh = type == ActivityType.ride ? 70.0 : 45.0;
    return avgSpeedKmh <= maxKmh;
  }

  static final _supabase = Supabase.instance.client;
  static const _uuid = Uuid();

  static Future<List<Challenge>> fetchChallenges() async {
    final currentUserId = _supabase.auth.currentUser?.id;

    try {
      final rows = await _supabase
          .from('challenges')
          .select('*, profiles(first_name, last_name, avatar_url)')
          .order('start_date', ascending: false);

      final challengeRows = (rows as List).cast<Map<String, dynamic>>();
      if (challengeRows.isEmpty) return [];

      final ids = challengeRows.map((r) => r['id'] as String).toList();
      final participantRows = await _supabase
          .from('challenge_participants')
          .select('challenge_id, user_id, completed_at')
          .inFilter('challenge_id', ids);

      final counts = <String, int>{};
      final joinedByMe = <String>{};
      final myCompletedAt = <String, DateTime>{};

      for (final row in (participantRows as List).cast<Map<String, dynamic>>()) {
        final challengeId = row['challenge_id'] as String;
        counts[challengeId] = (counts[challengeId] ?? 0) + 1;
        if (row['user_id'] == currentUserId) {
          joinedByMe.add(challengeId);
          if (row['completed_at'] != null) {
            myCompletedAt[challengeId] = DateTime.parse(row['completed_at'] as String).toLocal();
          }
        }
      }

      return challengeRows
          .map((row) => Challenge.fromMap(
                row,
                participantCount: counts[row['id']] ?? 0,
                joinedByMe: joinedByMe.contains(row['id']),
                myCompletedAt: myCompletedAt[row['id']],
              ))
          .toList();
    } catch (e) {
      // ignore: avoid_print
      print('ChallengeService.fetchChallenges failed: $e');
      return [];
    }
  }

  /// Inserts [challenge] and auto-joins its creator. Returns the created
  /// Challenge (with its real id) on success, or null on failure.
  ///
  /// For a route challenge, the creator's own recording IS the baseline
  /// everyone else has to beat — so their participant row is created
  /// with that time already filled in, putting them straight onto the
  /// leaderboard as the time to beat rather than leaving them as an
  /// un-timed participant.
  static Future<Challenge?> createChallenge(Challenge challenge) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final inserted = await _supabase.from('challenges').insert(challenge.toInsertMap(creatorId: user.id)).select('*, profiles(first_name, last_name, avatar_url)').single();

      final participantRow = <String, dynamic>{
        'challenge_id': inserted['id'],
        'user_id': user.id,
      };
      if (challenge.isRouteChallenge && challenge.baselineDurationSeconds != null) {
        participantRow['duration_seconds'] = challenge.baselineDurationSeconds;
        participantRow['completed_at'] = challenge.createdAt.toIso8601String();
      }
      await _supabase.from('challenge_participants').insert(participantRow);

      return Challenge.fromMap(inserted, participantCount: 1, joinedByMe: true);
    } catch (e) {
      // ignore: avoid_print
      print('ChallengeService.createChallenge failed: $e');
      return null;
    }
  }

  static Future<bool> join(String challengeId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    try {
      await _supabase.from('challenge_participants').insert({'challenge_id': challengeId, 'user_id': user.id});
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('ChallengeService.join failed: $e');
      return false;
    }
  }

  static Future<bool> leave(String challengeId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    try {
      await _supabase.from('challenge_participants').delete().eq('challenge_id', challengeId).eq('user_id', user.id);
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('ChallengeService.leave failed: $e');
      return false;
    }
  }

  /// Marks the current user as having completed [challengeId]. Call once
  /// their client-computed progress reaches the target (ChallengeDetailScreen
  /// decides when — this just records it).
  static Future<bool> markCompleted(String challengeId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    try {
      await _supabase
          .from('challenge_participants')
          .update({'completed_at': DateTime.now().toUtc().toIso8601String()})
          .eq('challenge_id', challengeId)
          .eq('user_id', user.id);
      BadgeService.check(); // challenge finished - any badge earned?
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('ChallengeService.markCompleted failed: $e');
      return false;
    }
  }

  /// Pushes the current user's own client-computed progress value for
  /// [challengeId] up to Supabase, so other participants can see it on
  /// the standings — without exposing their raw activities to anyone
  /// else. Only this one aggregate number leaves the device, computed
  /// the same way ChallengeDetailScreen._myProgress already computes it
  /// from ActivityProvider's already-loaded (and already theirs-only)
  /// data. Safe to call every time the detail screen loads — it's just
  /// an UPDATE on the participant row that already exists from join().
  static Future<void> updateProgress(String challengeId, double progressValue) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      await _supabase
          .from('challenge_participants')
          .update({'progress_value': progressValue})
          .eq('challenge_id', challengeId)
          .eq('user_id', user.id);
    } catch (e) {
      // ignore: avoid_print
      print('ChallengeService.updateProgress failed: $e');
    }
  }

  /// Standings for every joined participant of [challengeId] — not just
  /// the ones who've finished. Sorting is the caller's job (see
  /// ChallengeDetailScreen): finishers first by completed_at ascending,
  /// then everyone still in progress by progressValue descending — the
  /// service just returns the raw rows since it doesn't know the
  /// challenge's targetValue for formatting.
  ///
  /// This is the regular-challenge ranking (goal progress). It's
  /// separate from cash-prize winner determination — see
  /// [determineWinner] — which compares SHARED activities specifically
  /// because a cash prize needs a server-verifiable, cross-user
  /// comparison rather than each participant's own self-reported
  /// progress number.
  static Future<List<ChallengeStanding>> fetchStandings(String challengeId) async {
    try {
      final rows = await _supabase
          .from('challenge_participants')
          .select('user_id, completed_at, progress_value, profiles(first_name, last_name, avatar_url)')
          .eq('challenge_id', challengeId);

      return (rows as List).cast<Map<String, dynamic>>().map((row) {
        final profile = row['profiles'] as Map<String, dynamic>?;
        final first = profile?['first_name'] as String? ?? '';
        final last = profile?['last_name'] as String? ?? '';
        final name = ('$first $last').trim();
        final completedAtRaw = row['completed_at'] as String?;
        return ChallengeStanding(
          userId: row['user_id'] as String,
          name: name.isEmpty ? 'A Vitrax user' : name,
          avatarUrl: profile?['avatar_url'] as String?,
          completedAt: completedAtRaw != null ? DateTime.parse(completedAtRaw).toLocal() : null,
          progressValue: (row['progress_value'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList();
    } catch (e) {
      // ignore: avoid_print
      print('ChallengeService.fetchStandings failed: $e');
      return [];
    }
  }

  /// Names of everyone who has completed [challengeId], most recent
  /// first — the lightweight "social proof" element in place of a full
  /// numeric leaderboard for regular (non-prize) challenges.
  static Future<List<String>> fetchCompletedNames(String challengeId) async {
    try {
      final rows = await _supabase
          .from('challenge_participants')
          .select('completed_at, profiles(first_name, last_name, avatar_url)')
          .eq('challenge_id', challengeId)
          .not('completed_at', 'is', null)
          .order('completed_at', ascending: false);

      return (rows as List).cast<Map<String, dynamic>>().map((row) {
        final profile = row['profiles'] as Map<String, dynamic>?;
        final first = profile?['first_name'] as String? ?? '';
        final last = profile?['last_name'] as String? ?? '';
        final name = ('$first $last').trim();
        return name.isEmpty ? 'A Vitrax user' : name;
      }).toList();
    } catch (e) {
      // ignore: avoid_print
      print('ChallengeService.fetchCompletedNames failed: $e');
      return [];
    }
  }

  // ---------------- Cash prize (GCash) ----------------

  /// Uploads the current user's GCash receive-QR for [challengeId] and
  /// saves its URL on their participant row. Call this when a user finds
  /// out they've won, so the creator has somewhere to pay them.
  static Future<String?> uploadMyGcashQr({required String challengeId, required File qrImage}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final path = '${user.id}/$challengeId.jpg';
      await _supabase.storage.from('gcash-qr-codes').upload(
            path,
            qrImage,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      final url = _supabase.storage.from('gcash-qr-codes').getPublicUrl(path);

      await _supabase.from('challenge_participants').update({'gcash_qr_url': url}).eq('challenge_id', challengeId).eq('user_id', user.id);

      return url;
    } catch (e) {
      // ignore: avoid_print
      print('ChallengeService.uploadMyGcashQr failed: $e');
      return null;
    }
  }

  /// Determines the winner of [challenge]'s cash prize. For a regular
  /// (goal-based) challenge: among participants whose SHARED activities
  /// meet or exceed the target, whoever has the single highest total.
  /// For a route challenge, see [_determineRouteWinner] — "highest
  /// total" doesn't apply there, it's "fastest valid time" instead.
  /// Only meaningful once the challenge has ended — returns null for an
  /// active/upcoming challenge, or if nobody qualified.
  static Future<ChallengeWinner?> determineWinner(Challenge challenge) async {
    if (!challenge.hasEnded) return null;
    if (challenge.isRouteChallenge) return _determineRouteWinner(challenge);

    try {
      final participantRows = await _supabase
          .from('challenge_participants')
          .select('user_id, gcash_qr_url, profiles(first_name, last_name, avatar_url)')
          .eq('challenge_id', challenge.id);

      final participants = (participantRows as List).cast<Map<String, dynamic>>();
      if (participants.isEmpty) return null;

      final participantIds = participants.map((p) => p['user_id'] as String).toList();

      var query = _supabase
          .from('activities')
          .select('user_id, distance_km, duration_seconds, type, started_at')
          .eq('shared', true)
          .inFilter('user_id', participantIds)
          .gte('started_at', challenge.startDate.toIso8601String())
          .lte('started_at', challenge.endDate.add(const Duration(days: 1)).toIso8601String());

      if (challenge.activityFilter != ChallengeActivityFilter.any) {
        query = query.eq('type', challenge.activityFilter == ChallengeActivityFilter.run ? 'run' : 'ride');
      }

      final activityRows = (await query as List).cast<Map<String, dynamic>>();

      // Aggregate per user, matching the challenge's goal type — same
      // three metrics ChallengeDetailScreen computes client-side for
      // personal progress, just now summed per participant instead of
      // just for "me." Route challenges never reach this switch (see
      // the early return above), so it only needs to cover the three
      // goal-based types.
      final progressByUser = <String, double>{};
      final countByUser = <String, int>{};
      for (final row in activityRows) {
        final userId = row['user_id'] as String;
        countByUser[userId] = (countByUser[userId] ?? 0) + 1;
        switch (challenge.type) {
          case ChallengeType.distance:
            progressByUser[userId] = (progressByUser[userId] ?? 0) + (row['distance_km'] as num).toDouble();
            break;
          case ChallengeType.duration:
            progressByUser[userId] = (progressByUser[userId] ?? 0) + (row['duration_seconds'] as num).toDouble() / 60;
            break;
          case ChallengeType.activityCount:
            progressByUser[userId] = countByUser[userId]!.toDouble();
            break;
          case ChallengeType.route:
            break; // unreachable — route challenges return early above
        }
      }

      final paymentRows = await _supabase.from('challenge_prize_payments').select('winner_user_id').eq('challenge_id', challenge.id);
      final paidUserIds = (paymentRows as List).cast<Map<String, dynamic>>().map((r) => r['winner_user_id'] as String).toSet();

      ChallengeWinner? best;
      for (final p in participants) {
        final userId = p['user_id'] as String;
        final progress = progressByUser[userId] ?? 0;
        if (progress < challenge.targetValue) continue; // must actually meet the goal

        if (best == null || progress > best.progress) {
          final profile = p['profiles'] as Map<String, dynamic>?;
          final first = profile?['first_name'] as String? ?? '';
          final last = profile?['last_name'] as String? ?? '';
          final name = ('$first $last').trim();

          best = ChallengeWinner(
            userId: userId,
            name: name.isEmpty ? 'A Vitrax user' : name,
            avatarUrl: profile?['avatar_url'] as String?,
            progress: progress,
            gcashQrUrl: p['gcash_qr_url'] as String?,
            prizePaid: paidUserIds.contains(userId),
          );
        }
      }

      return best;
    } catch (e) {
      // ignore: avoid_print
      print('ChallengeService.determineWinner failed: $e');
      return null;
    }
  }

  /// Route-challenge winner: fastest recorded time among participants
  /// whose attempt was on a SHARED activity — the same "only shared
  /// activities count" policy the goal-based path uses above, checked
  /// here via the activity_id submitRouteAttempt already linked to each
  /// participant's best time.
  ///
  /// NOTE: ChallengeWinner.progress holds raw SECONDS for a route
  /// winner, not a goal total — callers must check
  /// challenge.isRouteChallenge before formatting it (see
  /// ChallengeDetailScreen, which formats it as a duration instead of
  /// "X kilometers" for this case).
  static Future<ChallengeWinner?> _determineRouteWinner(Challenge challenge) async {
    try {
      final participantRows = await _supabase
          .from('challenge_participants')
          .select('user_id, duration_seconds, activity_id, gcash_qr_url, profiles(first_name, last_name, avatar_url)')
          .eq('challenge_id', challenge.id)
          .not('duration_seconds', 'is', null);

      final participants = (participantRows as List).cast<Map<String, dynamic>>();
      if (participants.isEmpty) return null;

      final activityIds = participants.map((p) => p['activity_id'] as String?).whereType<String>().toList();
      if (activityIds.isEmpty) return null;

      final sharedRows = await _supabase.from('activities').select('id').eq('shared', true).inFilter('id', activityIds);
      final sharedIds = (sharedRows as List).cast<Map<String, dynamic>>().map((r) => r['id'] as String).toSet();

      final paymentRows = await _supabase.from('challenge_prize_payments').select('winner_user_id').eq('challenge_id', challenge.id);
      final paidUserIds = (paymentRows as List).cast<Map<String, dynamic>>().map((r) => r['winner_user_id'] as String).toSet();

      ChallengeWinner? best;
      int? bestSeconds;
      for (final p in participants) {
        final activityId = p['activity_id'] as String?;
        if (activityId == null || !sharedIds.contains(activityId)) continue; // must be shared to qualify

        final seconds = p['duration_seconds'] as int;
        if (bestSeconds == null || seconds < bestSeconds) {
          final userId = p['user_id'] as String;
          final profile = p['profiles'] as Map<String, dynamic>?;
          final first = profile?['first_name'] as String? ?? '';
          final last = profile?['last_name'] as String? ?? '';
          final name = ('$first $last').trim();

          bestSeconds = seconds;
          best = ChallengeWinner(
            userId: userId,
            name: name.isEmpty ? 'A Vitrax user' : name,
            avatarUrl: profile?['avatar_url'] as String?,
            progress: seconds.toDouble(),
            gcashQrUrl: p['gcash_qr_url'] as String?,
            prizePaid: paidUserIds.contains(userId),
          );
        }
      }

      return best;
    } catch (e) {
      // ignore: avoid_print
      print('ChallengeService._determineRouteWinner failed: $e');
      return null;
    }
  }

  /// Records that the creator has sent the prize money. RLS enforces
  /// that only the challenge's actual creator can call this
  /// successfully (see 016_challenge_prizes.sql) — the app doesn't need
  /// to duplicate that check client-side, but calling as a non-creator
  /// will simply fail.
  static Future<bool> markPrizePaid({required String challengeId, required String winnerUserId}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    try {
      await _supabase.from('challenge_prize_payments').insert({
        'challenge_id': challengeId,
        'winner_user_id': winnerUserId,
        'marked_paid_by': user.id,
      });
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('ChallengeService.markPrizePaid failed: $e');
      return false;
    }
  }

  // How close (meters) an attempt's start/finish must land to the
  // challenge's own start/finish to count as a real run of the same
  // route — GPS is never pixel-perfect, so this can't be zero, but it
  // also shouldn't be so loose that an unrelated nearby street passes
  // as "the same route."
  static const _proximityToleranceMeters = 60.0;

  /// Validates [activity] as an attempt on [challenge]'s route, then
  /// records it if it's the participant's best (lowest) valid time so
  /// far. Attempts a best-effort join first (a duplicate-row error from
  /// already being joined is harmless and ignored) so this works
  /// whether or not the user explicitly joined beforehand.
  static Future<ChallengeAttemptResult> submitRouteAttempt(Challenge challenge, Activity activity) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return const ChallengeAttemptResult(ChallengeAttemptStatus.error);

    final challengeStart = challenge.startPoint;
    final challengeFinish = challenge.finishPoint;
    if (challengeStart == null || challengeFinish == null || activity.route.isEmpty) {
      return const ChallengeAttemptResult(ChallengeAttemptStatus.error);
    }

    final attemptStart = activity.route.first;
    final attemptFinish = activity.route.last;

    final startDistance = Geolocator.distanceBetween(challengeStart.latitude, challengeStart.longitude, attemptStart.lat, attemptStart.lng);
    if (startDistance > _proximityToleranceMeters) {
      return const ChallengeAttemptResult(ChallengeAttemptStatus.tooFarFromStart);
    }

    final finishDistance = Geolocator.distanceBetween(challengeFinish.latitude, challengeFinish.longitude, attemptFinish.lat, attemptFinish.lng);
    if (finishDistance > _proximityToleranceMeters) {
      return const ChallengeAttemptResult(ChallengeAttemptStatus.tooFarFromFinish);
    }

    // Basic anti-cheat: an "attempt" faster than physically plausible
    // for the activity type (e.g. someone driving the route in a car)
    // is rejected outright. Not foolproof — a determined GPS-spoofer
    // can still get past this — but it catches the obvious case.
    if (!isPlausiblePace(activity.type, activity.avgSpeedKmh)) {
      return const ChallengeAttemptResult(ChallengeAttemptStatus.implausiblePace);
    }

    try {
      // Best-effort join — ignore a duplicate-row failure.
      try {
        await _supabase.from('challenge_participants').insert({'challenge_id': challenge.id, 'user_id': user.id});
      } catch (_) {}

      final existing = await _supabase
          .from('challenge_participants')
          .select('duration_seconds')
          .eq('challenge_id', challenge.id)
          .eq('user_id', user.id)
          .maybeSingle();

      final existingSeconds = existing?['duration_seconds'] as int?;
      final newSeconds = activity.duration.inSeconds;

      if (existingSeconds != null && existingSeconds <= newSeconds) {
        // Already have an equal-or-better time recorded — nothing to
        // update, but this isn't a failure, just not an improvement.
        return ChallengeAttemptResult(ChallengeAttemptStatus.notImproved, duration: Duration(seconds: existingSeconds));
      }

      await _supabase.from('challenge_participants').update({
        'duration_seconds': newSeconds,
        'activity_id': activity.id,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('challenge_id', challenge.id).eq('user_id', user.id);

      return ChallengeAttemptResult(ChallengeAttemptStatus.success, duration: activity.duration);
    } catch (e) {
      // ignore: avoid_print
      print('ChallengeService.submitRouteAttempt failed: $e');
      return const ChallengeAttemptResult(ChallengeAttemptStatus.error);
    }
  }

  /// Time-based leaderboard for a route challenge — fastest valid
  /// attempt first. Only participants with a recorded duration appear
  /// (someone who joined but hasn't attempted it yet has nothing to
  /// rank by).
  static Future<List<ChallengeTimeEntry>> fetchRouteLeaderboard(Challenge challenge) async {
    try {
      final rows = await _supabase
          .from('challenge_participants')
          .select('user_id, duration_seconds, profiles(first_name, last_name, avatar_url)')
          .eq('challenge_id', challenge.id)
          .not('duration_seconds', 'is', null)
          .order('duration_seconds', ascending: true);

      return (rows as List).cast<Map<String, dynamic>>().map((row) {
        final profile = row['profiles'] as Map<String, dynamic>?;
        final first = profile?['first_name'] as String? ?? '';
        final last = profile?['last_name'] as String? ?? '';
        final name = ('$first $last').trim();
        final userId = row['user_id'] as String;
        return ChallengeTimeEntry(
          userId: userId,
          name: name.isEmpty ? 'A Vitrax user' : name,
          avatarUrl: profile?['avatar_url'] as String?,
          duration: Duration(seconds: row['duration_seconds'] as int),
          isCreator: userId == challenge.creatorId,
        );
      }).toList();
    } catch (e) {
      // ignore: avoid_print
      print('ChallengeService.fetchRouteLeaderboard failed: $e');
      return [];
    }
  }
}

/// One row of a regular challenge's standings — who joined, how far
/// along they are, and when (if) they finished. Separate from
/// ChallengeWinner (in challenge.dart), which is specifically the
/// cash-prize winner determined server-side from shared activities.
class ChallengeStanding {
  final String userId;
  final String name;
  final String? avatarUrl;
  final DateTime? completedAt;
  final double progressValue;
  const ChallengeStanding({required this.userId, required this.name, this.avatarUrl, required this.completedAt, required this.progressValue});

  bool get isCompleted => completedAt != null;
}

/// Outcome of trying to submit an activity as an attempt on a route
/// challenge — carries enough detail for the UI to explain exactly why
/// an attempt didn't count, rather than a bare true/false.
enum ChallengeAttemptStatus { success, notImproved, tooFarFromStart, tooFarFromFinish, implausiblePace, error }

class ChallengeAttemptResult {
  final ChallengeAttemptStatus status;
  final Duration? duration;
  const ChallengeAttemptResult(this.status, {this.duration});

  bool get isSuccess => status == ChallengeAttemptStatus.success;
}

/// One row of a route challenge's time-based leaderboard.
class ChallengeTimeEntry {
  final String userId;
  final String name;
  final String? avatarUrl;
  final Duration duration;
  final bool isCreator;
  const ChallengeTimeEntry({required this.userId, required this.name, this.avatarUrl, required this.duration, required this.isCreator});
}
