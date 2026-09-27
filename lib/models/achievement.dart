import 'package:flutter/material.dart';

/// How far along a badge's single progression ladder the user is.
/// [none] means "not earned yet" and is shown as a locked slot — there's
/// no separate "locked" vs "in progress" state, since any value > 0 has
/// already cleared the bronze threshold.
enum BadgeTier { none, bronze, silver, gold, elite }

extension BadgeTierX on BadgeTier {
  String get label {
    switch (this) {
      case BadgeTier.none:
        return 'Locked';
      case BadgeTier.bronze:
        return 'Bronze';
      case BadgeTier.silver:
        return 'Silver';
      case BadgeTier.gold:
        return 'Gold';
      case BadgeTier.elite:
        return 'Elite';
    }
  }

  Color get color {
    switch (this) {
      case BadgeTier.none:
        return Colors.grey.shade700;
      case BadgeTier.bronze:
        return const Color(0xffCD7F32);
      case BadgeTier.silver:
        return const Color(0xffB0B4BB);
      case BadgeTier.gold:
        return const Color(0xffFFC94A);
      case BadgeTier.elite:
        return const Color(0xffE91E8C);
    }
  }
}

/// One intrinsic, non-cash recognition badge (panel's own examples: "Route
/// Pioneer", "Safety Warden") — a single progression ladder with four
/// tiers, built from a count the app already tracks honestly (see
/// AchievementService), never a separate points system a user could farm.
class AchievementBadge {
  final String title;
  final String description;
  final IconData icon;
  final BadgeTier tier;
  final int currentValue;
  final int? nextThreshold; // null once at Elite — nothing further to chase

  const AchievementBadge({
    required this.title,
    required this.description,
    required this.icon,
    required this.tier,
    required this.currentValue,
    required this.nextThreshold,
  });

  bool get isLocked => tier == BadgeTier.none;
  int? get remainingToNextTier => nextThreshold != null ? nextThreshold! - currentValue : null;
}
