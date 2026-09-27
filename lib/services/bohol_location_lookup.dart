import 'dart:math' as math;

/// Coarse "which town is this in" lookup for Bohol, done entirely
/// offline via nearest-municipality-center matching — no geocoding API
/// or key needed, which fits neatly since every activity in this app is
/// necessarily within Bohol anyway.
///
/// This is deliberately approximate: matching against a municipality's
/// center point, not its actual boundary polygon. For labeling a route
/// card ("Panglao, Bohol") that's more than precise enough — it's not
/// used for anything requiring exact administrative boundaries.
class BoholLocationLookup {
  static const _municipalities = [
    ('Tagbilaran City', 9.6472, 123.8547),
    ('Panglao', 9.579, 123.745),
    ('Dauis', 9.6167, 123.7667),
    ('Baclayon', 9.6227, 123.9135),
    ('Corella', 9.6833, 123.8833),
    ('Cortes', 9.65, 123.85),
    ('Maribojoc', 9.7333, 123.8333),
    ('Loon', 9.7833, 123.8),
    ('Antequera', 9.7812, 123.8975),
    ('Calape', 9.8833, 123.8833),
    ('Tubigon', 9.95, 123.9333),
    ('Clarin', 9.97, 124.02),
    ('Inabanga', 10.0333, 124.0667),
    ('Loboc', 9.6333, 124.0333),
    ('Bilar', 9.7, 124.1),
    ('Sikatuna', 9.6667, 123.95),
    ('Balilihan', 9.75, 123.95),
    ('Sagbayan', 9.9, 124.0167),
    ('Batuan', 9.75, 124.1167),
    ('Carmen', 9.8167, 124.1667),
    ('Jagna', 9.65, 124.3667),
    ('Anda', 9.75, 124.5667),
    ('Candijay', 9.8167, 124.45),
    ('Guindulman', 9.7667, 124.4167),
    ('Duero', 9.7, 124.3833),
    ('Valencia', 9.65, 124.2833),
    ('Dimiao', 9.6833, 124.15),
    ('Lila', 9.65, 124.0833),
    ('Loay', 9.6333, 124.0167),
    ('Alicia', 9.9167, 124.2),
    ('Talibon', 10.15, 124.3167),
    ('Ubay', 10.05, 124.4667),
    ('Trinidad', 10.05, 124.3333),
    ('Danao', 9.9667, 124.15),
    ('Pilar', 9.83, 124.33),
    ('Garcia Hernandez', 9.6667, 124.2333),
    ('Getafe', 10.1333, 124.15),
    ('San Isidro', 9.8, 124.3),
    ('Buenavista', 10.15, 124.1333),
  ];

  /// Nearest municipality to (lat, lng), formatted as "Name, Bohol" —
  /// matching the label style used elsewhere in the app.
  static String labelFor(double lat, double lng) {
    var bestName = 'Bohol';
    var bestDistance = double.infinity;

    for (final (name, mLat, mLng) in _municipalities) {
      final distance = _roughDistance(lat, lng, mLat, mLng);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestName = name;
      }
    }

    return '$bestName, Bohol';
  }

  /// Squared-degree distance is fine here — we only need relative
  /// ordering (which center is closest), not an actual distance value,
  /// so there's no need for haversine's extra cost.
  static double _roughDistance(double lat1, double lng1, double lat2, double lng2) {
    final dLat = lat1 - lat2;
    final dLng = lng1 - lng2;
    return math.sqrt(dLat * dLat + dLng * dLng);
  }
}
