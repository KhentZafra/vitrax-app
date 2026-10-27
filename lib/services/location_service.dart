import 'package:geocoding/geocoding.dart';

/// Turns GPS coordinates into a short, human-readable place name (e.g.
/// "Panglao, Bohol") using the device's native reverse-geocoding APIs
/// via the `geocoding` package.
///
/// REQUIRES: add `geocoding: ^3.0.0` (or the latest version) to
/// pubspec.yaml — this file assumes the package is already present.
/// On Android/iOS the package uses the platform's built-in geocoder, so
/// no separate API key is needed.
class LocationService {
  /// Returns something like "Panglao, Bohol", or null if reverse
  /// geocoding isn't available right now (no result, no connectivity,
  /// or the platform call fails for any reason). Callers should treat
  /// null as "no location available" and simply not show one — never
  /// as an error to surface to the user.
  static Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return null;

      final p = placemarks.first;
      // Vitrax is Bohol-only, so the second part should always read
      // "Bohol" — not the wider region name. On Philippine addresses,
      // `administrativeArea` from this package actually comes back as
      // the *region* ("Central Visayas"), while `subAdministrativeArea`
      // is the *province* ("Bohol"), which is what a Bohol-only app
      // actually wants shown. Falls back to hardcoding "Bohol" if that
      // field ever comes back empty, rather than silently reintroducing
      // the region name.
      final municipality = (p.locality != null && p.locality!.isNotEmpty) ? p.locality! : null;
      final province = (p.subAdministrativeArea != null && p.subAdministrativeArea!.isNotEmpty) ? p.subAdministrativeArea! : 'Bohol';

      final parts = <String>[
        ?municipality,
        province,
      ];

      if (parts.isEmpty) return null;
      return parts.join(', ');
    } catch (_) {
      return null;
    }
  }
}
