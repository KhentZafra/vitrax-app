import 'package:supabase_flutter/supabase_flutter.dart';

enum SafetyTier { newReporter, trustedContributor, safetyGuardian, elite }

extension SafetyTierX on SafetyTier {
  String get label {
    switch (this) {
      case SafetyTier.newReporter:
        return 'New Reporter';
      case SafetyTier.trustedContributor:
        return 'Trusted Contributor';
      case SafetyTier.safetyGuardian:
        return 'Safety Guardian';
      case SafetyTier.elite:
        return 'Elite Level'; // panel's own example wording, kept exact
    }
  }
}

class CommunityImpactStats {
  final int hazardsVerified;
  final int obstaclesCleared;
  final SafetyTier tier;
  final int score;
  final int scoreToNextTier; // 0 if already at the top tier

  CommunityImpactStats({
    required this.hazardsVerified,
    required this.obstaclesCleared,
    required this.tier,
    required this.score,
    required this.scoreToNextTier,
  });
}

/// Powers the Profile screen's "Community Impact" section
/// (Total Hazards Verified / Route Obstacles Cleared / Community Safety
/// Score), per the panel's exact spec.
///
/// Both stats are deliberately NOT just "how many hazards did you
/// report" or "how many times did you tap Clear Now" — they only count
/// action that someone ELSE independently corroborated, which is the
/// panel's own fix for the point-farming risk it flagged:
/// - Hazards Verified: hazards YOU reported that another user confirmed
///   are still real (via hazard_verifications — "Still Here").
/// - Obstacles Cleared: how many times YOU personally helped confirm a
///   hazard was gone (via hazard_clear_confirmations — "Clear Now"),
///   crediting you for "keeping the database clean" per the panel's
///   wording, not the person who originally reported it.
class CommunityImpactService {
  static final _supabase = Supabase.instance.client;

  /// Score weights: a verification of your own report requires someone
  /// else to trust it enough to confirm it's real — a stronger signal
  /// than a single Clear Now vote — so it's weighted higher (x2) toward
  /// the tiered Safety Score.
  static const _verifiedWeight = 2;
  static const _clearedWeight = 1;

  static Future<CommunityImpactStats> fetchStats(String userId) async {
    int hazardsVerified = 0;
    int obstaclesCleared = 0;

    try {
      // My own hazard ids, so I can count how many of THEM got verified
      // by someone else (not how many verifications I personally gave —
      // this stat is about the credibility of what I've reported).
      final myHazards = await _supabase.from('hazards').select('id').eq('user_id', userId);
      final myHazardIds = (myHazards as List).cast<Map<String, dynamic>>().map((r) => r['id'] as String).toList();

      if (myHazardIds.isNotEmpty) {
        final verifications = await _supabase.from('hazard_verifications').select('hazard_id').inFilter('hazard_id', myHazardIds);
        final distinctVerifiedHazardIds = (verifications as List).cast<Map<String, dynamic>>().map((r) => r['hazard_id'] as String).toSet();
        hazardsVerified = distinctVerifiedHazardIds.length;
      }

      final clears = await _supabase.from('hazard_clear_confirmations').select('id').eq('user_id', userId);
      obstaclesCleared = (clears as List).length;
    } catch (e) {
      // ignore: avoid_print
      print('CommunityImpactService.fetchStats failed: $e');
    }

    final score = hazardsVerified * _verifiedWeight + obstaclesCleared * _clearedWeight;
    final tier = _tierForScore(score);
    final scoreToNextTier = _scoreToNextTier(score);

    return CommunityImpactStats(
      hazardsVerified: hazardsVerified,
      obstaclesCleared: obstaclesCleared,
      tier: tier,
      score: score,
      scoreToNextTier: scoreToNextTier,
    );
  }

  // Tier thresholds — documented here as the single source of truth so
  // they're easy to explain/defend and easy to retune later.
  static const _trustedContributorThreshold = 5;
  static const _safetyGuardianThreshold = 15;
  static const _eliteThreshold = 30;

  static SafetyTier _tierForScore(int score) {
    if (score >= _eliteThreshold) return SafetyTier.elite;
    if (score >= _safetyGuardianThreshold) return SafetyTier.safetyGuardian;
    if (score >= _trustedContributorThreshold) return SafetyTier.trustedContributor;
    return SafetyTier.newReporter;
  }

  static int _scoreToNextTier(int score) {
    if (score < _trustedContributorThreshold) return _trustedContributorThreshold - score;
    if (score < _safetyGuardianThreshold) return _safetyGuardianThreshold - score;
    if (score < _eliteThreshold) return _eliteThreshold - score;
    return 0;
  }

  /// Registers the current user's "Still Here" verification for
  /// [hazardId] — the original reporter's Hazards Verified count goes up
  /// by this. Fails (by design, via RLS) if you're the original
  /// reporter or you've already verified this one.
  static Future<bool> verifyStillHere(String hazardId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    try {
      await _supabase.from('hazard_verifications').insert({'hazard_id': hazardId, 'verifier_id': user.id});
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('CommunityImpactService.verifyStillHere failed: $e');
      return false;
    }
  }

  /// Verification counts + "did I already verify" for a set of hazard
  /// ids — same pattern as HazardService.fetchClearStatus.
  static Future<Map<String, ({int count, bool byMe})>> fetchVerificationStatus(List<String> hazardIds) async {
    if (hazardIds.isEmpty) return {};
    final currentUserId = _supabase.auth.currentUser?.id;

    try {
      final rows = await _supabase.from('hazard_verifications').select('hazard_id, verifier_id').inFilter('hazard_id', hazardIds);

      final counts = <String, int>{};
      final byMe = <String>{};
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final id = row['hazard_id'] as String;
        counts[id] = (counts[id] ?? 0) + 1;
        if (row['verifier_id'] == currentUserId) byMe.add(id);
      }

      return {for (final id in hazardIds) id: (count: counts[id] ?? 0, byMe: byMe.contains(id))};
    } catch (e) {
      // ignore: avoid_print
      print('CommunityImpactService.fetchVerificationStatus failed: $e');
      return {};
    }
  }
}
