import 'package:flutter_test/flutter_test.dart';
import 'package:vitrax_app/models/achievement.dart';
import 'package:vitrax_app/services/badge_service.dart';

/// Badge ladders. The expected numbers are written out here on purpose
/// (not read from the app) so the test fails if someone changes a
/// threshold in the app without also changing it in 020_badges.sql.
void main() {
  const expected = <String, List<int>>{
    'first_steps': [1, 10, 25, 50, 100, 250],
    'distance': [10, 50, 150, 300, 600, 1000],
    'challenger': [1, 3, 5, 10, 20, 40],
    'streak': [3, 7, 14, 30, 60, 100],
    'route_pioneer': [1, 5, 15, 30, 60, 100],
    'safety_warden': [1, 5, 15, 30, 60, 100],
    'early_bird': [1, 5, 15, 30, 60, 100],
    'endurance': [10, 25, 50, 100, 150, 200],
    'hazard_spotter': [1, 10, 25, 50, 100, 250],
    'trail_sharer': [1, 5, 15, 30, 60, 100],
    'community_voice': [1, 10, 25, 50, 100, 250],
  };
  const tiers = [
    BadgeTier.bronze,
    BadgeTier.silver,
    BadgeTier.gold,
    BadgeTier.platinum,
    BadgeTier.diamond,
    BadgeTier.elite,
  ];

  BadgeTier tierFor(String key, int value) {
    final t = expected[key]!;
    var out = BadgeTier.none;
    for (var i = 0; i < t.length; i++) {
      if (value >= t[i]) out = tiers[i];
    }
    return out;
  }

  test('the app defines exactly the eleven badges, with the agreed thresholds', () {
    expect(BadgeService.defs.map((d) => d.key).toSet(), expected.keys.toSet());
    for (final d in BadgeService.defs) {
      expect(d.thresholds, expected[d.key], reason: d.key);
    }
  });

  test('a user with no activity has every badge locked', () {
    final badges = BadgeService.buildBadges({});
    expect(badges, hasLength(11));
    for (final b in badges) {
      expect(b.tier, BadgeTier.none);
      expect(b.currentValue, 0);
    }
  });

  test('tier changes exactly at each threshold, and one below stays lower', () {
    for (var i = 0; i < BadgeService.defs.length; i++) {
      final d = BadgeService.defs[i];
      final t = expected[d.key]!;
      final probes = <int>{0, 1, 2, 5, 9, 10, 100, 1000};
      for (final x in t) {
        probes.addAll([x - 1, x, x + 1]);
      }
      for (final v in probes.where((v) => v >= 0)) {
        final badge = BadgeService.buildBadges({d.key: v})[i];
        expect(badge.tier, tierFor(d.key, v), reason: '${d.key} at $v');
      }
    }
  });

  test('progress points at the next threshold, and is empty at Elite', () {
    final distanceIndex = BadgeService.defs.indexWhere((d) => d.key == 'distance');
    expect(BadgeService.buildBadges({'distance': 12})[distanceIndex].nextThreshold, 50);
    expect(BadgeService.buildBadges({'distance': 600})[distanceIndex].tier, BadgeTier.diamond);
    expect(BadgeService.buildBadges({'distance': 300})[distanceIndex].tier, BadgeTier.platinum);
    expect(BadgeService.buildBadges({'distance': 1000})[distanceIndex].nextThreshold, isNull);
    expect(BadgeService.buildBadges({'distance': 1000})[distanceIndex].tier, BadgeTier.elite);
  });
}
