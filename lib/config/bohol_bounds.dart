import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// The area the browsable maps are limited to: the island of Bohol plus a
/// margin (same box as the admin map). Maps that follow your live position
/// are not limited, so the dot is never cut off.
final LatLngBounds kBoholBounds = LatLngBounds(const LatLng(9.45, 123.65), const LatLng(10.20, 124.62));

/// Smallest zoom allowed. The map CENTER stays inside [kBoholBounds], so your own location can always be brought into view.
const double kBoholMinZoom = 10;
