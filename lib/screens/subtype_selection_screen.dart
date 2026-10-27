import 'package:flutter/material.dart';

import '../models/activity.dart';
import 'record_screen.dart';

const _cyclingSubtypes = [
  'Road cycling',
  'Mountain biking',
  'Gravel cycling',
  'Cycle touring',
  'Bikepacking',
  'BMX',
  'Fat biking',
  'Track cycling',
];

const _runningSubtypes = [
  'Recovery run',
  'Easy run',
  'Intervals',
  'Tempo run',
  'Threshold run',
  'Fartlek',
  'Progression run',
  'Hill reps',
];

/// Second step of the recording flow: after picking Cycling or Running on
/// ActivitySelectionScreen, this screen lets the user pick the specific
/// subtype. Tapping one navigates straight to RecordScreen — a separate,
/// dedicated screen, not a dropdown embedded inside the map screen.
///
/// [referenceRoute]/[referenceRouteLabel] are set only when reached from
/// "Track This Route" on PlanRouteScreen — a route the user just found
/// (Safest Itinerary or Direct Route) rather than a past shared activity.
/// Both are simply forwarded through to RecordScreen once a subtype is
/// picked, exactly like the existing "Track this Route" flow from
/// routes_screen.dart does for a previously-recorded activity.
class SubtypeSelectionScreen extends StatelessWidget {
  final ActivityType activityType;
  final List<GpsPoint>? referenceRoute;
  final String? referenceRouteLabel;
  final Color? referenceRouteColor;

  const SubtypeSelectionScreen({
    super.key,
    required this.activityType,
    this.referenceRoute,
    this.referenceRouteLabel,
    this.referenceRouteColor,
  });

  bool get _isCycling => activityType == ActivityType.ride;
  List<String> get _subtypes => _isCycling ? _cyclingSubtypes : _runningSubtypes;

  void _select(BuildContext context, String subtype) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordScreen(
          activityType: activityType,
          subtype: subtype,
          referenceRoute: referenceRoute,
          referenceRouteLabel: referenceRouteLabel,
          referenceRouteColor: referenceRouteColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff050505),
      appBar: AppBar(
        backgroundColor: const Color(0xff050505),
        title: Text(_isCycling ? 'Cycling' : 'Running'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What type of ${_isCycling ? 'cycling' : 'running'} activity?',
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose one to continue to GPS tracking.',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: _subtypes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final subtype = _subtypes[index];
                    return _SubtypeTile(
                      label: subtype,
                      icon: _isCycling ? Icons.pedal_bike : Icons.directions_run,
                      onTap: () => _select(context, subtype),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtypeTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SubtypeTile({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xff141414),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: Colors.blue.withValues(alpha: .15), shape: BoxShape.circle),
              child: Icon(icon, color: Colors.blue, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }
}
