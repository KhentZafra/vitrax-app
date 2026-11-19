import '../widgets/dialog_buttons.dart';
import '../widgets/route_end_marker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../models/activity.dart';
import '../providers/activity_provider.dart';
import 'package:provider/provider.dart';

class _Palette {
  static const background = Color(0xff050505);
  static const card = Color(0xff111111);
  static const cardAlt = Color(0xff1b1b1b);
  static const border = Colors.white10;
}

/// Full detail view for a single saved activity — route map, distance,
/// duration, average speed, and (when the recording captured enough GPS
/// points) top speed reached during the activity. Reached by tapping the
/// arrow on a Recent Activity tile or a row in AllActivitiesScreen.
class ActivityDetailScreen extends StatelessWidget {
  final Activity activity;

  const ActivityDetailScreen({super.key, required this.activity});

  List<LatLng> get _routePoints => activity.route.map((p) => LatLng(p.lat, p.lng)).toList();

  /// Highest speed reached between any two consecutive GPS points,
  /// filtering out physically-implausible jumps the same way the live
  /// recorder filters GPS noise — a single bad fix shouldn't be able to
  /// report a 300 km/h "top speed". Returns 0 if there isn't enough
  /// route data to compute this (fewer than 2 points — e.g. an activity
  /// saved before route recording, or a very short test recording).
  double get _maxSpeedKmh {
    final route = activity.route;
    if (route.length < 2) return 0;

    final maxPlausibleKmh = activity.type == ActivityType.ride ? 60.0 : 40.0;
    double maxSpeed = 0;

    // Speed over windows of at least 5 seconds, not between two single
    // points: one noisy fix (or fixes that arrived late after a signal gap)
    // used to create a fake spike such as 67 km/h on a bicycle.
    var start = 0;
    for (var i = 1; i < route.length; i++) {
      while (start < i - 1 && route[i].timestamp.difference(route[start + 1].timestamp).inSeconds >= 5) {
        start++;
      }
      final a = route[start];
      final b = route[i];
      final seconds = b.timestamp.difference(a.timestamp).inMilliseconds / 1000;
      if (seconds < 5) continue;
      final meters = Geolocator.distanceBetween(a.lat, a.lng, b.lat, b.lng);
      final kmh = (meters / seconds) * 3.6;
      if (kmh <= maxPlausibleKmh && kmh > maxSpeed) maxSpeed = kmh;
    }
    return maxSpeed;
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  IconData get _typeIcon {
    switch (activity.type) {
      case ActivityType.run:
        return Icons.directions_run;
      case ActivityType.ride:
        return Icons.pedal_bike;
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final provider = context.read<ActivityProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff141414),
        title: const Text('Delete this activity?', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
        content: Text(
          activity.shared
              ? 'It will be removed for good, including from Routes, the Community feed and any challenge it counts toward.'
              : 'It will be removed from your history for good.',
          style: TextStyle(color: Colors.grey.shade400, height: 1.4),
        ),
        actions: [
          DialogSafeButton(label: 'Keep', onPressed: () => Navigator.pop(ctx, false)),
          DialogDangerButton(label: 'Delete', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok != true) return;
    final done = await provider.deleteActivity(activity);
    messenger.clearSnackBars();
    if (done) {
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Activity deleted.')));
    } else {
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't delete the activity. Please try again.")));
    }
  }

  /// Shares an activity that was not shared yet, so it appears in Routes and
  /// counts toward challenges. It is not posted to the Community feed.
  Future<void> _confirmShare(BuildContext context, Activity a) async {
    final provider = context.read<ActivityProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff141414),
        title: const Text('Share this activity?', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
        content: Text(
          'It will appear in Routes and count toward any challenge you joined. It will not be posted on the Community feed.',
          style: TextStyle(color: Colors.grey.shade400, height: 1.4),
        ),
        actions: [
          DialogSafeButton(label: 'Not now', onPressed: () => Navigator.pop(ctx, false)),
          DialogSafeButton(label: 'Share', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok != true) return;
    final id = a.id;
    final done = id != null && await provider.markActivityShared(id);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text(done
          ? 'Shared. It now appears in Routes and counts toward your challenges.'
          : "Couldn't share this activity. Check your internet and try again."),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hasRoute = _routePoints.length > 1;
    final maxSpeed = _maxSpeedKmh;
    // The activity can change while this page is open (for example after
    // sharing), so read the current copy from the provider.
    final live = context.watch<ActivityProvider>().allActivities.firstWhere(
          (x) => x.id != null && x.id == activity.id,
          orElse: () => activity,
        );

    return Scaffold(
      backgroundColor: _Palette.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activity.title,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            DateFormat('MMM d, yyyy • h:mm a').format(activity.startedAt),
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: _Palette.cardAlt, shape: BoxShape.circle),
                      child: Icon(_typeIcon, color: Colors.blue, size: 20),
                    ),
                    IconButton(
                      tooltip: 'Delete activity',
                      icon: Icon(Icons.delete_outline, color: Colors.red.shade300),
                      onPressed: () => _confirmDelete(context),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: 260,
                    child: hasRoute
                        ? FlutterMap(
                            options: MapOptions(
                              initialCameraFit: CameraFit.coordinates(
                                coordinates: _routePoints,
                                padding: const EdgeInsets.all(28),
                              ),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.vitrax.app',
                              ),
                              PolylineLayer(
                                polylines: [Polyline(points: _routePoints, color: Colors.blue, strokeWidth: 4)],
                              ),
                              MarkerLayer(markers: RouteEndMarker.markers(_routePoints, activity.type)),
                            ],
                          )
                        : Container(
                            color: _Palette.card,
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.map_outlined, color: Colors.grey.shade600, size: 32),
                                const SizedBox(height: 8),
                                Text(
                                  'No route recorded for this activity',
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _DetailStat(
                            icon: Icons.map_outlined,
                            iconColor: Colors.blue,
                            value: activity.distanceKm.toStringAsFixed(2),
                            unit: 'km',
                            label: 'Distance',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DetailStat(
                            icon: Icons.access_time,
                            iconColor: Colors.greenAccent,
                            value: _formatDuration(activity.duration),
                            unit: '',
                            label: 'Duration',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _DetailStat(
                            icon: Icons.bolt,
                            iconColor: Colors.blue,
                            value: activity.avgSpeedKmh.toStringAsFixed(1),
                            unit: 'km/h',
                            label: 'Avg Speed',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DetailStat(
                            icon: Icons.speed,
                            iconColor: Colors.lightBlueAccent,
                            value: maxSpeed > 0 ? maxSpeed.toStringAsFixed(1) : '—',
                            unit: maxSpeed > 0 ? 'km/h' : '',
                            label: 'Top Speed',
                          ),
                        ),
                      ],
                    ),
                    if (!live.shared && !live.pendingSync && live.id != null) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _confirmShare(context, live),
                          icon: const Icon(Icons.share, size: 18),
                          label: const Text('Share to Routes and challenges', style: TextStyle(fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xff22c55e),
                            foregroundColor: const Color(0xff04210f),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                    if (live.shared) ...[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle, color: Colors.blue, size: 16),
                            SizedBox(width: 8),
                            Text('Shared with Community', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                    if (live.pendingSync) ...[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cloud_off, color: Colors.blue, size: 16),
                            SizedBox(width: 8),
                            Text('Not yet synced, Will upload once online', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String unit;
  final String label;

  const _DetailStat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.unit,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(unit, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }
}
