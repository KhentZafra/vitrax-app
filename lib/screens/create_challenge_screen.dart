import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/challenge.dart';
import '../services/challenge_service.dart';

class CreateChallengeScreen extends StatefulWidget {
  /// When provided, this becomes a route challenge seeded from an
  /// activity the user just finished recording — its actual GPS path
  /// becomes the route, and its duration becomes the time other
  /// participants have to beat. The goal-type chips, target field, and
  /// activity-type filter are all hidden in this mode since they're
  /// derived from the activity instead of chosen manually. Null keeps
  /// the original goal-based creation flow (distance/duration/activity
  /// count) unchanged.
  final Activity? seedActivity;
  const CreateChallengeScreen({super.key, this.seedActivity});

  @override
  State<CreateChallengeScreen> createState() => _CreateChallengeScreenState();
}

class _CreateChallengeScreenState extends State<CreateChallengeScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _targetController = TextEditingController();
  final _prizeController = TextEditingController();

  late ChallengeType _type = widget.seedActivity != null ? ChallengeType.route : ChallengeType.distance;
  ChallengeActivityFilter _filter = ChallengeActivityFilter.any;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));
  bool _hasPrize = false;
  bool _submitting = false;

  bool get _isRouteMode => widget.seedActivity != null;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _targetController.dispose();
    _prizeController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: Colors.grey.shade400),
      hintStyle: TextStyle(color: Colors.grey.shade600),
      filled: true,
      fillColor: const Color(0xff141414),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate.add(const Duration(days: 7));
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give your challenge a title.')));
      return;
    }

    double target;
    ChallengeActivityFilter filter;
    if (_isRouteMode) {
      final seed = widget.seedActivity!;
      if (seed.route.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("This activity doesn't have enough route data to challenge others on.")));
        return;
      }
      target = seed.distanceKm; // repurposed for display only — see ChallengeType.route's doc comment
      filter = seed.type == ActivityType.run ? ChallengeActivityFilter.run : (seed.type == ActivityType.ride ? ChallengeActivityFilter.ride : ChallengeActivityFilter.any);
    } else {
      final parsed = double.tryParse(_targetController.text.trim());
      if (parsed == null || parsed <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid target.')));
        return;
      }
      target = parsed;
      filter = _filter;
    }

    double? prizeAmount;
    if (_hasPrize) {
      prizeAmount = double.tryParse(_prizeController.text.trim());
      if (prizeAmount == null || prizeAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid prize amount, or turn off the cash prize.')));
        return;
      }
    }

    setState(() => _submitting = true);

    final challenge = Challenge(
      id: '',
      creatorId: '',
      creatorName: '',
      title: title,
      description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      type: _type,
      targetValue: target,
      activityFilter: filter,
      startDate: _startDate,
      endDate: _endDate,
      createdAt: DateTime.now(),
      prizeAmount: prizeAmount,
      routePoints: _isRouteMode ? widget.seedActivity!.route : null,
      baselineDurationSeconds: _isRouteMode ? widget.seedActivity!.duration.inSeconds : null,
    );

    final created = await ChallengeService.createChallenge(challenge);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (created != null) {
      Navigator.pop(context, created);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create the challenge, Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff050505),
      appBar: AppBar(backgroundColor: const Color(0xff050505), title: const Text('Create a Challenge')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: _titleController, style: const TextStyle(color: Colors.white), decoration: _decoration('Title', hint: 'e.g. October Distance Challenge')),
              const SizedBox(height: 14),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: _decoration('Description (optional)', hint: 'What\'s this challenge about?'),
              ),
              const SizedBox(height: 20),

              if (_isRouteMode) ...[
                _RouteSummaryCard(activity: widget.seedActivity!),
                const SizedBox(height: 20),
              ] else ...[
                const Text('Goal type', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  // Route is deliberately excluded here — it can only
                  // come from seeding this screen with a just-recorded
                  // activity (see widget.seedActivity), never by typing
                  // a number, since a route challenge needs a real GPS
                  // path to validate attempts against.
                  children: ChallengeType.values.where((t) => t != ChallengeType.route).map((t) {
                    final selected = _type == t;
                    return ChoiceChip(
                      label: Text(t.unitLabel[0].toUpperCase() + t.unitLabel.substring(1)),
                      selected: selected,
                      onSelected: (_) => setState(() => _type = t),
                      backgroundColor: const Color(0xff141414),
                      selectedColor: Colors.blue.withValues(alpha: .3),
                      labelStyle: TextStyle(color: selected ? Colors.blue : Colors.grey.shade400),
                      side: BorderSide(color: selected ? Colors.blue : Colors.white12),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _targetController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration('Target (${_type.unitLabel})', hint: _type == ChallengeType.distance ? 'e.g. 50' : (_type == ChallengeType.activityCount ? 'e.g. 5' : 'e.g. 300')),
                ),
                const SizedBox(height: 20),
                const Text('Counts toward', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: ChallengeActivityFilter.values.map((f) {
                    final selected = _filter == f;
                    return ChoiceChip(
                      label: Text(f.label),
                      selected: selected,
                      onSelected: (_) => setState(() => _filter = f),
                      backgroundColor: const Color(0xff141414),
                      selectedColor: Colors.blue.withValues(alpha: .3),
                      labelStyle: TextStyle(color: selected ? Colors.blue : Colors.grey.shade400),
                      side: BorderSide(color: selected ? Colors.blue : Colors.white12),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
              ],

              const Text('Dates', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(isStart: true),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24), padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text('Start: ${_startDate.month}/${_startDate.day}/${_startDate.year}', style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(isStart: false),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24), padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text('End: ${_endDate.month}/${_endDate.day}/${_endDate.year}', style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Cash prize section — panel's "GCash QR instead of GCash
              // API" simplification: Vitrax never touches real money.
              // Setting a prize here just means "I intend to pay the
              // winner myself, outside the app, via GCash" — the app's
              // only job is determining who won and giving you their
              // receive-QR.
              SwitchListTile(
                value: _hasPrize,
                onChanged: (v) => setState(() => _hasPrize = v),
                title: const Text('Add a cash prize', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'You pay the winner yourself via GCash — Vitrax just determines who won and shows you their QR code.',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
                activeThumbColor: Colors.blue,
                contentPadding: EdgeInsets.zero,
              ),
              if (_hasPrize) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _prizeController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration('Prize amount (₱)', hint: 'e.g. 500'),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.blue.withValues(alpha: .08), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'The winner is whoever exceeds this challenge\'s target by the most, once it ends. Only shared activities count.',
                          style: TextStyle(color: Colors.blue.shade100, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: _submitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Create Challenge', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Read-only summary of the activity this route challenge is seeded
/// from — shows what challengers will actually be racing against
/// (distance, time to beat) since none of that is editable here.
class _RouteSummaryCard extends StatelessWidget {
  final Activity activity;
  const _RouteSummaryCard({required this.activity});

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  IconData get _typeIcon {
    switch (activity.type) {
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_typeIcon, color: Colors.blue, size: 18),
              const SizedBox(width: 8),
              Text(
                'Route challenge — ${activity.title}',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Others will retrace this exact route (same start and finish points) and try to beat your time.',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _stat(Icons.route_outlined, '${activity.distanceKm.toStringAsFixed(2)} km', 'Distance'),
              ),
              Expanded(
                child: _stat(Icons.timer_outlined, _formatDuration(activity.duration), 'Time to beat'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.grey.shade400, size: 16),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
      ],
    );
  }
}
