import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:latlong2/latlong.dart';

import '../config/hazard_cluster_config.dart';
import '../models/activity.dart';
import '../models/hazard_cluster.dart';
import '../models/hazard_report.dart';
import '../services/directions_service.dart';
import '../services/hazard_service.dart';

/// Plan a route from your current location to a tapped destination,
/// with a toggle between "Direct Route" (fastest/shortest, ignores
/// hazard reports) and "Safest Itinerary" (routes around nearby
/// community-reported hazard clusters) — the panel's exact
/// recommendation, built on OpenRouteService rather than a custom
/// pathfinding engine.
class PlanRouteScreen extends StatefulWidget {
  final ActivityType activityType;
  const PlanRouteScreen({super.key, required this.activityType});

  @override
  State<PlanRouteScreen> createState() => _PlanRouteScreenState();
}

class _PlanRouteScreenState extends State<PlanRouteScreen> {
  final MapController _mapController = MapController();

  LatLng? _start;
  LatLng? _destination;
  bool _safest = true;
  bool _isLoadingLocation = true;
  bool _isFindingRoute = false;
  String? _permissionError;

  List<HazardCluster> _hazardClusters = [];
  PlannedRoute? _route;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await _ensurePermission();
    if (!ok || !mounted) return;

    try {
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final here = LatLng(position.latitude, position.longitude);
      setState(() {
        _start = here;
        _isLoadingLocation = false;
      });
      _mapController.move(here, 15);
      _loadNearbyHazards(here);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingLocation = false;
        _permissionError = "Couldn't get your current location. Check your phone's location settings.";
      });
    }
  }

  Future<bool> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
      setState(() {
        _isLoadingLocation = false;
        _permissionError = 'Location permission is required to plan a route.';
      });
      return false;
    }
    return true;
  }

  /// Loads shared hazards near your starting point and clusters them —
  /// clustering matters here beyond just display: it also cuts down how
  /// many separate avoidance polygons get sent to OpenRouteService, so
  /// ten reports of the same pothole become one avoidance zone, not ten
  /// overlapping ones.
  Future<void> _loadNearbyHazards(LatLng near) async {
    const searchRadiusMeters = 5000.0;
    final shared = await HazardService.fetchShared();
    if (!mounted) return;

    final nearby = shared.where((h) {
      final distance = Geolocator.distanceBetween(near.latitude, near.longitude, h.position.latitude, h.position.longitude);
      return distance <= searchRadiusMeters;
    }).toList();

    setState(() {
      _hazardClusters = HazardCluster.cluster(nearby, thresholdMeters: HazardClusterConfig.duplicateThresholdMeters);
    });
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _destination = point;
      _route = null; // stale once the destination changes
    });
  }

  Future<void> _findRoute() async {
    final start = _start;
    final destination = _destination;
    if (start == null || destination == null) return;

    setState(() => _isFindingRoute = true);

    final avoidCenters = _safest ? _hazardClusters.map((c) => c.center).toList() : <LatLng>[];

    final route = await DirectionsService.fetchRoute(
      start: start,
      destination: destination,
      activityType: widget.activityType,
      avoidCenters: avoidCenters,
    );

    if (!mounted) return;
    setState(() {
      _isFindingRoute = false;
      _route = route;
    });

    if (route == null) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _safest
                ? "Couldn't find a safe route avoiding nearby hazards. Try Direct Route, or pick a closer destination."
                : "Couldn't find a route to that destination. Try a different spot.",
          ),
        ),
      );
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  String _formatDuration(double seconds) {
    final d = Duration(seconds: seconds.round());
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff050505),
      appBar: AppBar(
        backgroundColor: const Color(0xff050505),
        title: const Text('Plan a Route', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _start ?? const LatLng(9.65, 123.85), // Bohol fallback
              initialZoom: 14,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.vitrax.app',
              ),
              if (_route != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _route!.points,
                      color: _safest ? const Color(0xff2ECC71) : const Color(0xff2F6FED),
                      strokeWidth: 5,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  ..._hazardClusters.map(
                    (c) => Marker(
                      point: c.center,
                      width: 26,
                      height: 26,
                      child: Container(
                        decoration: BoxDecoration(shape: BoxShape.circle, color: c.type.color.withValues(alpha: .85), border: Border.all(color: Colors.white, width: 1.5)),
                        child: Icon(c.type.icon, color: Colors.white, size: 13),
                      ),
                    ),
                  ),
                  if (_start != null)
                    Marker(
                      point: _start!,
                      width: 24,
                      height: 24,
                      child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blue, border: Border.all(color: Colors.white, width: 2))),
                    ),
                  if (_destination != null)
                    Marker(
                      point: _destination!,
                      width: 30,
                      height: 30,
                      child: const Icon(Icons.location_on, color: Colors.redAccent, size: 30),
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
              child: _InfoBanner(message: _permissionError!),
            )
          else if (_isLoadingLocation)
            const Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: _InfoBanner(message: 'Getting your location…'),
            )
          else if (_destination == null)
            const Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: _InfoBanner(message: 'Tap anywhere on the map to set your destination.'),
            ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                        child: _TierToggleButton(
                          label: 'Safest Itinerary',
                          icon: Icons.shield_outlined,
                          selected: _safest,
                          onTap: () => setState(() {
                            _safest = true;
                            _route = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TierToggleButton(
                          label: 'Direct Route',
                          icon: Icons.trending_flat,
                          selected: !_safest,
                          onTap: () => setState(() {
                            _safest = false;
                            _route = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_route != null) ...[
                    Row(
                      children: [
                        Icon(Icons.route, color: Colors.grey.shade400, size: 16),
                        const SizedBox(width: 6),
                        Text(_formatDistance(_route!.distanceMeters), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 18),
                        Icon(Icons.access_time, color: Colors.grey.shade400, size: 16),
                        const SizedBox(width: 6),
                        Text(_formatDuration(_route!.durationSeconds), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_start != null && _destination != null && !_isFindingRoute) ? _findRoute : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isFindingRoute
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Find Route', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
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

class _TierToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _TierToggleButton({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.blueAccent.withValues(alpha: .18) : const Color(0xff181818),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? Colors.blueAccent : Colors.white10),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? Colors.blueAccent : Colors.grey.shade400, size: 18),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: selected ? Colors.blueAccent : Colors.grey.shade400, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String message;
  const _InfoBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xff141414), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.blueAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white70, fontSize: 12))),
        ],
      ),
    );
  }
}
