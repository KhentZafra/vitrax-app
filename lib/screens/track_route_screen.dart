import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:latlong2/latlong.dart';

import '../models/activity.dart';

/// Distance in meters between two points, via the haversine formula.
/// Kept local (same formula routes_screen.dart already uses for hazard
/// proximity) rather than importing Geolocator's own distanceBetween,
/// so this file has no surprise dependency beyond the position stream.
double _metersBetween(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  final dLat = (lat2 - lat1) * (math.pi / 180);
  final dLng = (lng2 - lng1) * (math.pi / 180);
  final lat1Rad = lat1 * math.pi / 180;
  final lat2Rad = lat2 * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(lat1Rad) * math.cos(lat2Rad) * math.sin(dLng / 2) * math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadius * c;
}

/// "Track this route" — shows the original sharer's exact recorded trail
/// as a fixed reference line on a live map, with your own current
/// position moving on top of it in real time, so you can follow the same
/// path they took. This is a guide, not turn-by-turn navigation: it
/// doesn't reroute or give directions, it just always shows you where
/// the original trail is relative to where you are right now.
class TrackRouteScreen extends StatefulWidget {
  final Activity activity;
  final String routeTitle;
  final String sharerName;
  const TrackRouteScreen({super.key, required this.activity, required this.routeTitle, required this.sharerName});

  @override
  State<TrackRouteScreen> createState() => _TrackRouteScreenState();
}

class _TrackRouteScreenState extends State<TrackRouteScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSub;

  late final List<LatLng> _referencePoints = widget.activity.route.map((p) => LatLng(p.lat, p.lng)).toList();

  LatLng? _currentLatLng;
  bool _followMe = true; // camera re-centers on you as you move, until you pan/zoom the map yourself
  bool _isLoadingFix = true;
  String? _permissionError;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<bool> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() => _permissionError = "Location access was denied. Enable it in your phone's Settings to track this route.");
      return false;
    }
    if (permission == LocationPermission.denied) {
      setState(() => _permissionError = 'Location permission is required to track this route.');
      return false;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _permissionError = 'Location services are turned off on this device.');
      return false;
    }
    return true;
  }

  Future<void> _start() async {
    final ok = await _ensurePermission();
    if (!ok || !mounted) return;

    const settings = LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 3);
    _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      if (!mounted) return;
      final latLng = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _currentLatLng = latLng;
        _isLoadingFix = false;
      });
      if (_followMe) {
        _mapController.move(latLng, _mapController.camera.zoom < 15 ? 17 : _mapController.camera.zoom);
      }
    });
  }

  void _fitToRoute() {
    if (_referencePoints.length < 2) return;
    _mapController.fitCamera(CameraFit.coordinates(coordinates: _referencePoints, padding: const EdgeInsets.all(40)));
  }

  /// Straight-line distance from your current position to the nearest
  /// point anywhere along the reference trail — a simple, honest "how
  /// far off the trail am I" number. Not a route-network distance (it
  /// can't know about roads/paths between the two points), which is a
  /// reasonable trade-off for a reference guide rather than a full
  /// navigation engine.
  double? get _distanceFromTrailMeters {
    final me = _currentLatLng;
    if (me == null || _referencePoints.isEmpty) return null;
    var best = double.infinity;
    for (final p in _referencePoints) {
      final d = _metersBetween(me.latitude, me.longitude, p.latitude, p.longitude);
      if (d < best) best = d;
    }
    return best;
  }

  double? get _distanceToStartMeters {
    final me = _currentLatLng;
    if (me == null || _referencePoints.isEmpty) return null;
    final start = _referencePoints.first;
    return _metersBetween(me.latitude, me.longitude, start.latitude, start.longitude);
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    final distanceFromTrail = _distanceFromTrailMeters;
    final distanceToStart = _distanceToStartMeters;
    // A rough "on the trail" read — anything within ~30m could just be
    // GPS drift or a parallel path, so it's not flagged as off-course.
    final onTrail = distanceFromTrail != null && distanceFromTrail <= 30;

    return Scaffold(
      backgroundColor: const Color(0xff050505),
      appBar: AppBar(
        backgroundColor: const Color(0xff050505),
        title: Text(widget.routeTitle, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              // Frame the whole reference trail on first render when
              // there's an actual path to show; otherwise fall back to a
              // plain center+zoom (a single-point "route" or one that
              // failed to record properly shouldn't crash the fit math).
              initialCameraFit: _referencePoints.length > 1 ? CameraFit.coordinates(coordinates: _referencePoints, padding: const EdgeInsets.all(40)) : null,
              initialCenter: _referencePoints.isNotEmpty ? _referencePoints.first : const LatLng(9.65, 123.85), // Bohol, as a sane fallback center
              initialZoom: 14,
              // A manual pan/zoom means the user wants to look around —
              // stop yanking the camera back to their position until
              // they explicitly ask to re-follow via the FAB below.
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && _followMe) setState(() => _followMe = false);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.vitrax.app',
              ),
              if (_referencePoints.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(points: _referencePoints, color: Colors.blue, strokeWidth: 5),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_referencePoints.isNotEmpty)
                    Marker(
                      point: _referencePoints.first,
                      width: 26,
                      height: 26,
                      child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green, border: Border.all(color: Colors.white, width: 2))),
                    ),
                  if (_referencePoints.length > 1)
                    Marker(
                      point: _referencePoints.last,
                      width: 26,
                      height: 26,
                      child: Container(
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blue, border: Border.all(color: Colors.white, width: 2)),
                        child: const Icon(Icons.flag, color: Colors.white, size: 14),
                      ),
                    ),
                  if (_currentLatLng != null)
                    Marker(
                      point: _currentLatLng!,
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.orangeAccent, border: Border.all(color: Colors.white, width: 3)),
                      ),
                    ),
                ],
              ),
            ],
          ),

          if (_permissionError != null)
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: _InfoBanner(icon: Icons.location_off, color: Colors.orange, message: _permissionError!),
            )
          else if (_isLoadingFix)
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: _InfoBanner(icon: Icons.gps_not_fixed, color: Colors.blueGrey, message: 'Getting your location…'),
            ),

          // Re-follow button — only meaningful once we've actually seen
          // a GPS fix and the user has panned away from it.
          if (_currentLatLng != null && !_followMe)
            Positioned(
              right: 16,
              bottom: 190,
              child: FloatingActionButton(
                heroTag: 'followMe',
                mini: true,
                backgroundColor: Colors.blue,
                onPressed: () {
                  setState(() => _followMe = true);
                  _mapController.move(_currentLatLng!, 17);
                },
                child: const Icon(Icons.my_location, color: Colors.white),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 130,
            child: FloatingActionButton(
              heroTag: 'fitRoute',
              mini: true,
              backgroundColor: const Color(0xff222222),
              onPressed: () {
                setState(() => _followMe = false);
                _fitToRoute();
              },
              child: const Icon(Icons.route, color: Colors.white),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: const BoxDecoration(
                color: Color(0xff0d0d0d),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Following ${widget.sharerName}\'s trail', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                      ),
                      if (distanceFromTrail != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: (onTrail ? Colors.green : Colors.orange).withValues(alpha: .18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            onTrail ? 'On the trail' : '${_formatDistance(distanceFromTrail)} from trail',
                            style: TextStyle(color: onTrail ? Colors.green : Colors.orange, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _TrackStat(label: 'ROUTE DISTANCE', value: '${a.distanceKm.toStringAsFixed(1)} km')),
                      Expanded(child: _TrackStat(label: 'EST. TIME', value: '${a.duration.inHours}h ${a.duration.inMinutes.remainder(60)}m')),
                      Expanded(
                        child: _TrackStat(
                          label: 'TO START',
                          value: distanceToStart != null ? _formatDistance(distanceToStart) : '—',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  const _InfoBanner({required this.icon, required this.color, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xff141414), borderRadius: BorderRadius.circular(12), border: Border.all(color: color)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: color, fontSize: 12))),
        ],
      ),
    );
  }
}

class _TrackStat extends StatelessWidget {
  final String label;
  final String value;
  const _TrackStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 10, letterSpacing: .3)),
      ],
    );
  }
}
