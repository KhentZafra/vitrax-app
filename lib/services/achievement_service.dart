import 'package:flutter/material.dart';

import '../models/achievement.dart';
import 'community_impact_service.dart';

/// Builds the panel's named achievement badges — "Route Pioneer" and
/// "Safety Warden" — as tiered, intrinsic (non-cash) recognition, per its
/// own advice: "Keep the rewards strictly intrinsic and tier-based."
///
/// Deliberately NOT a separate badges table/backend. Both badges are just
/// a named, tiered view onto numbers CommunityImpactStats already
/// computes — and that service already only counts hazard actions
/// independently corroborated by someone else, which is the panel's own
/// fix for the point-farming risk it flagged. Reusing that here means a
/// badge can't be farmed any more easily than the Community Impact score
/// already can't be.
class AchievementService {
  // One shared four-step ladder for every badge — easy to explain, easy
  // to retune later without touching the badge-building logic itself.
  static const _bronze = 1;
  static const _silver = 5;
  static const _gold = 15;
  static const _elite = 30;

  static BadgeTier _tierFor(int value) {
    if (value >= _elite) return BadgeTier.elite;
    if (value >= _gold) return BadgeTier.gold;
    if (value >= _silver) return BadgeTier.silver;
    if (value >= _bronze) return BadgeTier.bronze;
    return BadgeTier.none;
  }

  static int? _nextThreshold(int value) {
    if (value < _bronze) return _bronze;
    if (value < _silver) return _silver;
    if (value < _gold) return _gold;
    if (value < _elite) return _elite;
    return null; // already Elite — nothing further on this ladder
  }

  /// [stats] is whatever ProfileScreen already loaded from
  /// CommunityImpactService.fetchStats — no extra network call needed.
  static List<AchievementBadge> fromStats(CommunityImpactStats stats) {
    return [
      AchievementBadge(
        title: 'Route Pioneer',
        description: "Awarded for hazard reports you filed that other riders and runners independently confirmed are real — the panel's own example of who deserves recognition first.",
        icon: Icons.flag_outlined,
        tier: _tierFor(stats.hazardsVerified),
        currentValue: stats.hazardsVerified,
        nextThreshold: _nextThreshold(stats.hazardsVerified),
      ),
      AchievementBadge(
        title: 'Safety Warden',
        description: 'Awarded for helping confirm a hazard was actually cleared, keeping the community map trustworthy for everyone behind you.',
        icon: Icons.shield_outlined,
        tier: _tierFor(stats.obstaclesCleared),
        currentValue: stats.obstaclesCleared,
        nextThreshold: _nextThreshold(stats.obstaclesCleared),
      ),
    ];
  }
}
