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
  final Set<String> _expanded = {};

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

  static const _blue = Color(0xff1E88FF);

  @override
  Widget build(BuildContext context) {
    final active = _challenges.where((c) => c.isActive).toList();
    final upcoming = _challenges.where((c) => !c.hasStarted).toList();
    final ended = _challenges.where((c) => c.hasEnded).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: GestureDetector(
        onTap: _openCreate,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: _blue,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: _blue.withValues(alpha: .4), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  const _ChallengesBanner(),
                  const SizedBox(height: 18),
                  if (_challenges.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 50),
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
                  if (active.isNotEmpty) ..._section('Active', active),
                  if (upcoming.isNotEmpty) ..._section('Upcoming', upcoming),
                  if (ended.isNotEmpty) ..._section('Ended', ended),
                ],
              ),
            ),
    );
  }

  static const _collapsedCount = 3;

  List<Widget> _section(String title, List<Challenge> items) {
    final expanded = _expanded.contains(title);
    final canToggle = items.length > _collapsedCount;
    final shown = expanded || !canToggle ? items : items.take(_collapsedCount).toList();
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Container(width: 4, height: 18, decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
            if (canToggle)
              InkWell(
                onTap: () => setState(() => expanded ? _expanded.remove(title) : _expanded.add(title)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    children: [
                      Text(expanded ? 'Show less' : 'View all', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                      Icon(expanded ? Icons.expand_less : Icons.chevron_right, color: Colors.grey.shade400, size: 18),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      ...shown.map((c) => _ChallengeCard(challenge: c, goalLabel: _goalLabel(c), onTap: () => _openDetail(c))),
      const SizedBox(height: 10),
    ];
  }
}

class _ChallengesBanner extends StatelessWidget {
  const _ChallengesBanner();

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xff1E88FF);
    return Container(
      height: 84,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [Color(0xff0A2350), Color(0xff071327)]),
        border: Border.all(color: blue.withValues(alpha: .45)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned(
              right: 6,
              bottom: -6,
              child: Row(
                children: [
                  Icon(Icons.directions_run, size: 56, color: blue.withValues(alpha: .28)),
                  Icon(Icons.directions_run, size: 62, color: blue.withValues(alpha: .22)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xff0C2F6B)),
                    child: const Icon(Icons.emoji_events, color: blue, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Challenges', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(
                          'Join challenges, earn badges, and stay consistent together.',
                          maxLines: 2,
                          style: TextStyle(color: Colors.grey.shade300, fontSize: 12, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 50),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  final Challenge challenge;
  final String goalLabel;
  final VoidCallback onTap;
  const _ChallengeCard({required this.challenge, required this.goalLabel, required this.onTap});

  static const _blue = Color(0xff1E88FF);

  String _dateRangeLabel() {
    String fmt(DateTime d) => '${d.month}/${d.day}';
    return '${fmt(challenge.startDate)} – ${fmt(challenge.endDate)}';
  }

  IconData _activityIcon() {
    switch (challenge.activityFilter) {
      case ChallengeActivityFilter.run:
        return Icons.directions_run;
      case ChallengeActivityFilter.ride:
        return Icons.directions_bike;
      case ChallengeActivityFilter.any:
        return Icons.groups;
    }
  }

  /// Right side of the footer: your result if you finished, otherwise
  /// where the challenge is in its schedule.
  Widget _status() {
    if (challenge.iCompletedIt) {
      return const _StatusText(icon: Icons.check_circle, text: 'Completed', color: Colors.green);
    }
    if (challenge.hasEnded) {
      return _StatusText(icon: Icons.flag, text: 'Ended', color: Colors.grey.shade500);
    }
    if (!challenge.hasStarted) {
      final d = challenge.startDate;
      return _StatusText(icon: Icons.schedule, text: 'Starts ${d.month}/${d.day}', color: _blue);
    }
    final left = challenge.endDate.difference(DateTime.now()).inDays;
    return _StatusText(icon: Icons.timer_outlined, text: left <= 0 ? 'Ends today' : 'Ends in ${left}d', color: _blue);
  }

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.grey.shade400, size: 15),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(color: Colors.grey.shade300, fontSize: 12)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final ended = challenge.hasEnded;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xff0B0E13),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 4, color: _blue)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 14, 12),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xff0C2447)),
                            child: Icon(
                              challenge.iCompletedIt ? Icons.check_circle : Icons.emoji_events,
                              color: challenge.iCompletedIt ? Colors.green : _blue,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        challenge.title,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: ended ? Colors.grey.shade300 : Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    if (challenge.joinedByMe)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(color: _blue.withValues(alpha: .18), borderRadius: BorderRadius.circular(20)),
                                        child: const Text('Joined', style: TextStyle(color: _blue, fontSize: 11, fontWeight: FontWeight.w600)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 14,
                                  runSpacing: 6,
                                  children: [
                                    _meta(Icons.route, goalLabel),
                                    _meta(_activityIcon(), challenge.activityFilter.label),
                                    _meta(Icons.calendar_month, _dateRangeLabel()),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Colors.white12),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.groups, color: Colors.grey.shade400, size: 18),
                          const SizedBox(width: 6),
                          Text('${challenge.participantCount} participants', style: TextStyle(color: Colors.grey.shade300, fontSize: 13)),
                          const Spacer(),
                          _status(),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _StatusText({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
