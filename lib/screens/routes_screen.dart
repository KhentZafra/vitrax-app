import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:skeletonizer/skeletonizer.dart';

import '../config/hazard_cluster_config.dart';
import '../models/activity.dart';
import '../models/hazard_cluster.dart';
import '../models/hazard_report.dart';
import '../models/shared_route.dart';
import '../services/community_impact_service.dart';
import '../services/hazard_service.dart';
import '../services/route_service.dart';
import '../widgets/route_nav_icon.dart';
import 'placeholder_screen.dart';
import 'community_feed_screen.dart';
import 'profile_screen.dart';
import 'record_screen.dart';

/// Community routes — anyone can browse these, whether or not they've
/// recorded an activity themselves. Shows every route a user has chosen
/// to share, with its path and any hazard reports made along it.
class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  List<SharedRoute> _routes = [];
  bool _isLoading = true;
  RouteSafetyTier? _filterTier; // null = All
  // null = All areas. Built from whatever place names actually show up
  // in the currently-loaded routes (see _availableLocations) rather than
  // a hardcoded Bohol town list, so it never goes stale and never shows
  // an area with nothing in it.
  String? _filterLocation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final routes = await RouteService.fetchSharedRoutes();
    if (!mounted) return;
    setState(() {
      _routes = routes;
      // A location picked before this refresh might no longer exist in
      // the new results (nobody's shared from there anymore) — falling
      // back to "All areas" instead of silently showing an empty list
      // with no obvious reason why.
      if (_filterLocation != null && !routes.any((r) => r.activity.location == _filterLocation)) {
        _filterLocation = null;
      }
      _isLoading = false;
    });
  }

  /// Distinct, sorted place names among the currently loaded routes —
  /// only routes with a successfully reverse-geocoded location
  /// contribute one (see Activity.location's own doc comment for when
  /// it's null). Used to populate the area filter dropdown.
  List<String> get _availableLocations {
    final locations = _routes.map((r) => r.activity.location).whereType<String>().where((l) => l.isNotEmpty).toSet().toList();
    locations.sort();
    return locations;
  }

  List<SharedRoute> get _visibleRoutes {
    return _routes.where((r) {
      if (_filterTier != null && r.safetyTier != _filterTier) return false;
      if (_filterLocation != null && r.activity.location != _filterLocation) return false;
      return true;
    }).toList();
  }

  Widget _buildTierFilterRow() {
    Widget chip(String label, IconData? icon, Color color, RouteSafetyTier? tier) {
      final selected = _filterTier == tier;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          avatar: icon != null ? Icon(icon, size: 16, color: selected ? Colors.white : color) : null,
          label: Text(label),
          selected: selected,
          onSelected: (_) => setState(() => _filterTier = tier),
          backgroundColor: const Color(0xff141414),
          selectedColor: tier == null ? Colors.blue : color.withValues(alpha: .22),
          labelStyle: TextStyle(
            color: selected ? (tier == null ? Colors.white : color) : Colors.grey.shade400,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          side: BorderSide(color: selected ? color : Colors.white10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('All', Icons.grid_view_rounded, Colors.blue, null),
          chip('Safe', Icons.shield_outlined, RouteSafetyTier.safe.color, RouteSafetyTier.safe),
          chip('Caution', Icons.warning_amber_rounded, RouteSafetyTier.caution.color, RouteSafetyTier.caution),
          chip('Hazardous', Icons.error_outline, RouteSafetyTier.hazardous.color, RouteSafetyTier.hazardous),
        ],
      ),
    );
  }

  /// Area dropdown — lets someone near Panglao, Dauis, Bilar, etc. jump
  /// straight to routes shared from around there, instead of scrolling
  /// past every route in Bohol. Hidden entirely once there's nothing to
  /// filter by (no shared routes yet, or none with a resolved location).
  Widget _buildLocationFilter() {
    final locations = _availableLocations;
    if (locations.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showLocationPicker(locations),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xff141414),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              Icon(Icons.location_on_outlined, color: _filterLocation != null ? Colors.blue : Colors.grey.shade500, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _filterLocation ?? 'All areas in Bohol',
                  style: TextStyle(
                    color: _filterLocation != null ? Colors.white : Colors.grey.shade400,
                    fontSize: 14,
                    fontWeight: _filterLocation != null ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (_filterLocation != null)
                InkWell(
                  onTap: () => setState(() => _filterLocation = null),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.close, color: Colors.grey.shade500, size: 16)),
                )
              else
                Icon(Icons.expand_more, color: Colors.grey.shade500, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // "All areas" is returned from the sheet as this empty-string sentinel
  // rather than null, so it stays distinguishable from "the sheet was
  // dismissed without picking anything" (which showModalBottomSheet
  // itself represents as null) — otherwise both cases look identical
  // and a dismissed sheet would wrongly clear the filter.
  static const _allAreasSentinel = '';

  Future<void> _showLocationPicker(List<String> locations) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xff141414),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (context) => _LocationPickerSheet(locations: locations, selected: _filterLocation, allAreasValue: _allAreasSentinel),
    );
    if (chosen == null || !mounted) return; // dismissed — leave the filter as-is
    setState(() => _filterLocation = chosen == _allAreasSentinel ? null : chosen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff050505),
      bottomNavigationBar: _buildBottomNav(),
      body: SafeArea(
        child: Skeletonizer(
          enabled: _isLoading,
          child: RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Routes', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Shared by the community', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                        const SizedBox(height: 18),
                        _buildTierFilterRow(),
                        _buildLocationFilter(),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                if (!_isLoading && _visibleRoutes.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(filtered: _filterTier != null || _filterLocation != null),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    sliver: SliverList.separated(
                      itemCount: _isLoading ? 3 : _visibleRoutes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        if (_isLoading) return const _RouteCardSkeleton();
                        final route = _visibleRoutes[index];
                        return _RouteCard(
                          route: route,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => RouteDetailScreen(route: route)),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Bottom nav (Home / Routes / Record / Community Feed / You) ----------
  //
  // Routes is the currently-selected tab here.

  void _navigateFromNav(int index) {
    const currentIndex = 1; // Routes
    if (index == currentIndex) return;

    switch (index) {
      case 0:
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
        break;
      case 2:
        Navigator.of(context).pushNamedAndRemoveUntil('/activitySelection', (route) => false);
        break;
      case 3:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityFeedScreen()));
        break;
      case 4:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
        break;
    }
  }

  Widget _buildBottomNav() {
    return Container(
      height: 90,
      padding: const EdgeInsets.only(top: 6),
      decoration: const BoxDecoration(color: Colors.black, border: Border(top: BorderSide(color: Colors.white10))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NavTab(icon: Icons.home_rounded, label: 'Home', selected: false, onTap: () => _navigateFromNav(0)),
          _NavTab(customIcon: (color) => RouteNavIcon(color: color), label: 'Routes', selected: true, onTap: () => _navigateFromNav(1)),
          _RecordNavTab(onTap: () => _navigateFromNav(2)),
          _NavTab(icon: Icons.chat_bubble_outline, label: 'Community', selected: false, onTap: () => _navigateFromNav(3)),
          _NavTab(icon: Icons.person_outline, label: 'You', selected: false, onTap: () => _navigateFromNav(4)),
        ],
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final IconData? icon;
  final Widget Function(Color color)? customIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({this.icon, this.customIcon, required this.label, required this.selected, required this.onTap})
      : assert(icon != null || customIcon != null);

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.blueAccent : Colors.grey;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            customIcon != null ? customIcon!(color) : Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _RecordNavTab extends StatelessWidget {
  final VoidCallback onTap;
  const _RecordNavTab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            offset: const Offset(0, -6),
            child: Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.blueAccent),
              // Nudged 2px right so the triangle's visual center (its
              // bulk sits left of its bounding box) lines up with the
              // circle's actual center instead of looking off-balance.
              child: const Center(child: Padding(padding: EdgeInsets.only(left: 2), child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30))),
            ),
          ),
          const Text('Record', style: TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }
}

/// Bottom sheet for choosing an area to filter shared routes by, plus a
/// live search box for when the community's shared enough routes that
/// scrolling a plain list stops being convenient.
class _LocationPickerSheet extends StatefulWidget {
  final List<String> locations;
  final String? selected;
  final String allAreasValue;
  const _LocationPickerSheet({required this.locations, required this.selected, required this.allAreasValue});

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.locations;
    return widget.locations.where((l) => l.toLowerCase().contains(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text('Filter by area', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  autofocus: widget.locations.length > 6, // not worth a keyboard popping up for a short list
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search Panglao, Dauis, Bilar…',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xff1a1a1a),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    ListTile(
                      leading: Icon(Icons.public, color: widget.selected == null ? Colors.blue : Colors.grey.shade500),
                      title: Text('All areas in Bohol', style: TextStyle(color: widget.selected == null ? Colors.blue : Colors.white, fontWeight: widget.selected == null ? FontWeight.w700 : FontWeight.normal)),
                      trailing: widget.selected == null ? const Icon(Icons.check, color: Colors.blue) : null,
                      onTap: () => Navigator.pop(context, widget.allAreasValue),
                    ),
                    if (_filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Text('No area matches your search.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                      )
                    else
                      ..._filtered.map((location) {
                        final selected = widget.selected == location;
                        return ListTile(
                          leading: Icon(Icons.location_on_outlined, color: selected ? Colors.blue : Colors.grey.shade500),
                          title: Text(location, style: TextStyle(color: selected ? Colors.blue : Colors.white, fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
                          trailing: selected ? const Icon(Icons.check, color: Colors.blue) : null,
                          onTap: () => Navigator.pop(context, location),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool filtered;
  const _EmptyState({this.filtered = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route, color: Colors.grey.shade700, size: 40),
            const SizedBox(height: 12),
            Text(
              filtered ? 'No routes match your filters' : 'No routes shared yet',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              filtered ? 'Try a different tier or area above.' : 'Record an activity and share it to the community to see it here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _activityIcon(ActivityType type) {
  switch (type) {
    case ActivityType.run:
      return Icons.directions_run;
    case ActivityType.walk:
      return Icons.directions_walk;
    case ActivityType.ride:
      return Icons.pedal_bike;
  }
}

String _estTimeLabel(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  return '$m min';
}

class _RouteCard extends StatelessWidget {
  final SharedRoute route;
  final VoidCallback onTap;

  const _RouteCard({required this.route, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = route.activity;
    final hazardCount = route.hazards.length;
    final tier = route.safetyTier;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xff141414),
            border: Border(left: BorderSide(color: tier.color, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 92,
                      height: 92,
                      child: _RouteSketch(points: a.route),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: .15),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(_activityIcon(a.type), color: Colors.blue, size: 16),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                a.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        if (a.location != null && a.location!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined, color: Colors.grey.shade500, size: 14),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  a.location!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: tier.color.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: tier.color)),
                        const SizedBox(width: 5),
                        Text(
                          hazardCount > 0 ? '${tier.label} · $hazardCount' : tier.label,
                          style: TextStyle(color: tier.color, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _CardStat(
                      icon: Icons.route_outlined,
                      iconColor: Colors.blue,
                      value: a.distanceKm.toStringAsFixed(1),
                      unit: 'km',
                      label: 'DISTANCE',
                    ),
                  ),
                  Expanded(
                    child: _CardStat(
                      icon: Icons.speed,
                      iconColor: Colors.lightBlueAccent,
                      value: a.avgSpeedKmh.toStringAsFixed(1),
                      unit: 'km/h',
                      label: 'AVG. SPEED',
                    ),
                  ),
                  Expanded(
                    child: _CardStat(
                      icon: Icons.access_time,
                      iconColor: Colors.blue,
                      value: _estTimeLabel(a.duration),
                      unit: '',
                      label: 'EST. TIME',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: const Color(0xff222222),
                    child: Icon(Icons.person, size: 15, color: Colors.grey.shade400),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Shared by ${route.sharerName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    ),
                  ),
                  Icon(Icons.more_vert, color: Colors.grey.shade600, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardStat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String unit;
  final String label;

  const _CardStat({required this.icon, required this.iconColor, required this.value, required this.unit, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 14),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                unit.isNotEmpty ? '$value $unit' : value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 10, letterSpacing: .3)),
      ],
    );
  }
}

class _RouteCardSkeleton extends StatelessWidget {
  const _RouteCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(color: const Color(0xff141414), borderRadius: BorderRadius.circular(18)),
    );
  }
}

/// A lightweight abstract sketch of the route's shape — drawn with a
/// CustomPainter rather than a live map, since rendering many real
/// FlutterMap/tile widgets in a scrolling list would be expensive.
class _RouteSketch extends StatelessWidget {
  final List<GpsPoint> points;
  const _RouteSketch({required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xff0b0b0b),
      child: CustomPaint(
        painter: _RoutePainter(points),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<GpsPoint> points;
  _RoutePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final lats = points.map((p) => p.lat);
    final lngs = points.map((p) => p.lng);
    final minLat = lats.reduce((a, b) => a < b ? a : b);
    final maxLat = lats.reduce((a, b) => a > b ? a : b);
    final minLng = lngs.reduce((a, b) => a < b ? a : b);
    final maxLng = lngs.reduce((a, b) => a > b ? a : b);

    final latRange = (maxLat - minLat).abs() < 0.0001 ? 0.0001 : (maxLat - minLat);
    final lngRange = (maxLng - minLng).abs() < 0.0001 ? 0.0001 : (maxLng - minLng);

    const padding = 10.0;
    Offset project(GpsPoint p) {
      final x = padding + ((p.lng - minLng) / lngRange) * (size.width - padding * 2);
      final y = size.height - padding - ((p.lat - minLat) / latRange) * (size.height - padding * 2);
      return Offset(x, y);
    }

    final path = Path()..moveTo(project(points.first).dx, project(points.first).dy);
    for (final p in points.skip(1)) {
      final o = project(p);
      path.lineTo(o.dx, o.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.blue
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(project(points.first), 4, Paint()..color = Colors.green);
    canvas.drawCircle(project(points.last), 4, Paint()..color = Colors.blue);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) => oldDelegate.points != points;
}

/// Distance in meters between two points, via the haversine formula
/// (avoids pulling in Geolocator just for this).
double _metersBetween(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  final dLat = (lat2 - lat1) * (math.pi / 180);
  final dLng = (lng2 - lng1) * (math.pi / 180);
  final lat1Rad = lat1 * math.pi / 180;
  final lat2Rad = lat2 * math.pi / 180;

  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1Rad) * math.cos(lat2Rad) * math.sin(dLng / 2) * math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadius * c;
}

/// Full detail view for a single shared route: real map, actual route
/// polyline colored per-segment by nearby hazards (Green/Orange/Red per
/// the panel's recommendation), hazard markers with a layer toggle to
/// hide/show them, and the hazard list below.
class RouteDetailScreen extends StatefulWidget {
  final SharedRoute route;
  const RouteDetailScreen({super.key, required this.route});

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  bool _showHazards = true;

  late final List<HazardCluster> _hazardClusters = HazardCluster.cluster(
    widget.route.hazards,
    thresholdMeters: HazardClusterConfig.duplicateThresholdMeters,
  );

  String _relativeTimeLabel(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showClusterSheet(BuildContext context, HazardCluster cluster) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xff141414),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (context) => _ClusterDetailSheet(cluster: cluster, relativeTimeLabel: _relativeTimeLabel),
    );
  }

  // How close (in meters) a hazard needs to be to a route point for that
  // stretch of the line to inherit the hazard's color.
  static const _hazardProximityMeters = 60.0;

  Color _colorNear(double lat, double lng) {
    Color best = const Color(0xff2ECC71); // green — safe by default
    double bestWeight = 0;
    for (final h in widget.route.hazards) {
      final distance = _metersBetween(lat, lng, h.position.latitude, h.position.longitude);
      if (distance > _hazardProximityMeters) continue;
      final weight = hazardSeverityWeight(h.type) * hazardRecencyMultiplier(h.reportedAt);
      if (weight > bestWeight) {
        bestWeight = weight;
        best = weight >= 3 ? const Color(0xffE53935) : const Color(0xffFB8C00); // red vs orange
      }
    }
    return best;
  }

  List<Polyline> _buildSegments(List<LatLng> points) {
    if (points.length < 2) return [];
    final segments = <Polyline>[];
    for (var i = 0; i < points.length - 1; i++) {
      final mid = LatLng((points[i].latitude + points[i + 1].latitude) / 2, (points[i].longitude + points[i + 1].longitude) / 2);
      final color = _colorNear(mid.latitude, mid.longitude);
      segments.add(Polyline(points: [points[i], points[i + 1]], color: color, strokeWidth: 5));
    }
    return segments;
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final a = route.activity;
    final points = a.route.map((p) => LatLng(p.lat, p.lng)).toList();

    return Scaffold(
      backgroundColor: const Color(0xff050505),
      appBar: AppBar(
        backgroundColor: const Color(0xff050505),
        title: Text(a.title, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        
        actions: [
          if (route.hazards.isNotEmpty)
            IconButton(
              tooltip: _showHazards ? 'Hide hazard markers' : 'Show hazard markers',
              onPressed: () => setState(() => _showHazards = !_showHazards),
              icon: Icon(_showHazards ? Icons.layers : Icons.layers_clear_outlined),
              
            ),
        ],
      ),
      body: Column(
        children: [
          if (points.length > 1)
            SizedBox(
              height: 260,
              child: FlutterMap(
                options: MapOptions(
                  initialCameraFit: CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(24)),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.vitrax.app',
                  ),
                  PolylineLayer(polylines: _buildSegments(points)),
                  if (_showHazards)
                    MarkerLayer(
                      markers: _hazardClusters
                          .map(
                            (c) => Marker(
                              point: c.center,
                              width: 34,
                              height: 34,
                              child: GestureDetector(
                                onTap: () => _showClusterSheet(context, c),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: c.type.color,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                      child: Icon(c.type.icon, color: Colors.white, size: 16),
                                    ),
                                    if (c.count > 1)
                                      Positioned(
                                        right: -2,
                                        top: -2,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white, width: 1)),
                                          child: Text('${c.count}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Shared by ${route.sharerName}', style: TextStyle(color: Colors.grey.shade400, fontSize: 14))),
                      _TierPill(tier: route.safetyTier),
                    ],
                  ),
                  if (a.location != null && a.location!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, color: Colors.grey.shade500, size: 15),
                        const SizedBox(width: 4),
                        Text(a.location!, style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _Stat(label: 'Distance', value: '${a.distanceKm.toStringAsFixed(2)} km'),
                      _Stat(label: 'Duration', value: '${a.duration.inHours}h ${a.duration.inMinutes.remainder(60)}m'),
                      _Stat(label: 'Avg Speed', value: '${a.avgSpeedKmh.toStringAsFixed(1)} km/h'),
                    ],
                  ),
                  if (points.length > 1) ...[
                    const SizedBox(height: 20),
                    _TrackRouteCard(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RecordScreen(
                            activityType: a.type,
                            subtype: a.subtype ?? a.title,
                            referenceRoute: a.route,
                            referenceRouteLabel: '${route.sharerName}\'s ${a.title}',
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text('Hazard reports (${_hazardClusters.length})', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_hazardClusters.isEmpty)
                    Text('No hazards were reported on this route.', style: TextStyle(color: Colors.grey.shade500, fontSize: 13))
                  else
                    ..._hazardClusters.map((c) => _HazardClusterRow(cluster: c, onTap: () => _showClusterSheet(context, c))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Track this Route" as a card rather than a plain flat button — an
/// icon badge, a title/subtitle pair explaining what tapping it does,
/// and a chevron, matching the tappable-row style used elsewhere in the
/// app (e.g. chat list rows) instead of a giant colored rectangle.
class _TrackRouteCard extends StatelessWidget {
  final VoidCallback onTap;
  const _TrackRouteCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xff102035),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blue.withValues(alpha: .35)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.blue.withValues(alpha: .18), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.near_me_rounded, color: Colors.blue, size: 20),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Track this Route', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  Text('Record your own attempt, following this exact trail', style: TextStyle(color: Colors.blue, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.blue, size: 22),
          ],
        ),
      ),
    );
  }
}

class _TierPill extends StatelessWidget {
  final RouteSafetyTier tier;
  const _TierPill({required this.tier});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: tier.color.withValues(alpha: .18), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: tier.color)),
          const SizedBox(width: 6),
          Text(tier.label, style: TextStyle(color: tier.color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      ],
    );
  }
}

class _HazardClusterRow extends StatelessWidget {
  final HazardCluster cluster;
  final VoidCallback onTap;
  const _HazardClusterRow({required this.cluster, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(shape: BoxShape.circle, color: cluster.type.color),
              child: Icon(cluster.type.icon, color: Colors.white, size: 14),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(cluster.type.label, style: const TextStyle(color: Colors.white, fontSize: 14))),
            if (cluster.count > 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(20)),
                child: Text('×${cluster.count}', style: TextStyle(color: Colors.grey.shade300, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: Colors.grey.shade600, size: 18),
          ],
        ),
      ),
    );
  }
}
/// Cluster detail sheet with "Clear Now" — the panel's exact spec: 3
/// distinct confirmations from other users auto-deletes the hazard
/// server-side (see 012_hazard_clear_now.sql's trigger). Shown per
/// individual report in the cluster (not one button for the whole
/// cluster) since each underlying report needs its own 3 confirmations —
/// a heavily-duplicated hazard is intentionally harder to fully clear,
/// consistent with the corroboration weighting already used in route
/// difficulty scoring.
class _ClusterDetailSheet extends StatefulWidget {
  final HazardCluster cluster;
  final String Function(DateTime) relativeTimeLabel;
  const _ClusterDetailSheet({required this.cluster, required this.relativeTimeLabel});

  @override
  State<_ClusterDetailSheet> createState() => _ClusterDetailSheetState();
}

class _ClusterDetailSheetState extends State<_ClusterDetailSheet> {
  Map<String, ({int count, bool byMe})> _clearStatus = {};
  Map<String, ({int count, bool byMe})> _verifyStatus = {};
  bool _loadingStatus = true;
  final Set<String> _busyIds = {};

  late final List<HazardReport> _sortedReports = [...widget.cluster.reports]..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final ids = _sortedReports.where((r) => r.id != null).map((r) => r.id!).toList();
    final clearStatus = await HazardService.fetchClearStatus(ids);
    final verifyStatus = await CommunityImpactService.fetchVerificationStatus(ids);
    if (!mounted) return;
    setState(() {
      _clearStatus = clearStatus;
      _verifyStatus = verifyStatus;
      _loadingStatus = false;
    });
  }

  Future<void> _confirmClear(String hazardId) async {
    setState(() => _busyIds.add(hazardId));
    final success = await HazardService.confirmClear(hazardId);
    if (!mounted) return;
    setState(() => _busyIds.remove(hazardId));

    if (success) {
      _loadStatus(); // refresh counts — may now be gone entirely if this was the 3rd
    } else {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't confirm, You may be the original reporter, or you've already confirmed this one.")),
      );
    }
  }

  Future<void> _confirmStillHere(String hazardId) async {
    setState(() => _busyIds.add(hazardId));
    final success = await CommunityImpactService.verifyStillHere(hazardId);
    if (!mounted) return;
    setState(() => _busyIds.remove(hazardId));

    if (success) {
      _loadStatus();
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks, This helps keep reports trustworthy.')));
    } else {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't confirm, You may be the original reporter, or you've already confirmed this one.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cluster = widget.cluster;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: cluster.type.color),
                  child: Icon(cluster.type.icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cluster.type.label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(
                        cluster.count == 1 ? 'Reported once' : 'Reported ${cluster.count} times',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _sortedReports.length,
                separatorBuilder: (_, __) => Divider(color: Colors.white10, height: 20),
                itemBuilder: (context, index) {
                  final r = _sortedReports[index];
                  final clearStatus = r.id != null ? _clearStatus[r.id] : null;
                  final clearCount = clearStatus?.count ?? 0;
                  final clearedByMe = clearStatus?.byMe ?? false;
                  final verifyStatus = r.id != null ? _verifyStatus[r.id] : null;
                  final verifiedByMe = verifyStatus?.byMe ?? false;
                  final busy = r.id != null && _busyIds.contains(r.id);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.circle, size: 6, color: Colors.grey.shade600),
                          const SizedBox(width: 10),
                          Text(widget.relativeTimeLabel(r.reportedAt), style: TextStyle(color: Colors.grey.shade300, fontSize: 13)),
                        ],
                      ),
                      if (r.id != null) ...[
                        const SizedBox(height: 8),
                        if (_loadingStatus)
                          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              OutlinedButton(
                                onPressed: (verifiedByMe || busy) ? null : () => _confirmStillHere(r.id!),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                  side: BorderSide(color: verifiedByMe ? Colors.blue : Colors.white24),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                                child: busy
                                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Text(
                                        verifiedByMe ? 'Verified still here' : 'Still Here?',
                                        style: TextStyle(color: verifiedByMe ? Colors.blue : Colors.white70, fontSize: 11),
                                      ),
                              ),
                              OutlinedButton(
                                onPressed: (clearedByMe || busy) ? null : () => _confirmClear(r.id!),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                  side: BorderSide(color: clearedByMe ? Colors.green : Colors.white24),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                                child: busy
                                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Text(
                                        clearedByMe ? 'Confirmed $clearCount/3' : 'Clear Now ($clearCount/3)',
                                        style: TextStyle(color: clearedByMe ? Colors.green : Colors.white70, fontSize: 11),
                                      ),
                              ),
                            ],
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Clear Now" if this is gone when you pass by. 3 confirmations from other users removes it automatically.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
