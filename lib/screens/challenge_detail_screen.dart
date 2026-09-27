import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity.dart';
import '../models/challenge.dart';
import '../providers/activity_provider.dart';
import '../services/challenge_service.dart';

class ChallengeDetailScreen extends StatefulWidget {
  final String challengeId;
  const ChallengeDetailScreen({super.key, required this.challengeId});

  @override
  State<ChallengeDetailScreen> createState() => _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends State<ChallengeDetailScreen> {
  Challenge? _challenge;
  List<ChallengeStanding> _standings = [];
  List<ChallengeTimeEntry> _timeLeaderboard = [];
  ChallengeWinner? _winner;
  bool _isLoading = true;
  bool _busy = false;
  bool _submittingAttempt = false;
  // Read directly from the auth session, not from ActivityProvider —
  // deriving this from allActivities.firstOrNull?.userId broke for
  // anyone with zero recorded activities (a brand new joiner, for
  // instance), silently making both iAmWinner and iAmCreator wrong.
  final String? _currentUserId = Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final all = await ChallengeService.fetchChallenges();

    Challenge? found;
    for (final c in all) {
      if (c.id == widget.challengeId) {
        found = c;
        break;
      }
    }

    final isRoute = found?.isRouteChallenge ?? false;

    final standings = isRoute ? <ChallengeStanding>[] : await ChallengeService.fetchStandings(widget.challengeId);
    final timeLeaderboard = (found != null && isRoute) ? await ChallengeService.fetchRouteLeaderboard(found) : <ChallengeTimeEntry>[];
    final winner = (found != null && found.hasPrize) ? await ChallengeService.determineWinner(found) : null;

    if (!mounted) return;
    setState(() {
      _challenge = found;
      _standings = standings;
      _timeLeaderboard = timeLeaderboard;
      _winner = winner;
      _isLoading = false;
    });

    // Auto-complete and progress-push are goal-based-challenge concepts
    // only — a route challenge's "completion" is set directly by
    // submitRouteAttempt when a valid attempt is recorded, not by
    // comparing a progress number against targetValue.
    if (!isRoute) {
      _maybeAutoComplete();

      // Push my own current progress up so other participants see an
      // up-to-date standing for me too — harmless to call even if I
      // haven't joined (updateProgress no-ops when there's no matching
      // participant row) or if I've already completed (progress no
      // longer matters once completed_at is set — see build() below).
      if (mounted && found != null && found.joinedByMe && !found.iCompletedIt) {
        await ChallengeService.updateProgress(found.id, _myProgress);
      }
    }
  }

  /// My progress toward the goal, computed from activities already
  /// loaded in ActivityProvider — not a server round-trip. See the note
  /// on Challenge for why this is client-side and personal-only for
  /// regular challenges (the cash-prize WINNER is a separate,
  /// server-computed thing — see ChallengeService.determineWinner).
  /// Meaningless for a route challenge (always 0) — that type tracks a
  /// recorded time via submitRouteAttempt instead, see _timeLeaderboard.
  double get _myProgress {
    final c = _challenge;
    if (c == null || !mounted) return 0;

    final activities = context.read<ActivityProvider>().allActivities.where((a) {
      final inRange = !a.startedAt.isBefore(c.startDate) && !a.startedAt.isAfter(c.endDate);
      final matchesType = c.activityFilter == ChallengeActivityFilter.any ||
          (c.activityFilter == ChallengeActivityFilter.run && a.type == ActivityType.run) ||
          (c.activityFilter == ChallengeActivityFilter.ride && a.type == ActivityType.ride);
      return inRange && matchesType;
    });

    switch (c.type) {
      case ChallengeType.distance:
        return activities.fold(0.0, (sum, a) => sum + a.distanceKm);
      case ChallengeType.activityCount:
        return activities.length.toDouble();
      case ChallengeType.duration:
        return activities.fold(0.0, (sum, a) => sum + a.duration.inMinutes);
      case ChallengeType.route:
        return 0; // not used for route challenges — see _timeLeaderboard instead
    }
  }

  Future<void> _maybeAutoComplete() async {
    final c = _challenge;
    if (c == null || !c.joinedByMe || c.iCompletedIt) return;
    if (_myProgress < c.targetValue) return;

    final ok = await ChallengeService.markCompleted(c.id);
    if (!ok || !mounted) return;
    _load();
  }

  Future<void> _toggleJoin() async {
    final c = _challenge;
    if (c == null) return;
    setState(() => _busy = true);

    final success = c.joinedByMe ? await ChallengeService.leave(c.id) : await ChallengeService.join(c.id);

    if (!mounted) return;
    setState(() => _busy = false);
    if (success) {
      _load();
    } else {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Something went wrong, Please try again.')));
    }
  }

  Future<void> _uploadMyQr() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    final url = await ChallengeService.uploadMyGcashQr(challengeId: widget.challengeId, qrImage: File(picked.path));
    if (!mounted) return;
    setState(() => _busy = false);

    ScaffoldMessenger.of(context).clearSnackBars();
    if (url != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('QR code uploaded, The creator can now pay you.')));
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't upload, Please try again.")));
    }
  }

  Future<void> _markPaid() async {
    final winner = _winner;
    if (winner == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff141414),
        title: const Text('Mark prize as paid?', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
        content: Text('Confirm you\'ve sent the prize to ${winner.name} via GCash. This can\'t be undone.', style: TextStyle(color: Colors.grey.shade400)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm', style: TextStyle(color: Colors.blue))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final success = await ChallengeService.markPrizePaid(challengeId: widget.challengeId, winnerUserId: winner.userId);
    if (!mounted) return;
    setState(() => _busy = false);

    if (success) {
      _load();
    } else {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not confirm, Please try again.')));
    }
  }

  // ---------- Route-challenge attempt submission ----------

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  /// Lets the user pick one of their own already-recorded activities to
  /// submit as an attempt on this route challenge. Deliberately not a
  /// live "record now, auto-submit" flow — see the scoping note this
  /// was built against: submitting an attempt happens by picking a
  /// finished recording here, same as how the challenge itself gets
  /// created from a finished recording via RecordScreen's completion
  /// modal.
  Future<void> _pickAttemptActivity() async {
    final c = _challenge;
    if (c == null) return;

    final myActivities = context.read<ActivityProvider>().allActivities.where((a) => a.route.length > 1).toList();

    if (myActivities.isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You don't have any recorded activities with a route yet.")));
      return;
    }

    final selected = await showModalBottomSheet<Activity>(
      context: context,
      backgroundColor: const Color(0xff141414),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (context) => _ActivityPickerSheet(activities: myActivities),
    );

    if (selected == null || !mounted) return;
    await _submitAttempt(c, selected);
  }

  Future<void> _submitAttempt(Challenge challenge, Activity activity) async {
    setState(() => _submittingAttempt = true);
    final result = await ChallengeService.submitRouteAttempt(challenge, activity);
    if (!mounted) return;
    setState(() => _submittingAttempt = false);

    ScaffoldMessenger.of(context).clearSnackBars();
    switch (result.status) {
      case ChallengeAttemptStatus.success:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('New time recorded: ${_formatDuration(result.duration!)}! 🎉')));
        _load();
        break;
      case ChallengeAttemptStatus.notImproved:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Your best time is still ${_formatDuration(result.duration!)}, This attempt wasn\'t faster.')));
        break;
      case ChallengeAttemptStatus.tooFarFromStart:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("This activity didn't start close enough to the challenge's route.")));
        break;
      case ChallengeAttemptStatus.tooFarFromFinish:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("This activity didn't finish close enough to the challenge's route.")));
        break;
      case ChallengeAttemptStatus.implausiblePace:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That pace is faster than physically plausible for this activity type, Attempt rejected.')));
        break;
      case ChallengeAttemptStatus.error:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't submit, Please try again.")));
        break;
    }
  }

  String _goalLabel(Challenge c) {
    final value = c.targetValue == c.targetValue.roundToDouble() ? c.targetValue.toInt().toString() : c.targetValue.toStringAsFixed(1);
    return '$value ${c.type.unitLabel}';
  }

  String _progressLabel(double progress, Challenge c) {
    final p = progress == progress.roundToDouble() ? progress.toInt().toString() : progress.toStringAsFixed(1);
    return '$p / ${_goalLabel(c)}';
  }

  /// Winner's result, formatted for display — a duration for a route
  /// challenge (ChallengeWinner.progress holds raw seconds there, see
  /// its doc comment), the usual "X / goal" for everything else.
  String _winnerResultLabel(ChallengeWinner winner, Challenge c) {
    if (c.isRouteChallenge) return _formatDuration(Duration(seconds: winner.progress.round()));
    return _progressLabel(winner.progress, c);
  }

  String _peso(double amount) {
    final whole = amount == amount.roundToDouble() ? amount.toInt().toString() : amount.toStringAsFixed(2);
    return '₱$whole';
  }

  /// Finishers first (earliest completed_at first), then everyone still
  /// in progress sorted by how close they are to the target.
  List<ChallengeStanding> get _rankedStandings {
    final finished = _standings.where((s) => s.isCompleted).toList()..sort((a, b) => a.completedAt!.compareTo(b.completedAt!));
    final inProgress = _standings.where((s) => !s.isCompleted).toList()..sort((a, b) => b.progressValue.compareTo(a.progressValue));
    return [...finished, ...inProgress];
  }

  bool get _hasDisplayableRoute {
    final points = _challenge?.routePoints;
    if (points == null || points.length < 2) return false;
    final lats = points.map((p) => p.lat);
    final lngs = points.map((p) => p.lng);
    final latSpan = lats.reduce((a, b) => a > b ? a : b) - lats.reduce((a, b) => a < b ? a : b);
    final lngSpan = lngs.reduce((a, b) => a > b ? a : b) - lngs.reduce((a, b) => a < b ? a : b);
    // Same guard used on ActivityDetailScreen/RouteDetailScreen — a
    // near-zero-area bounding box crashes CameraFit.coordinates with
    // "Unsupported operation: Infinity or NaN toInt".
    return latSpan > 0.00001 || lngSpan > 0.00001;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(backgroundColor: Color(0xff050505), body: Center(child: CircularProgressIndicator(color: Colors.blue)));
    }

    final c = _challenge;
    if (c == null) {
      return const Scaffold(
        backgroundColor: Color(0xff050505),
        body: Center(child: Text('Challenge not found.', style: TextStyle(color: Colors.grey))),
      );
    }

    final progress = c.joinedByMe ? _myProgress : 0.0;
    final progressFraction = c.targetValue > 0 ? (progress / c.targetValue).clamp(0.0, 1.0) : 0.0;
    final iAmWinner = _winner != null && _winner!.userId == _currentUserId;
    final iAmCreator = c.creatorId == _currentUserId;
    final myBestTime = _timeLeaderboard.where((e) => e.userId == _currentUserId).map((e) => e.duration).firstOrNull;

    return Scaffold(
      backgroundColor: const Color(0xff050505),
      appBar: AppBar(backgroundColor: const Color(0xff050505), title: Text(c.title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.blue.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
                    child: Text(c.hasEnded ? 'Ended' : (c.hasStarted ? 'Active' : 'Upcoming'), style: const TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  if (c.isRouteChallenge) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.purple.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
                      child: const Text('Route Race', style: TextStyle(color: Colors.purpleAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: Text('by ${c.creatorName}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12), overflow: TextOverflow.ellipsis)),
                  if (c.hasPrize)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.amber.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.emoji_events, color: Colors.amber, size: 14),
                          const SizedBox(width: 5),
                          Text(_peso(c.prizeAmount!), style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                ],
              ),
              if ((c.description ?? '').isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(c.description!, style: TextStyle(color: Colors.grey.shade300, fontSize: 14, height: 1.4)),
              ],
              const SizedBox(height: 20),

              if (c.isRouteChallenge) ...[
                if (_hasDisplayableRoute)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 200,
                      child: IgnorePointer(
                        child: FlutterMap(
                          options: MapOptions(
                            initialCameraFit: CameraFit.coordinates(
                              coordinates: c.routePoints!.map((p) => LatLng(p.lat, p.lng)).toList(),
                              padding: const EdgeInsets.all(24),
                            ),
                            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                          ),
                          children: [
                            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.vitrax.app'),
                            PolylineLayer(polylines: [Polyline(points: c.routePoints!.map((p) => LatLng(p.lat, p.lng)).toList(), color: Colors.blue, strokeWidth: 4)]),
                            MarkerLayer(markers: [
                              Marker(point: c.startPoint!, width: 16, height: 16, child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green, border: Border.all(color: Colors.white, width: 2)))),
                              Marker(point: c.finishPoint!, width: 16, height: 16, child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red, border: Border.all(color: Colors.white, width: 2)))),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _InfoTile(label: 'Distance', value: '${c.targetValue.toStringAsFixed(1)} km')),
                    Expanded(child: _InfoTile(label: 'Time to Beat', value: c.baselineDuration != null ? _formatDuration(c.baselineDuration!) : '—')),
                    Expanded(child: _InfoTile(label: 'Attempts', value: '${_timeLeaderboard.length}')),
                  ],
                ),
              ] else
                Row(
                  children: [
                    Expanded(child: _InfoTile(label: 'Goal', value: _goalLabel(c))),
                    Expanded(child: _InfoTile(label: 'Counts', value: c.activityFilter.label)),
                    Expanded(child: _InfoTile(label: 'Joined', value: '${c.participantCount}')),
                  ],
                ),
              const SizedBox(height: 24),

              // ---------- Cash prize section ----------
              if (c.hasPrize) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.amber.withValues(alpha: .06), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.amber.withValues(alpha: .25))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.emoji_events, color: Colors.amber, size: 18),
                          const SizedBox(width: 8),
                          Text('${_peso(c.prizeAmount!)} prize', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (!c.hasEnded)
                        Text(
                          c.isRouteChallenge
                              ? 'Winner is decided once the challenge ends — fastest valid, shared time wins.'
                              : 'Winner is decided once the challenge ends — whoever has the highest qualifying result.',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 12.5, height: 1.4),
                        )
                      else if (_winner == null)
                        Text('No one reached the target, no prize awarded this time.', style: TextStyle(color: Colors.grey.shade400, fontSize: 12.5))
                      else ...[
                        Text('${_winner!.name} won with ${_winnerResultLabel(_winner!, c)}!', style: TextStyle(color: Colors.grey.shade300, fontSize: 13)),
                        const SizedBox(height: 12),

                        // Winner, hasn't uploaded QR yet
                        if (iAmWinner && _winner!.gcashQrUrl == null)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _busy ? null : _uploadMyQr,
                              icon: const Icon(Icons.qr_code, size: 18),
                              label: const Text('Upload your GCash QR to get paid'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 12)),
                            ),
                          ),

                        // Winner, already uploaded QR, not yet paid
                        if (iAmWinner && _winner!.gcashQrUrl != null && !_winner!.prizePaid)
                          Row(
                            children: [
                              const Icon(Icons.check_circle, color: Colors.green, size: 16),
                              const SizedBox(width: 6),
                              const Expanded(child: Text('QR uploaded, Waiting for the creator to send payment.', style: TextStyle(color: Colors.green, fontSize: 12.5))),
                            ],
                          ),

                        // Creator view: show winner's QR + mark paid
                        if (iAmCreator && !_winner!.prizePaid) ...[
                          if (_winner!.gcashQrUrl != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(_winner!.gcashQrUrl!, height: 220, width: double.infinity, fit: BoxFit.contain, color: null),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _busy ? null : _markPaid,
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.green)),
                                child: const Text('Mark as Paid', style: TextStyle(color: Colors.green)),
                              ),
                            ),
                          ] else
                            Text('Waiting for ${_winner!.name} to upload their GCash QR code.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5)),
                        ],

                        // Prize already paid — shown to anyone
                        if (_winner!.prizePaid)
                          const Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 16),
                              SizedBox(width: 6),
                              Text('Prize paid ✓', style: TextStyle(color: Colors.green, fontSize: 12.5, fontWeight: FontWeight.w600)),
                            ],
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              if (c.isRouteChallenge) ...[
                if (myBestTime != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Your best time', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Icon(
                            c.baselineDuration != null && myBestTime <= c.baselineDuration! ? Icons.check_circle : Icons.timer_outlined,
                            color: c.baselineDuration != null && myBestTime <= c.baselineDuration! ? Colors.green : Colors.blue,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(_formatDuration(myBestTime), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                if (!c.hasEnded)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _submittingAttempt ? null : _pickAttemptActivity,
                      icon: _submittingAttempt
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.directions_run, size: 18),
                      label: Text(myBestTime == null ? 'Submit an Attempt' : 'Submit a Faster Attempt'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    ),
                  ),
                const SizedBox(height: 12),
              ],

              if (!c.isRouteChallenge && c.joinedByMe) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Your progress', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                    if (c.iCompletedIt)
                      const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 16),
                          SizedBox(width: 4),
                          Text('Completed', style: TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progressFraction,
                    minHeight: 10,
                    backgroundColor: const Color(0xff1a1a1a),
                    valueColor: AlwaysStoppedAnimation(c.iCompletedIt ? Colors.green : Colors.blue),
                  ),
                ),
                const SizedBox(height: 6),
                Text(_progressLabel(progress, c), style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                const SizedBox(height: 24),
              ],

              if (!c.hasEnded)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _toggleJoin,
                    icon: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(c.joinedByMe ? Icons.close : Icons.add, size: 18),
                    label: Text(c.joinedByMe ? 'Leave Challenge' : 'Join Challenge'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: c.joinedByMe ? Colors.red.shade300 : Colors.blue),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),

              const SizedBox(height: 28),
              if (c.isRouteChallenge) ...[
                Text('Leaderboard (${_timeLeaderboard.length})', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Fastest valid attempt wins.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                const SizedBox(height: 12),
                if (_timeLeaderboard.isEmpty)
                  Text('No attempts yet, Be the first to try it.', style: TextStyle(color: Colors.grey.shade500, fontSize: 13))
                else
                  ..._timeLeaderboard.asMap().entries.map(
                        (entry) => _TimeEntryRow(
                          rank: entry.key + 1,
                          entry: entry.value,
                          formatDuration: _formatDuration,
                          isMe: entry.value.userId == _currentUserId,
                        ),
                      ),
              ] else ...[
                Text('Standings (${_standings.length})', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Finishers ranked by who got there first, then everyone else by progress.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (_standings.isEmpty)
                  Text('No one has joined yet.', style: TextStyle(color: Colors.grey.shade500, fontSize: 13))
                else
                  ..._rankedStandings.asMap().entries.map(
                        (entry) => _StandingRow(
                          rank: entry.key + 1,
                          standing: entry.value,
                          target: c.targetValue,
                          unitLabel: c.type.unitLabel,
                          isMe: entry.value.userId == _currentUserId,
                        ),
                      ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for picking which of your own recorded activities to
/// submit as an attempt on a route challenge.
class _ActivityPickerSheet extends StatelessWidget {
  final List<Activity> activities;
  const _ActivityPickerSheet({required this.activities});

  IconData _iconFor(Activity a) {
    switch (a.type) {
      case ActivityType.run:
        return Icons.directions_run;
      case ActivityType.walk:
        return Icons.directions_walk;
      case ActivityType.ride:
        return Icons.pedal_bike;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...activities]..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pick an activity to submit', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              "It has to actually start and finish close to this challenge's route to count.",
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sorted.length,
                separatorBuilder: (_, __) => Divider(color: Colors.white10, height: 1),
                itemBuilder: (context, index) {
                  final a = sorted[index];
                  final h = a.duration.inHours;
                  final m = a.duration.inMinutes.remainder(60);
                  final s = a.duration.inSeconds.remainder(60);
                  final durationLabel = h > 0 ? '${h}h ${m}m ${s}s' : (m > 0 ? '${m}m ${s}s' : '${s}s');
                  return ListTile(
                    onTap: () => Navigator.pop(context, a),
                    leading: CircleAvatar(backgroundColor: const Color(0xff222222), child: Icon(_iconFor(a), color: Colors.blue)),
                    title: Text(a.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${a.distanceKm.toStringAsFixed(1)} km · $durationLabel · ${DateFormat('MMM d, y').format(a.startedAt)}',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeEntryRow extends StatelessWidget {
  final int rank;
  final ChallengeTimeEntry entry;
  final String Function(Duration) formatDuration;
  final bool isMe;
  const _TimeEntryRow({required this.rank, required this.entry, required this.formatDuration, required this.isMe});

  Color? get _medalColor {
    switch (rank) {
      case 1:
        return const Color(0xffFFD700);
      case 2:
        return const Color(0xffC0C0C0);
      case 3:
        return const Color(0xffCD7F32);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final medal = _medalColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? Colors.blue.withValues(alpha: .12) : const Color(0xff141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isMe ? Colors.blue.withValues(alpha: .4) : Colors.white10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: medal != null
                ? Icon(Icons.emoji_events, color: medal, size: 20)
                : Text('#$rank', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Text(
                  isMe ? '${entry.name} (You)' : entry.name,
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: isMe ? FontWeight.w700 : FontWeight.w500),
                ),
                if (entry.isCreator) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.purple.withValues(alpha: .18), borderRadius: BorderRadius.circular(20)),
                    child: const Text('Creator', style: TextStyle(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
          Text(formatDuration(entry.duration), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  final int rank;
  final ChallengeStanding standing;
  final double target;
  final String unitLabel;
  final bool isMe;
  const _StandingRow({required this.rank, required this.standing, required this.target, required this.unitLabel, required this.isMe});

  Color? get _medalColor {
    if (!standing.isCompleted) return null;
    switch (rank) {
      case 1:
        return const Color(0xffFFD700); // gold
      case 2:
        return const Color(0xffC0C0C0); // silver
      case 3:
        return const Color(0xffCD7F32); // bronze
      default:
        return null;
    }
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(time);
  }

  String _progressText() {
    final p = standing.progressValue == standing.progressValue.roundToDouble()
        ? standing.progressValue.toInt().toString()
        : standing.progressValue.toStringAsFixed(1);
    final t = target == target.roundToDouble() ? target.toInt().toString() : target.toStringAsFixed(1);
    return '$p / $t $unitLabel';
  }

  @override
  Widget build(BuildContext context) {
    final medal = _medalColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? Colors.blue.withValues(alpha: .12) : const Color(0xff141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isMe ? Colors.blue.withValues(alpha: .4) : Colors.white10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: medal != null
                ? Icon(Icons.emoji_events, color: medal, size: 20)
                : Text('#$rank', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '${standing.name} (You)' : standing.name,
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: isMe ? FontWeight.w700 : FontWeight.w500),
                ),
                if (!standing.isCompleted) ...[
                  const SizedBox(height: 2),
                  Text(_progressText(), style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ],
              ],
            ),
          ),
          if (standing.isCompleted)
            Text(_relativeTime(standing.completedAt!), style: TextStyle(color: Colors.grey.shade500, fontSize: 12))
          else
            Icon(Icons.hourglass_empty, color: Colors.grey.shade700, size: 16),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
      ],
    );
  }
}
