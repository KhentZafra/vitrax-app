import 'package:latlong2/latlong.dart';

import 'activity.dart' show GpsPoint;

/// What a challenge's target is measured in. [route] is a different
/// kind of challenge entirely — not "hit this number," but "retrace
/// this specific recorded route and post the fastest time" (see the
/// route-specific fields on Challenge below). It deliberately has no
/// meaningful unitLabel/target of its own — targetValue is repurposed
/// to hold the route's distance for display, never shown as a "goal."
enum ChallengeType { distance, activityCount, duration, route }

extension ChallengeTypeX on ChallengeType {
  /// Used both as the unit shown in "Target (kilometers)" and, in
  /// CreateChallengeScreen, capitalized as the chip label for picking
  /// the goal type itself.
  String get unitLabel {
    switch (this) {
      case ChallengeType.distance:
        return 'kilometers';
      case ChallengeType.activityCount:
        return 'activities';
      case ChallengeType.duration:
        return 'minutes';
      case ChallengeType.route:
        return 'km'; // only used for the route's distance display, never as a goal unit
    }
  }

  String get value {
    switch (this) {
      case ChallengeType.distance:
        return 'distance';
      case ChallengeType.activityCount:
        return 'activity_count';
      case ChallengeType.duration:
        return 'duration';
      case ChallengeType.route:
        return 'route';
    }
  }

  static ChallengeType fromString(String value) {
    return ChallengeType.values.firstWhere((t) => t.value == value, orElse: () => ChallengeType.distance);
  }
}

/// Which activities count toward a challenge's progress.
enum ChallengeActivityFilter { any, run, ride }

extension ChallengeActivityFilterX on ChallengeActivityFilter {
  String get label {
    switch (this) {
      case ChallengeActivityFilter.any:
        return 'Any';
      case ChallengeActivityFilter.run:
        return 'Running';
      case ChallengeActivityFilter.ride:
        return 'Cycling';
    }
  }

  String get value => name;

  static ChallengeActivityFilter fromString(String value) {
    return ChallengeActivityFilter.values.firstWhere((f) => f.value == value, orElse: () => ChallengeActivityFilter.any);
  }
}

/// A community challenge: a measurable goal (distance, activity count,
/// or duration) over a date range, optionally restricted to one
/// activity type, that anyone can join.
///
/// Progress toward the goal is NOT stored — it's computed on demand from
/// each user's own already-loaded ActivityProvider data (see
/// ChallengeDetailScreen), so there's no separate counter that can drift
/// out of sync with the real activities table, and no need for a new RLS
/// policy exposing other users' unshared activities. The social/
/// completion element is lighter-weight: `challenge_participants.
/// completed_at` (set once a participant hits their goal) is visible to
/// everyone, so a challenge shows who's finished without needing to
/// expose or aggregate anyone's exact distance/time numbers.
///
/// [prizeAmount] is the one exception to "nothing needs cross-user
/// comparison" — if a challenge has a cash prize, determining the WINNER
/// (highest qualifying performance, not just "did you finish") genuinely
/// requires comparing participants' shared activities against each
/// other. See ChallengeService.determineWinner.
class Challenge {
  final String id;
  final String creatorId;
  final String creatorName;
  final String title;
  final String? description;
  final ChallengeType type;
  final double targetValue;
  final ChallengeActivityFilter activityFilter;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime createdAt;
  final double? prizeAmount; // null = no cash prize, just a regular challenge
  final int participantCount;
  final bool joinedByMe;
  final DateTime? myCompletedAt;

  // Route-challenge only (type == ChallengeType.route) — null for every
  // other challenge type. The creator's own recorded activity becomes
  // the target: routePoints is that activity's actual GPS path, and
  // baselineDurationSeconds is the time other participants have to
  // beat. See ChallengeService.submitRouteAttempt for how an attempt
  // gets validated against startPoint/finishPoint below.
  final List<GpsPoint>? routePoints;
  final int? baselineDurationSeconds;

  Challenge({
    required this.id,
    required this.creatorId,
    required this.creatorName,
    required this.title,
    this.description,
    required this.type,
    required this.targetValue,
    required this.activityFilter,
    required this.startDate,
    required this.endDate,
    required this.createdAt,
    this.prizeAmount,
    this.participantCount = 0,
    this.joinedByMe = false,
    this.myCompletedAt,
    this.routePoints,
    this.baselineDurationSeconds,
  });

  bool get hasEnded => DateTime.now().isAfter(endDate);
  bool get hasStarted => DateTime.now().isAfter(startDate) || DateTime.now().isAtSameMomentAs(startDate);
  bool get isActive => hasStarted && !hasEnded;
  bool get iCompletedIt => myCompletedAt != null;
  bool get hasPrize => prizeAmount != null && prizeAmount! > 0;
  bool get isRouteChallenge => type == ChallengeType.route;

  LatLng? get startPoint => (routePoints != null && routePoints!.isNotEmpty) ? LatLng(routePoints!.first.lat, routePoints!.first.lng) : null;
  LatLng? get finishPoint => (routePoints != null && routePoints!.isNotEmpty) ? LatLng(routePoints!.last.lat, routePoints!.last.lng) : null;
  Duration? get baselineDuration => baselineDurationSeconds != null ? Duration(seconds: baselineDurationSeconds!) : null;

  factory Challenge.fromMap(Map<String, dynamic> map, {int participantCount = 0, bool joinedByMe = false, DateTime? myCompletedAt}) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    final first = profile?['first_name'] as String? ?? '';
    final last = profile?['last_name'] as String? ?? '';
    final name = ('$first $last').trim();

    return Challenge(
      id: map['id'] as String,
      creatorId: map['creator_id'] as String,
      creatorName: name.isEmpty ? 'A Vitrax user' : name,
      title: map['title'] as String,
      description: map['description'] as String?,
      type: ChallengeTypeX.fromString(map['type'] as String),
      targetValue: (map['target_value'] as num).toDouble(),
      activityFilter: ChallengeActivityFilterX.fromString(map['activity_filter'] as String? ?? 'any'),
      // Stored in UTC; shown and compared in the phone's local time.
      startDate: DateTime.parse(map['start_date'] as String).toLocal(),
      endDate: DateTime.parse(map['end_date'] as String).toLocal(),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      prizeAmount: map['prize_amount'] != null ? (map['prize_amount'] as num).toDouble() : null,
      participantCount: participantCount,
      joinedByMe: joinedByMe,
      myCompletedAt: myCompletedAt,
      routePoints: (map['route'] as List<dynamic>?)?.map((p) => GpsPoint.fromJson(p as Map<String, dynamic>)).toList(),
      baselineDurationSeconds: map['baseline_duration_seconds'] as int?,
    );
  }

  Map<String, dynamic> toInsertMap({required String creatorId}) {
    return {
      'creator_id': creatorId,
      'title': title,
      'description': description,
      'type': type.value,
      'target_value': targetValue,
      'activity_filter': activityFilter.value,
      'start_date': startDate.toUtc().toIso8601String(),
      'end_date': endDate.toUtc().toIso8601String(),
      'prize_amount': prizeAmount,
      'route': routePoints?.map((p) => p.toJson()).toList(),
      'baseline_duration_seconds': baselineDurationSeconds,
    };
  }
}

/// The determined winner of a challenge's cash prize — only meaningful
/// once the challenge has ended, since the "who's leading" position can
/// still change up until the deadline.
class ChallengeWinner {
  final String userId;
  final String name;
  final String? avatarUrl;
  final double progress;
  final String? gcashQrUrl;
  final bool prizePaid;

  /// Storage path of the creator's proof-of-payment screenshot (private).
  final String? proofPath;

  /// When the creator marked the prize paid, and when the winner confirmed.
  final DateTime? markedPaidAt;
  final DateTime? confirmedAt;

  /// The winner reported "I did not receive it" and an admin has not ruled yet.
  final bool disputed;

  ChallengeWinner({
    required this.userId,
    required this.name,
    this.avatarUrl,
    required this.progress,
    this.gcashQrUrl,
    required this.prizePaid,
    this.proofPath,
    this.markedPaidAt,
    this.confirmedAt,
    this.disputed = false,
  });

  /// A paid prize counts as confirmed when the winner confirmed it, or when
  /// 7 days passed with no dispute.
  bool get confirmed =>
      prizePaid &&
      !disputed &&
      (confirmedAt != null || (markedPaidAt != null && DateTime.now().difference(markedPaidAt!).inDays >= 7));

  /// Marked paid by the creator, waiting for the winner to confirm.
  bool get awaitingConfirm => prizePaid && !disputed && !confirmed;
}
