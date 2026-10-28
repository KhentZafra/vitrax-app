import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/activity.dart';

/// Start / finish marker for route maps. The start shows the activity's own
/// icon (cyclist for rides, runner for runs) and the finish
/// shows a flag, each with a "Start" / "Finish" label.
class RouteEndMarker extends StatelessWidget {
  final bool isStart;
  final ActivityType type;
  final bool showLabel;
  const RouteEndMarker({super.key, required this.isStart, required this.type, this.showLabel = true});

  static IconData startIcon(ActivityType type) {
    switch (type) {
      case ActivityType.run:
        return Icons.directions_run;
      case ActivityType.ride:
        return Icons.directions_bike;
    }
  }

  /// Ready-made markers for the first and last point of a route.
  static List<Marker> markers(List<LatLng> points, ActivityType type, {double size = 32}) {
    if (points.isEmpty) return const [];
    return [
      Marker(
        point: points.last,
        width: size,
        height: size,
        child: RouteEndMarker(isStart: false, type: type),
      ),
      Marker(
        point: points.first,
        width: size,
        height: size,
        child: RouteEndMarker(isStart: true, type: type),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final color = isStart ? const Color(0xff2ECC71) : const Color(0xffE53935);
    final label = isStart ? 'Start' : 'Finish';
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
          ),
          child: Center(child: Icon(isStart ? startIcon(type) : Icons.flag_rounded, color: Colors.white, size: 18)),
        ),
        if (showLabel)
          Positioned(
            left: -22,
            right: -22,
            top: isStart ? -22 : 36,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .82),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color, width: 1),
                ),
                child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
      ],
    );
  }
}
