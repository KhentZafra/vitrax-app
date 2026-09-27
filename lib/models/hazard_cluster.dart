import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:latlong2/latlong.dart';
import 'hazard_report.dart';

/// A group of same-type hazard reports that are close enough together to
/// represent as one pin instead of many overlapping ones — e.g. 8 separate
/// "Aggressive Dogs" reports near the same intersection become a single
/// cluster showing "8" with a circle covering the area they were reported in.
class HazardCluster {
  final HazardType type;
  final LatLng center;
  final double radiusMeters;
  final List<HazardReport> reports;

  HazardCluster({required this.type, required this.center, required this.radiusMeters, required this.reports});

  int get count => reports.length;

  /// Groups reports by type, then greedily merges same-type reports within
  /// [thresholdMeters] of a cluster's running centroid. Not a rigorous
  /// clustering algorithm (e.g. no DBSCAN), but simple, fast, and good
  /// enough for "same spot, same hazard" grouping at city-street scale.
  static List<HazardCluster> cluster(List<HazardReport> reports, {double thresholdMeters = 100}) {
    final byType = <HazardType, List<HazardReport>>{};
    for (final r in reports) {
      byType.putIfAbsent(r.type, () => []).add(r);
    }

    final clusters = <HazardCluster>[];

    for (final entry in byType.entries) {
      final type = entry.key;
      final points = entry.value;
      final used = List<bool>.filled(points.length, false);

      for (var i = 0; i < points.length; i++) {
        if (used[i]) continue;
        final group = <HazardReport>[points[i]];
        used[i] = true;

        var centerLat = points[i].position.latitude;
        var centerLng = points[i].position.longitude;

        for (var j = i + 1; j < points.length; j++) {
          if (used[j]) continue;
          final distance = Geolocator.distanceBetween(
            centerLat,
            centerLng,
            points[j].position.latitude,
            points[j].position.longitude,
          );
          if (distance <= thresholdMeters) {
            group.add(points[j]);
            used[j] = true;
            // Recompute running centroid as the simple average of the group.
            centerLat = group.map((r) => r.position.latitude).reduce((a, b) => a + b) / group.length;
            centerLng = group.map((r) => r.position.longitude).reduce((a, b) => a + b) / group.length;
          }
        }

        final center = LatLng(centerLat, centerLng);
        final radius = group
            .map((r) => Geolocator.distanceBetween(centerLat, centerLng, r.position.latitude, r.position.longitude))
            .fold<double>(0, (max, d) => d > max ? d : max);

        clusters.add(HazardCluster(
          type: type,
          center: center,
          // Minimum visual radius so a single-report "cluster" still shows
          // a visible circle rather than a zero-radius dot.
          radiusMeters: radius < 30 ? 30 : radius,
          reports: group,
        ));
      }
    }

    return clusters;
  }
}
