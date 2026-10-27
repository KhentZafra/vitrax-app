import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity.dart';
import '../models/challenge.dart';

/// Which activities a user picked when registering (or in Edit Profile):
/// Cyclist, Runner, or both. Stored in profiles.primary_activity as
/// "Cyclist", "Runner" or "Cyclist,Runner".
class ActivityPreference {
  final bool cyclist;
  final bool runner;
  const ActivityPreference({required this.cyclist, required this.runner});

  static const none = ActivityPreference(cyclist: false, runner: false);

  bool get hasAny => cyclist || runner;

  static ActivityPreference parse(String? raw) {
    final parts = (raw ?? '').split(',').map((e) => e.trim().toLowerCase()).toList();
    return ActivityPreference(cyclist: parts.contains('cyclist'), runner: parts.contains('runner'));
  }

  static String encode({required bool cyclist, required bool runner}) {
    return [if (cyclist) 'Cyclist', if (runner) 'Runner'].join(',');
  }

  /// "Cyclist", "Runner" or "Cyclist & Runner" for display.
  static String label(String? raw) {
    final p = parse(raw);
    if (p.cyclist && p.runner) return 'Cyclist & Runner';
    if (p.cyclist) return 'Cyclist';
    if (p.runner) return 'Runner';
    return raw ?? '';
  }

  /// Does a recorded activity type match what this user said they do?
  bool matchesType(ActivityType t) => (t == ActivityType.ride && cyclist) || (t == ActivityType.run && runner);

  /// Does a challenge's activity filter match? ("Any" is neutral.)
  bool matchesFilter(ChallengeActivityFilter f) =>
      (f == ChallengeActivityFilter.ride && cyclist) || (f == ChallengeActivityFilter.run && runner);

  static Future<ActivityPreference> load() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return none;
      final row = await client.from('profiles').select('primary_activity').eq('id', user.id).maybeSingle();
      return parse(row?['primary_activity'] as String?);
    } catch (_) {
      return none;
    }
  }
}
