import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:vitrax_app/models/hazard_cluster.dart';
import 'package:vitrax_app/models/hazard_report.dart';

/// Grouping of duplicate hazard reports into one pin.
/// 0.0001 degrees of latitude is about 11 metres.
void main() {
  final when = DateTime(2026, 10, 1, 8);
  HazardReport report(HazardType type, double lat, double lng) =>
      HazardReport(type: type, position: LatLng(lat, lng), reportedAt: when);

  test('no reports gives no clusters', () {
    expect(HazardCluster.cluster([]), isEmpty);
  });

  test('two same-type reports about 20 m apart become one cluster of 2', () {
    final clusters = HazardCluster.cluster([
      report(HazardType.pothole, 9.6500, 123.8500),
      report(HazardType.pothole, 9.6502, 123.8500),
    ]);
    expect(clusters, hasLength(1));
    expect(clusters.first.count, 2);
  });

  test('same type but about 500 m apart stay separate', () {
    final clusters = HazardCluster.cluster([
      report(HazardType.pothole, 9.6500, 123.8500),
      report(HazardType.pothole, 9.6545, 123.8500),
    ]);
    expect(clusters, hasLength(2));
  });

  test('different types at the same spot are never merged', () {
    final clusters = HazardCluster.cluster([
      report(HazardType.pothole, 9.6500, 123.8500),
      report(HazardType.flooding, 9.6500, 123.8500),
    ]);
    expect(clusters, hasLength(2));
    expect(clusters.map((c) => c.type).toSet(), {HazardType.pothole, HazardType.flooding});
  });

  test('a single report still gets a visible circle (minimum 30 m)', () {
    final clusters = HazardCluster.cluster([report(HazardType.accident, 9.65, 123.85)]);
    expect(clusters.single.radiusMeters, greaterThanOrEqualTo(30));
  });

  test('the threshold is respected: 60 m apart merges at 100 m, not at 30 m', () {
    final pair = [
      report(HazardType.flooding, 9.6500, 123.8500),
      report(HazardType.flooding, 9.65054, 123.8500),
    ];
    expect(HazardCluster.cluster(pair, thresholdMeters: 100), hasLength(1));
    expect(HazardCluster.cluster(pair, thresholdMeters: 30), hasLength(2));
  });
}
