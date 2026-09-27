import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'activity.dart';
import 'hazard_cluster.dart';
import 'hazard_report.dart';
import '../config/hazard_cluster_config.dart';

/// Route safety tier — per the panel's recommended color scheme for
/// route lines (Green = Safe, Orange = Caution, Red = Hazardous), applied
/// here at the route level so it can be shown as a badge and used to
/// filter the Routes screen.
enum RouteSafetyTier { safe, caution, hazardous }

extension RouteSafetyTierX on RouteSafetyTier {
  String get label {
    switch (this) {
      case RouteSafetyTier.safe:
        return 'Safe';
      case RouteSafetyTier.caution:
        return 'Caution';
      case RouteSafetyTier.hazardous:
        return 'Hazardous';
    }
  }

  Color get color {
    switch (this) {
      case RouteSafetyTier.safe:
        return const Color(0xff2ECC71); // green
      case RouteSafetyTier.caution:
        return const Color(0xffFB8C00); // orange
      case RouteSafetyTier.hazardous:
        return const Color(0xffE53935); // red
    }
  }
}

/// Severity weight per hazard type, per the panel's own examples:
/// "historical reports of light construction or heavy traffic" -> Caution,
/// "active road blockages, major potholes, or deep floods" -> Hazardous.
/// A single pothole report doesn't automatically make a route Hazardous —
/// several stacked reports (higher aggregate score) will push it there,
/// which mirrors "duplicate pins on the same spot" being a real signal.
double hazardSeverityWeight(HazardType type) {
  switch (type) {
    case HazardType.pothole:
    case HazardType.roadConstruction:
    case HazardType.heavyTraffic:
      return 1; // Caution-tier examples in the panel doc — heavy traffic
      // grouped with light construction, per the panel's own wording.
    case HazardType.aggressiveDogs:
    case HazardType.flooding:
      return 2;
    case HazardType.accident:
    case HazardType.crime:
      return 3; // Hazardous-tier examples in the panel doc
    case HazardType.noSignal:
      return 0; // Doesn't affect the safety score — poor connectivity
      // isn't the same thing as physical danger. A no-signal route isn't
      // necessarily unsafe, just harder to get help on if something else
      // goes wrong. Still worth reporting/showing on the map, just not
      // counted toward Safe/Caution/Hazardous.
  }
}

/// Recency decay so stale reports stop dominating the score — directly
/// addresses the panel's "a road condition reported six months ago...
/// outdated pins will ruin user trust" concern. This is a lightweight
/// stand-in for the panel's fuller recommendation (upvote/downvote or an
/// auto-expiry timer after 3 "Clear Now" confirmations), which is a
/// separate feature to build next.
double hazardRecencyMultiplier(DateTime reportedAt) {
  final ageDays = DateTime.now().difference(reportedAt).inDays;
  if (ageDays > 180) return 0; // treated as expired
  if (ageDays > 60) return 0.5; // fading relevance
  return 1;
}

/// A community-visible route: someone's shared Activity, who shared it,
/// and any hazard reports linked to that activity that were also shared.
class SharedRoute {
  final Activity activity;
  final String sharerName;
  final List<HazardReport> hazards;

  SharedRoute({required this.activity, required this.sharerName, required this.hazards});

  factory SharedRoute.fromMap(Map<String, dynamic> map, {required List<HazardReport> hazards}) {
    final activity = Activity.fromMap(map);
    final profile = map['profiles'] as Map<String, dynamic>?;
    final first = profile?['first_name'] as String? ?? '';
    final last = profile?['last_name'] as String? ?? '';
    final name = ('$first $last').trim();

    return SharedRoute(
      activity: activity,
      sharerName: name.isEmpty ? 'A Vitrax user' : name,
      hazards: hazards,
    );
  }

  /// Weighted hazard density: sum of (severity x recency x corroboration)
  /// divided by distance, so a short route with one severe report ranks
  /// worse than a long route with the same report diluted across many
  /// kilometers. Distance is floored at 0.5km so very short routes
  /// aren't skewed to extremes by a single report.
  ///
  /// Hazards are clustered first (same duplicate-merging logic as the
  /// map pins) before scoring — otherwise 5 separate reports of the
  /// exact same pothole would count as 5x the danger of one report of
  /// something else entirely, which overstates the actual risk. Multiple
  /// independent reports of the same spot still matter (more witnesses
  /// = more confidence it's real and still there), so each cluster's
  /// contribution scales with log2(count) instead of being ignored or
  /// counted linearly — diminishing returns, not zero and not 1:1.
  double get hazardScore {
    if (hazards.isEmpty) return 0;
    final distanceKm = activity.distanceKm < 0.5 ? 0.5 : activity.distanceKm;

    final clusters = HazardCluster.cluster(hazards, thresholdMeters: HazardClusterConfig.duplicateThresholdMeters);

    final weighted = clusters.fold<double>(0, (sum, cluster) {
      // Most recent report in the cluster determines recency — if
      // someone reported the same pothole again yesterday, it's still
      // clearly there, even if the original report was months old.
      final mostRecent = cluster.reports.map((h) => h.reportedAt).reduce((a, b) => a.isAfter(b) ? a : b);
      // sqrt(count) so corroboration matters but with real diminishing
      // returns: 2 reports -> 1.41x, 4 reports -> 2x, 9 reports -> 3x —
      // each doubling of witnesses only multiplies contribution by ~1.4x,
      // not 2x, so duplicate spam can't dominate the score.
      final corroboration = math.sqrt(cluster.count);
      return sum + hazardSeverityWeight(cluster.type) * hazardRecencyMultiplier(mostRecent) * corroboration;
    });

    return weighted / distanceKm;
  }

  RouteSafetyTier get safetyTier {
    final score = hazardScore;
    if (score <= 0) return RouteSafetyTier.safe;
    if (score < 2) return RouteSafetyTier.caution;
    return RouteSafetyTier.hazardous;
  }
}
