import '../widgets/route_end_marker.dart';
import '../widgets/route_nav_icon.dart';
import '../widgets/track_arrow_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/hazard_cluster_config.dart';
import '../models/activity.dart';
import '../models/hazard_cluster.dart';
import '../models/hazard_report.dart';
import '../providers/activity_provider.dart';
import '../services/directions_service.dart';
import '../services/hazard_service.dart';
import 'activity_selection_screen.dart';

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
  // Cycling or running: changes the routing profile AND the time estimate.
  late ActivityType _type = widget.activityType == ActivityType.ride ? ActivityType.ride : ActivityType.run;
  bool _locating = false;
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
    final shared = await HazardService.fetchNear(near.latitude, near.longitude, searchRadiusMeters);
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
      activityType: _type,
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

  /// Hands the just-found route off to RecordScreen as a fixed guide
  /// line (the same "reference route" mechanism already used by "Track
  /// this Route" on a past shared activity — see routes_screen.dart /
  /// record_screen.dart), colored green for a Safest Itinerary or blue
  /// for a Direct Route, matching the colors of the trail just shown on
  /// this screen's map.
  ///
  /// Goes through ActivitySelectionScreen first (Cycling vs Running),
  /// then SubtypeSelectionScreen, exactly like a normal recording would
  /// — rather than assuming whatever activity type this planning screen
  /// happened to be opened with.
  ///
  /// GpsPoint requires a timestamp field (it's built for *recorded* GPS
  /// fixes), but a freshly-planned route has no real fix times — the
  /// polyline is all RecordScreen actually reads from it, so stamping
  /// every point with "now" is harmless filler, not meaningful data.
  void _trackThisRoute() {
    final route = _route;
    if (route == null) return;

    final now = DateTime.now();
    final referenceRoute = route.points.map((p) => GpsPoint(lat: p.latitude, lng: p.longitude, timestamp: now)).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActivitySelectionScreen(
          referenceRoute: referenceRoute,
          referenceRouteLabel: _safest ? 'your Safest Itinerary' : 'your Direct Route',
          referenceRouteColor: _safest ? const Color(0xff2ECC71) : const Color(0xff2F6FED),
        ),
      ),
    );
  }

  // ---- Distance and time estimates ----
  //
  // 1. The routing engine snaps your start and your pin to the nearest
  //    routable road or path. If either is off the road, the line it returns
  //    stops short, so the app adds the straight-line gap at each end
  //    (drawn dotted on the map) to the distance and the time.
  // 2. Time = distance / pace. The pace is the median of YOUR own saved
  //    activities of that type when there are at least 3 usable ones,
  //    otherwise a typical recreational pace.
  static const _typicalCycleKmh = 15.0;
  static const _typicalRunKmh = 8.0;
  static const _typicalWalkKmh = 5.0;

  /// Straight-line metres from your start to where the route begins, and
  /// from where it ends to your pin.
  double _startGapMeters(PlannedRoute r) {
    final start = _start;
    if (start == null || r.points.isEmpty) return 0;
    final f = r.points.first;
    return Geolocator.distanceBetween(start.latitude, start.longitude, f.latitude, f.longitude);
  }

  double _endGapMeters(PlannedRoute r) {
    final dest = _destination;
    if (dest == null || r.points.isEmpty) return 0;
    final l = r.points.last;
    return Geolocator.distanceBetween(l.latitude, l.longitude, dest.latitude, dest.longitude);
  }

  /// Route length plus the off-road gaps at both ends.
  double _totalMeters(PlannedRoute r) => r.distanceMeters + _startGapMeters(r) + _endGapMeters(r);

  /// Median average speed (km/h) of the user's own saved activities of
  /// [type], or null when there are fewer than 3 usable ones.
  double? _personalKmh(ActivityType type) {
    List<Activity> all;
    try {
      all = context.read<ActivityProvider>().allActivities;
    } catch (_) {
      return null;
    }
    final lo = type == ActivityType.ride ? 6.0 : 3.5;
    final hi = type == ActivityType.ride ? 45.0 : 18.0;
    final speeds = all
        .where((a) => a.type == type && a.distanceKm >= 0.5 && a.avgSpeedKmh >= lo && a.avgSpeedKmh <= hi)
        .take(30)
        .map((a) => a.avgSpeedKmh)
        .toList()
      ..sort();
    if (speeds.length < 3) return null;
    final mid = speeds.length ~/ 2;
    return speeds.length.isOdd ? speeds[mid] : (speeds[mid - 1] + speeds[mid]) / 2;
  }

  double _paceKmh(ActivityType type) {
    final mine = _personalKmh(type);
    if (mine != null) return mine;
    switch (type) {
      case ActivityType.ride:
        return _typicalCycleKmh;
      case ActivityType.run:
        return _typicalRunKmh;
      case ActivityType.walk:
        return _typicalWalkKmh;
    }
  }

  /// Estimated seconds for [type] over the whole trip (route + gaps).
  double _estimateSeconds(ActivityType type, PlannedRoute route) {
    return _totalMeters(route) / (_paceKmh(type) / 3.6);
  }

  /// "Based on your average pace" / "Based on a typical pace".
  String _paceSourceNote() {
    final mine = _personalKmh(_type) != null;
    return mine ? 'Time is based on your own average pace.' : 'Time is based on a typical pace. It adjusts once you have 3 saved activities.';
  }

  void _setType(ActivityType t) {
    if (t == _type) return;
    setState(() {
      _type = t;
      _route = null; // roads allowed differ for cycling vs running
    });
  }

  /// "Where am I?" - re-reads GPS, moves the map there and makes it the
  /// route start.
  Future<void> _locateMe() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final ok = await _ensurePermission();
      if (!ok) return;
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location services are turned off.'),
            action: SnackBarAction(label: 'Open Settings', onPressed: Geolocator.openLocationSettings),
          ),
        );
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final here = LatLng(position.latitude, position.longitude);
      setState(() {
        _start = here;
        _permissionError = null;
        _isLoadingLocation = false;
        _route = null;
      });
      _mapController.move(here, 16);
      _loadNearbyHazards(here);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't get your location. Check your phone's location settings.")));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  String _formatDuration(double seconds) {
    // Rounded UP to whole minutes: "about 3m" for a 2m10s trip reads
    // better than "2m" and never promises to be faster than it will be.
    final mins = (seconds / 60).ceil();
    if (mins >= 60) return '${mins ~/ 60}h ${mins % 60}m';
    return '${mins < 1 ? 1 : mins}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff050505),
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: false,
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
                    // Dotted lines for the part the routing engine could not
                    // follow: from your start to the route, and from the route
                    // to your pin.
                    if (_start != null && _route!.points.isNotEmpty && _startGapMeters(_route!) > 8)
                      Polyline(
                        points: [_start!, _route!.points.first],
                        color: Colors.white70,
                        strokeWidth: 3,
                        pattern: StrokePattern.dotted(),
                      ),
                    if (_destination != null && _route!.points.isNotEmpty && _endGapMeters(_route!) > 8)
                      Polyline(
                        points: [_route!.points.last, _destination!],
                        color: Colors.white70,
                        strokeWidth: 3,
                        pattern: StrokePattern.dotted(),
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
                      child: RouteEndMarker(isStart: true, type: _type, showLabel: false),
                    ),
                  if (_destination != null)
                    Marker(
                      point: _destination!,
                      width: 36,
                      height: 36,
                      // bottomCenter so the pin's pointed tip — not its
                      // bulb — lands exactly on the tapped coordinate.
                      alignment: Alignment.center,
                      child: const RouteEndMarker(isStart: false, type: ActivityType.ride, showLabel: false),
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
            right: 16,
            top: 72,
            child: Material(
              color: const Color(0xff0A0B0F),
              shape: const CircleBorder(side: BorderSide(color: Colors.white24)),
              elevation: 4,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _locateMe,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: _locating
                      ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location, color: Color(0xff2F7BFF)),
                ),
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              decoration: BoxDecoration(
                color: const Color(0xff0A0B0F),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: .08))),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3))),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _TierToggleButton(
                            label: 'Cycling',
                            subtitle: 'Bike-friendly roads',
                            icon: Icons.directions_bike,
                            selected: _type == ActivityType.ride,
                            onTap: () => _setType(ActivityType.ride),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TierToggleButton(
                            label: 'Running',
                            subtitle: 'Footpaths and streets',
                            icon: Icons.directions_run,
                            selected: _type == ActivityType.run,
                            onTap: () => _setType(ActivityType.run),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _TierToggleButton(
                            label: 'Safest Itinerary',
                            subtitle: 'Recommended route',
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
                            subtitle: 'Faster but less safe',
                            icon: Icons.arrow_right_alt,
                            selected: !_safest,
                            onTap: () => setState(() {
                              _safest = false;
                              _route = null;
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xff101216),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _StatTile(
                              icon: Icons.route,
                              label: 'Distance',
                              value: _route == null ? '--' : _formatDistance(_totalMeters(_route!)),
                            ),
                          ),
                          Container(width: 1, height: 36, color: Colors.white12),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _StatTile(
                              icon: Icons.schedule,
                              label: _type == ActivityType.ride ? 'Est. cycling time' : 'Est. running time',
                              value: _route == null ? '--' : _formatDuration(_estimateSeconds(_type, _route!)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_route != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          children: [
                            Text(
                              'Cycling about ${_formatDuration(_estimateSeconds(ActivityType.ride, _route!))}  \u00b7  Running about ${_formatDuration(_estimateSeconds(ActivityType.run, _route!))}',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                            ),
                            if (_startGapMeters(_route!) + _endGapMeters(_route!) > 30) ...[
                              const SizedBox(height: 3),
                              Text(
                                'Includes ${_formatDistance(_startGapMeters(_route!) + _endGapMeters(_route!))} off the mapped path (dotted line).',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5),
                              ),
                            ],
                            const SizedBox(height: 3),
                            Text(_paceSourceNote(), textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          flex: _route != null ? 11 : 1,
                          child: _FindRouteButton(
                            loading: _isFindingRoute,
                            onTap: (_start != null && _destination != null && !_isFindingRoute) ? _findRoute : null,
                          ),
                        ),
                        // Only shows up once a route has actually been
                        // found — nothing to track before that.
                        if (_route != null) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 8,
                            child: InkWell(
                              onTap: _trackThisRoute,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xff07140D),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xff2ECC71), width: 1.5),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    TrackArrowIcon(color: Color(0xff2ECC71), size: 18),
                                    SizedBox(width: 8),
                                    Text('Track', style: TextStyle(color: Color(0xff2ECC71), fontSize: 15, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
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
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _TierToggleButton({required this.label, required this.subtitle, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xff2F7BFF);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xff0B1C3D) : const Color(0xff121316),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? blue : Colors.white12, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? blue : Colors.grey.shade400, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? blue : Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                ],
              ),
            ),
            if (selected)
              Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: blue),
                child: const Icon(Icons.check, color: Colors.white, size: 13),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppIcon(icon, color: const Color(0xff2F7BFF), size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              const SizedBox(height: 2),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }
}

class _FindRouteButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;
  const _FindRouteButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null && !loading ? .5 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: [Color(0xff1459E0), Color(0xff2D7BFF)]),
            boxShadow: [BoxShadow(color: const Color(0xff2F7BFF).withValues(alpha: .35), blurRadius: 16, offset: const Offset(0, 5))],
          ),
          child: loading
              ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
              : const Row(
                  children: [
                    TrackArrowIcon(color: Colors.white, size: 18),
                    SizedBox(width: 10),
                    Expanded(child: Text('Find Route', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))),
                    Icon(Icons.chevron_right, color: Colors.white, size: 22),
                  ],
                ),
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
