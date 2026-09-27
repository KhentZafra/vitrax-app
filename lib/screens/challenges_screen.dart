import 'package:flutter/material.dart';

import '../models/challenge.dart';
import '../services/challenge_service.dart';
import 'challenge_detail_screen.dart';
import 'create_challenge_screen.dart';

/// Browse/join screen for Community Challenges — the real feature
/// replacing the "coming soon" stub. Embedded as the content of the
/// Community Feed's Challenges tab.
class ChallengesScreen extends StatefulWidget {
  const ChallengesScreen({super.key});

  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  List<Challenge> _challenges = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final challenges = await ChallengeService.fetchChallenges();
    if (!mounted) return;
    setState(() {
      _challenges = challenges;
      _isLoading = false;
    });
  }

  Future<void> _openCreate() async {
    final created = await Navigator.push<Challenge>(
      context,
      MaterialPageRoute(builder: (_) => const CreateChallengeScreen()),
    );
    if (created != null) _load();
  }

  Future<void> _openDetail(Challenge challenge) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ChallengeDetailScreen(challengeId: challenge.id)));
    _load(); // refresh in case join state / completion changed
  }

  String _goalLabel(Challenge c) {
    final value = c.targetValue == c.targetValue.roundToDouble() ? c.targetValue.toInt().toString() : c.targetValue.toStringAsFixed(1);
    return '$value ${c.type.unitLabel}';
  }

  @override
  Widget build(BuildContext context) {
    final active = _challenges.where((c) => c.isActive).toList();
    final upcoming = _challenges.where((c) => !c.hasStarted).toList();
    final ended = _challenges.where((c) => c.hasEnded).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : RefreshIndicator(
              onRefresh: _load,
              child: _challenges.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 80),
                          child: Column(
                            children: [
                              Icon(Icons.emoji_events_outlined, color: Colors.grey.shade700, size: 40),
                              const SizedBox(height: 12),
                              Text('No challenges yet', style: TextStyle(color: Colors.grey.shade400, fontSize: 16, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text('Tap + to start one for the community.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      children: [
                        if (active.isNotEmpty) ..._section('Active', active),
                        if (upcoming.isNotEmpty) ..._section('Upcoming', upcoming),
                        if (ended.isNotEmpty) ..._section('Ended', ended),
                      ],
                    ),
            ),
    );
  }

  List<Widget> _section(String title, List<Challenge> items) {
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 8),
        child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
      ),
      ...items.map((c) => _ChallengeCard(challenge: c, goalLabel: _goalLabel(c), onTap: () => _openDetail(c))),
      const SizedBox(height: 8),
    ];
  }
}

class _ChallengeCard extends StatelessWidget {
  final Challenge challenge;
  final String goalLabel;
  final VoidCallback onTap;
  const _ChallengeCard({required this.challenge, required this.goalLabel, required this.onTap});

  String _dateRangeLabel() {
    String fmt(DateTime d) => '${d.month}/${d.day}';
    return '${fmt(challenge.startDate)} – ${fmt(challenge.endDate)}';
  }

  @override
  Widget build(BuildContext context) {
    final ended = challenge.hasEnded;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xff141414),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blue.withValues(alpha: .15)),
              child: Icon(
                challenge.iCompletedIt ? Icons.check_circle : Icons.emoji_events,
                color: challenge.iCompletedIt ? Colors.green : Colors.blue,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(challenge.title, style: TextStyle(color: ended ? Colors.grey.shade400 : Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '$goalLabel · ${challenge.activityFilter.label} · ${_dateRangeLabel()}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (challenge.joinedByMe)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.blue.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
                child: const Text('Joined', style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }
}
