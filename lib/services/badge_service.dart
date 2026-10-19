import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/achievement.dart';

/// Key the root MaterialApp uses, so a badge celebration can pop up from
/// anywhere (after a ride is saved, a challenge is completed, etc.) without
/// the caller having to hand over a BuildContext.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// One badge on the ladder: how it's named and where each tier starts.
class BadgeDef {
  final String key;
  final String title;
  final String description;
  final String unit; // "rides", "km", ...
  final IconData icon;
  final List<int> thresholds; // bronze, silver, gold, platinum, diamond, elite

  const BadgeDef({
    required this.key,
    required this.title,
    required this.description,
    required this.unit,
    required this.icon,
    required this.thresholds,
  });
}

/// Badges are awarded by the SERVER (`evaluate_my_badges()` in
/// 020_badges.sql). This class only asks "anything new?" and shows the
/// celebration; thresholds here must match the ones in that SQL function.
class BadgeService {
  static final _supabase = Supabase.instance.client;

  static const defs = <BadgeDef>[
    BadgeDef(
      key: 'first_steps',
      title: 'First Steps',
      description: 'Complete real rides and runs (at least 200 m each).',
      unit: 'activities',
      icon: Icons.directions_run,
      thresholds: [1, 10, 25, 50, 100, 250],
    ),
    BadgeDef(
      key: 'distance',
      title: 'Distance Club',
      description: 'Add up the total kilometres you have covered.',
      unit: 'km',
      icon: Icons.route,
      thresholds: [10, 50, 150, 300, 600, 1000],
    ),
    BadgeDef(
      key: 'challenger',
      title: 'Challenger',
      description: 'Finish community challenges.',
      unit: 'challenges',
      icon: Icons.emoji_events_outlined,
      thresholds: [1, 3, 5, 10, 20, 40],
    ),
    BadgeDef(
      key: 'streak',
      title: 'On a Roll',
      description: 'Be active on consecutive days. Your longest streak counts.',
      unit: 'days',
      icon: Icons.local_fire_department_outlined,
      thresholds: [3, 7, 14, 30, 60, 100],
    ),
    BadgeDef(
      key: 'route_pioneer',
      title: 'Route Pioneer',
      description: 'Hazard reports you filed that other riders and runners confirmed are real.',
      unit: 'confirmed reports',
      icon: Icons.flag_outlined,
      thresholds: [1, 5, 15, 30, 60, 100],
    ),
    BadgeDef(
      key: 'safety_warden',
      title: 'Safety Warden',
      description: 'Help confirm that a hazard was cleared, keeping the community map trustworthy.',
      unit: 'confirmations',
      icon: Icons.shield_outlined,
      thresholds: [1, 5, 15, 30, 60, 100],
    ),
    BadgeDef(
      key: 'early_bird',
      title: 'Early Bird',
      description: 'Start real activities before 7 AM.',
      unit: 'early activities',
      icon: Icons.wb_twilight,
      thresholds: [1, 5, 15, 30, 60, 100],
    ),
    BadgeDef(
      key: 'endurance',
      title: 'Endurance',
      description: 'Go the distance: your longest single activity counts.',
      unit: 'km in one go',
      icon: Icons.terrain,
      thresholds: [10, 25, 50, 100, 150, 200],
    ),
    BadgeDef(
      key: 'hazard_spotter',
      title: 'Hazard Spotter',
      description: 'Report hazards so others can avoid them.',
      unit: 'reports',
      icon: Icons.warning_amber_rounded,
      thresholds: [1, 10, 25, 50, 100, 250],
    ),
    BadgeDef(
      key: 'trail_sharer',
      title: 'Trail Sharer',
      description: 'Share your tracks with the community.',
      unit: 'shared tracks',
      icon: Icons.share_outlined,
      thresholds: [1, 5, 15, 30, 60, 100],
    ),
    BadgeDef(
      key: 'community_voice',
      title: 'Community Voice',
      description: 'Post and comment in the community feed.',
      unit: 'posts and comments',
      icon: Icons.forum_outlined,
      thresholds: [1, 10, 25, 50, 100, 250],
    ),
  ];

  static BadgeDef? defFor(String key) {
    for (final d in defs) {
      if (d.key == key) return d;
    }
    return null;
  }

  static BadgeTier tierFromName(String? name) {
    switch (name) {
      case 'bronze':
        return BadgeTier.bronze;
      case 'silver':
        return BadgeTier.silver;
      case 'gold':
        return BadgeTier.gold;
      case 'platinum':
        return BadgeTier.platinum;
      case 'diamond':
        return BadgeTier.diamond;
      case 'elite':
        return BadgeTier.elite;
    }
    return BadgeTier.none;
  }

  /// Current numbers behind every badge (from the server). {} on failure.
  static Future<Map<String, int>> fetchStats() async {
    try {
      final res = await _supabase.rpc('my_badge_stats');
      final map = Map<String, dynamic>.from(res as Map);
      return map.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (e) {
      // ignore: avoid_print
      print('BadgeService.fetchStats failed: $e');
      return {};
    }
  }

  /// All badges as profile cards, using [stats] from [fetchStats].
  static List<AchievementBadge> buildBadges(Map<String, int> stats) {
    return defs.map((d) {
      final value = stats[d.key] ?? 0;
      var tier = BadgeTier.none;
      const tiers = [BadgeTier.bronze, BadgeTier.silver, BadgeTier.gold, BadgeTier.platinum, BadgeTier.diamond, BadgeTier.elite];
      int? next = d.thresholds.first;
      for (var i = 0; i < d.thresholds.length; i++) {
        if (value >= d.thresholds[i]) {
          tier = tiers[i];
          next = i + 1 < d.thresholds.length ? d.thresholds[i + 1] : null;
        }
      }
      return AchievementBadge(
        title: d.title,
        description: d.description,
        icon: d.icon,
        tier: tier,
        currentValue: value,
        nextThreshold: next,
      );
    }).toList();
  }

  static bool _checking = false;

  /// Asks the server whether anything new was earned and, if so, celebrates.
  /// Safe to call as often as you like (it never throws and ignores
  /// overlapping calls).
  static Future<void> check() async {
    if (_checking) return;
    if (_supabase.auth.currentUser == null) return;
    _checking = true;
    try {
      final res = await _supabase.rpc('evaluate_my_badges');
      final rows = (res as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return;

      // Only the highest newly-earned tier per badge gets a celebration.
      final best = <String, BadgeTier>{};
      for (final r in rows) {
        final key = r['badge_key'] as String;
        final tier = tierFromName(r['tier'] as String?);
        if (!best.containsKey(key) || tier.index > best[key]!.index) best[key] = tier;
      }
      final earned = best.entries.where((e) => defFor(e.key) != null).toList()
        ..sort((a, b) => b.value.index.compareTo(a.value.index));

      // A brand-new install of this feature can award many at once; show the
      // best three so it stays a nice surprise instead of a wall of popups.
      for (final e in earned.take(3)) {
        await _celebrate(defFor(e.key)!, e.value);
      }
    } catch (e) {
      // ignore: avoid_print
      print('BadgeService.check failed: $e');
    } finally {
      _checking = false;
    }
  }

  static Future<void> _celebrate(BadgeDef def, BadgeTier tier) async {
    // Give the screen that triggered us a moment to settle (e.g. the ride
    // summary), so the popup lands on top of it instead of fighting it.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    // The overlay's context sits BELOW the Navigator, so Navigator.of works.
    final context = rootNavigatorKey.currentState?.overlay?.context;
    if (context == null || !context.mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Badge earned',
      barrierColor: Colors.black.withValues(alpha: .78),
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (context, animation, secondaryAnimation) => _BadgeEarnedDialog(def: def, tier: tier),
      transitionBuilder: (context, anim, secondaryAnimation, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack), child: child),
      ),
    );
  }
}

class _BadgeEarnedDialog extends StatefulWidget {
  final BadgeDef def;
  final BadgeTier tier;
  const _BadgeEarnedDialog({required this.def, required this.tier});

  @override
  State<_BadgeEarnedDialog> createState() => _BadgeEarnedDialogState();
}

class _BadgeEarnedDialogState extends State<_BadgeEarnedDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.tier.color;
    final tierIdx = widget.tier.index - 1; // bronze = 0

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: math.min(MediaQuery.of(context).size.width - 48, 340),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          decoration: BoxDecoration(
            color: const Color(0xff101015),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: color.withValues(alpha: .55), width: 1.4),
            boxShadow: [BoxShadow(color: color.withValues(alpha: .35), blurRadius: 40, spreadRadius: 2)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('BADGE UNLOCKED', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2.4)),
              const SizedBox(height: 20),
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    RotationTransition(
                      turns: _spin,
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(colors: [color.withValues(alpha: 0), color.withValues(alpha: .55), color.withValues(alpha: 0)]),
                        ),
                      ),
                    ),
                    Container(
                      width: 116,
                      height: 116,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [color.withValues(alpha: .38), const Color(0xff141414)]),
                        border: Border.all(color: color, width: 3),
                      ),
                      child: Icon(widget.def.icon, color: color, size: 54),
                    ),
                    Positioned(
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                        child: Text(widget.tier.label.toUpperCase(), style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: .8)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(widget.def.title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                '${widget.def.thresholds[tierIdx.clamp(0, widget.def.thresholds.length - 1)]} ${widget.def.unit} reached',
                style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(widget.def.description, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade400, fontSize: 13, height: 1.4)),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Awesome!', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
