import '../widgets/route_nav_icon.dart';
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

  // Inline error messages shown under the field that is wrong.
  String? _titleError;
  String? _targetError;
  String? _prizeError;
  String? _dateError;
  String? _formError;
  final _scrollController = ScrollController();

  bool get _isRouteMode => widget.seedActivity != null;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _targetController.dispose();
    _prizeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {String? hint, IconData? icon, String? error}) {
    OutlineInputBorder border(Color c, [double w = 1.2]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: c, width: w));
    return InputDecoration(
      hintText: hint ?? label,
      errorText: error,
      errorMaxLines: 3,
      errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
      hintStyle: TextStyle(color: Colors.grey.shade600),
      prefixIcon: icon == null ? null : Icon(icon, color: Colors.white54),
      filled: true,
      fillColor: const Color(0xff0c0f14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: border(Colors.white12),
      enabledBorder: border(Colors.white12),
      focusedBorder: border(Colors.blue, 1.6),
      errorBorder: border(Colors.redAccent, 1.4),
      focusedErrorBorder: border(Colors.redAccent, 1.8),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      );

  /// Rounded selectable pill with an icon, used for goal type / counts toward.
  Widget _choice({required IconData icon, required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xff0a77ff) : const Color(0xff0c0f14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? Colors.blue : Colors.white24, width: 1.2),
          boxShadow: selected ? [BoxShadow(color: Colors.blue.withValues(alpha: .35), blurRadius: 12)] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(ChallengeType t) {
    switch (t) {
      case ChallengeType.distance:
        return Icons.route;
      case ChallengeType.activityCount:
        return Icons.bolt;
      case ChallengeType.duration:
        return Icons.schedule;
      case ChallengeType.route:
        return Icons.route;
    }
  }

  IconData _filterIcon(ChallengeActivityFilter f) {
    switch (f) {
      case ChallengeActivityFilter.any:
        return Icons.groups_outlined;
      case ChallengeActivityFilter.run:
        return Icons.directions_run;
      case ChallengeActivityFilter.ride:
        return Icons.directions_bike;
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    // Real-time dates only: nothing before today, and the end can never be
    // before the start.
    final today = _dayOnly(DateTime.now());
    final firstDate = isStart ? today : (_dayOnly(_startDate).isBefore(today) ? today : _dayOnly(_startDate));
    var initial = isStart ? _startDate : _endDate;
    if (_dayOnly(initial).isBefore(firstDate)) initial = firstDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _dateError = null;
      _formError = null;
      if (isStart) {
        _startDate = picked;
        if (_dayOnly(_endDate).isBefore(_dayOnly(_startDate))) _endDate = _startDate.add(const Duration(days: 7));
      } else {
        _endDate = picked;
      }
    });
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void _showFormError(String message) {
    setState(() => _formError = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    setState(() {
      _titleError = null;
      _targetError = null;
      _prizeError = null;
      _dateError = null;
      _formError = null;
    });
    var hasError = false;

    if (title.isEmpty) {
      _titleError = 'Please enter a title for your challenge.';
      hasError = true;
    } else if (title.length < 3) {
      _titleError = 'The title is too short (at least 3 characters).';
      hasError = true;
    }

    if (_dayOnly(_startDate).isBefore(_dayOnly(DateTime.now()))) {
      _dateError = 'The start date cannot be in the past. Pick today or a later date.';
      hasError = true;
    } else if (_dayOnly(_endDate).isBefore(_dayOnly(_startDate))) {
      _dateError = 'The end date cannot be before the start date.';
      hasError = true;
    }

    double target;
    ChallengeActivityFilter filter;
    if (_isRouteMode) {
      final seed = widget.seedActivity!;
      if (seed.route.length < 2) {
        _showFormError("This activity doesn't have enough route data to challenge others on.");
        return;
      }
      target = seed.distanceKm; // repurposed for display only — see ChallengeType.route's doc comment
      filter = seed.type == ActivityType.run ? ChallengeActivityFilter.run : (seed.type == ActivityType.ride ? ChallengeActivityFilter.ride : ChallengeActivityFilter.any);
    } else {
      final parsed = double.tryParse(_targetController.text.trim());
      if (parsed == null || parsed <= 0) {
        _targetError = 'Enter a target greater than 0 (numbers only).';
        hasError = true;
      }
      target = parsed ?? 0;
      filter = _filter;
    }

    double? prizeAmount;
    if (_hasPrize) {
      prizeAmount = double.tryParse(_prizeController.text.trim());
      if (prizeAmount == null || prizeAmount <= 0) {
        _prizeError = 'Enter a prize amount greater than 0, or turn off the cash prize.';
        hasError = true;
      }
    }

    if (hasError) {
      setState(() {});
      _showFormError('Please fix the highlighted fields.');
      return;
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
      // Start of the first day to the END of the last day, so a challenge
      // that starts and ends on the same day lasts that whole day.
      // Starting today means starting right now (real time); a later start
      // begins at the start of that day.
      startDate: _dayOnly(_startDate) == _dayOnly(DateTime.now()) ? DateTime.now() : _dayOnly(_startDate),
      endDate: DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59),
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
      _showFormError(ChallengeService.lastCreateError ?? 'Could not create the challenge. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff050505),
      appBar: AppBar(backgroundColor: const Color(0xff050505), foregroundColor: Colors.white, title: const Text('Create a Challenge', style: TextStyle(fontWeight: FontWeight.w700))),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_formError != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: .12), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.redAccent)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_formError!, style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.35))),
                    ],
                  ),
                ),
              _heading('Title'),
              TextField(controller: _titleController, maxLength: 50, style: const TextStyle(color: Colors.white), decoration: _decoration('Title', hint: 'e.g. October Distance Challenge', icon: Icons.description_outlined, error: _titleError)),
              const SizedBox(height: 14),
              _heading('Description (optional)'),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                maxLength: 300,
                style: const TextStyle(color: Colors.white),
                decoration: _decoration('Description (optional)', hint: 'What\'s this challenge about?', icon: Icons.description_outlined),
              ),
              const SizedBox(height: 20),

              if (_isRouteMode) ...[
                _RouteSummaryCard(activity: widget.seedActivity!),
                const SizedBox(height: 20),
              ] else ...[
                _heading('Goal type'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  // Route is deliberately excluded here — it can only
                  // come from seeding this screen with a just-recorded
                  // activity (see widget.seedActivity), never by typing
                  // a number, since a route challenge needs a real GPS
                  // path to validate attempts against.
                  children: ChallengeType.values.where((t) => t != ChallengeType.route).map((t) {
                    return _choice(
                      icon: _typeIcon(t),
                      label: t.unitLabel[0].toUpperCase() + t.unitLabel.substring(1),
                      selected: _type == t,
                      onTap: () => setState(() => _type = t),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _targetController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration('Target (${_type.unitLabel})', icon: Icons.outlined_flag, error: _targetError),
                ),
                const SizedBox(height: 20),
                _heading('Counts toward'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: ChallengeActivityFilter.values.map((f) {
                    return _choice(
                      icon: _filterIcon(f),
                      label: f.label,
                      selected: _filter == f,
                      onTap: () => setState(() => _filter = f),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
              ],

              _heading('Dates'),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(isStart: true),
                      style: OutlinedButton.styleFrom(backgroundColor: const Color(0xff0c0f14), side: const BorderSide(color: Colors.white12, width: 1.2), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: Row(children: [
                        const Icon(Icons.calendar_month_outlined, color: Colors.white70, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('Start: ${_startDate.month}/${_startDate.day}/${_startDate.year}', style: const TextStyle(color: Colors.white)))),
                        const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 20),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(isStart: false),
                      style: OutlinedButton.styleFrom(backgroundColor: const Color(0xff0c0f14), side: const BorderSide(color: Colors.white12, width: 1.2), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: Row(children: [
                        const Icon(Icons.calendar_month_outlined, color: Colors.white70, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('End: ${_endDate.month}/${_endDate.day}/${_endDate.year}', style: const TextStyle(color: Colors.white)))),
                        const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 20),
                      ]),
                    ),
                  ),
                ],
              ),
              if (_dateError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Text(_dateError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Text('A challenge can start and end on the same day (it lasts the whole day).', style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
                ),
              const SizedBox(height: 20),

              // Cash prize section — panel's "GCash QR instead of GCash
              // API" simplification: Vitrax never touches real money.
              // Setting a prize here just means "I intend to pay the
              // winner myself, outside the app, via GCash" — the app's
              // only job is determining who won and giving you their
              // receive-QR.
              _heading('Add a cash prize'),
              SwitchListTile(
                value: _hasPrize,
                onChanged: (v) => setState(() => _hasPrize = v),
                secondary: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: const Color(0xff141a22), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white70),
                ),
                title: const SizedBox.shrink(),
                subtitle: Text(
                  'Pay the winner yourself via GCash — just determines who won and shows their QR code.',
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
                  decoration: _decoration('Prize amount (₱)', icon: Icons.payments_outlined, error: _prizeError),
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
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff0a77ff), foregroundColor: Colors.white, elevation: 6, shadowColor: Colors.blue, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                  child: _submitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Create Challenge', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
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
        AppIcon(icon, color: Colors.grey.shade400, size: 16),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
      ],
    );
  }
}
