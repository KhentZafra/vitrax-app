import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/env.dart';
import '../models/activity.dart';

/// A single planned route returned from OpenRouteService — just the
/// pieces the UI needs (the line to draw, plus the two headline
/// numbers), not the full GeoJSON response.
class PlannedRoute {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  const PlannedRoute({required this.points, required this.distanceMeters, required this.durationSeconds});
}

/// Calls OpenRouteService's Directions API for real, road-following
/// routes — the panel's own recommendation over building a custom
/// pathfinding server (Dijkstra/A*) from scratch, which is heavy to run
/// on a phone or a small backend. OpenRouteService is built directly on
/// OpenStreetMap data, matching the same map data this app's tiles
/// already use.
///
/// The "Safest Itinerary" half of the panel's requested toggle is
/// implemented via ORS's own `avoid_polygons` option: small circular
/// polygons dropped around every nearby community-reported hazard, so
/// the routing engine is told to route around those areas rather than
/// VITRAX trying to compute avoidance itself.
/// How the route is chosen: the quickest way there, or the shortest distance.
enum RoutePreference { fastest, shortest }

class DirectionsService {
  static const _baseUrl = 'https://api.openrouteservice.org/v2/directions';

  /// ORS's own routing profile names — picked from the activity type so
  /// a "safest route" for a run doesn't send you down a highway meant
  /// for cyclists, and vice versa.
  static String _profileFor(ActivityType type) {
    switch (type) {
      case ActivityType.ride:
        return 'cycling-regular';
      case ActivityType.run:
        return 'foot-walking'; // ORS name for its on-foot profile (running)
    }
  }

  /// Builds a rough circular polygon (16 sides) around [center] with
  /// [radiusMeters], in the [lng, lat] coordinate order GeoJSON expects.
  /// A true circle isn't representable in GeoJSON, but 16 sides is
  /// plenty for a ~50-100m avoidance zone — nobody will notice the
  /// difference between that and a real circle at routing scale.
  static List<List<double>> _circlePolygon(LatLng center, double radiusMeters) {
    const sides = 16;
    const earthRadius = 6371000.0;
    final latRad = center.latitude * math.pi / 180;

    final points = <List<double>>[];
    for (var i = 0; i <= sides; i++) {
      final angle = (i / sides) * 2 * math.pi;
      final dLat = (radiusMeters * math.cos(angle)) / earthRadius;
      final dLng = (radiusMeters * math.sin(angle)) / (earthRadius * math.cos(latRad));
      final pointLat = center.latitude + dLat * 180 / math.pi;
      final pointLng = center.longitude + dLng * 180 / math.pi;
      points.add([pointLng, pointLat]); // GeoJSON order: [lng, lat]
    }
    return points;
  }

  /// Fetches a route from [start] to [destination] for [activityType].
  /// When [avoidCenters] is non-empty, each point becomes a ~[avoidRadiusMeters]
  /// no-go zone the routing engine must detour around — pass the centers
  /// of nearby hazard clusters here for the "Safest Itinerary" mode, or
  /// an empty list for "Direct Route".
  ///
  /// Returns null on any failure (network error, no key configured, or
  /// ORS genuinely can't find a route — which can happen if avoidance
  /// zones box in the start or destination point entirely). The caller
  /// decides how to explain that to the user.
  static Future<PlannedRoute?> fetchRoute({
    required LatLng start,
    required LatLng destination,
    required ActivityType activityType,
    List<LatLng> avoidCenters = const [],
    double avoidRadiusMeters = 80,
  }) async {
    // Automatic: ask for both the fastest and the shortest way at once, then
    // take the shorter one when it costs almost no extra time (within 5%),
    // otherwise the fastest. The rider never has to choose.
    final results = await Future.wait([
      _fetchOne(start: start, destination: destination, activityType: activityType, avoidCenters: avoidCenters, avoidRadiusMeters: avoidRadiusMeters, preference: RoutePreference.fastest),
      _fetchOne(start: start, destination: destination, activityType: activityType, avoidCenters: avoidCenters, avoidRadiusMeters: avoidRadiusMeters, preference: RoutePreference.shortest),
    ]);
    final fastest = results[0];
    final shortest = results[1];
    if (fastest == null) return shortest;
    if (shortest == null) return fastest;
    final nearlyAsQuick = shortest.durationSeconds <= fastest.durationSeconds * 1.05;
    return (nearlyAsQuick && shortest.distanceMeters < fastest.distanceMeters) ? shortest : fastest;
  }

  static Future<PlannedRoute?> _fetchOne({
    required LatLng start,
    required LatLng destination,
    required ActivityType activityType,
    required List<LatLng> avoidCenters,
    required double avoidRadiusMeters,
    required RoutePreference preference,
  }) async {
    if (Env.orsApiKey.isEmpty || Env.orsApiKey == 'YOUR_OPENROUTESERVICE_API_KEY') {
      if (kDebugMode) print('DirectionsService: no ORS API key configured.');
      return null;
    }

    // Always route with the rider's own profile (cycling or running)
    // and ask OpenRouteService for the fastest or the shortest way there.
    final profile = _profileFor(activityType);
    final uri = Uri.parse('$_baseUrl/$profile/geojson');

    final body = <String, dynamic>{
      'coordinates': [
        [start.longitude, start.latitude],
        [destination.longitude, destination.latitude],
      ],
      'preference': preference == RoutePreference.shortest ? 'shortest' : 'fastest',
    };

    final options = <String, dynamic>{};
    if (avoidCenters.isNotEmpty) {
      options['avoid_polygons'] = {
        'type': 'MultiPolygon',
        'coordinates': avoidCenters.map((c) => [_circlePolygon(c, avoidRadiusMeters)]).toList(),
      };
    }
    if (options.isNotEmpty) body['options'] = options;

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Authorization': Env.orsApiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        if (kDebugMode) print('DirectionsService.fetchRoute failed: ${response.statusCode} ${response.body}');
        return null;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final features = decoded['features'] as List<dynamic>;
      if (features.isEmpty) return null;

      final feature = features.first as Map<String, dynamic>;
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = (geometry['coordinates'] as List<dynamic>).cast<List<dynamic>>();
      final points = coordinates.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();

      final properties = feature['properties'] as Map<String, dynamic>;
      final summary = properties['summary'] as Map<String, dynamic>;

      return PlannedRoute(
        points: points,
        distanceMeters: (summary['distance'] as num).toDouble(),
        durationSeconds: (summary['duration'] as num).toDouble(),
      );
    } catch (e) {
      if (kDebugMode) print('DirectionsService.fetchRoute failed: $e');
      return null;
    }
  }
}
