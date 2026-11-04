import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:latlong2/latlong.dart';

import '../config/env.dart';

/// Finds stretches of the route with no mobile data while recording.
///
/// Every [checkEvery] it tries to reach the VITRAX server (a tiny request).
/// After [failsToStart] failed checks in a row it marks the START of a dead
/// zone at the position of the first failed check. It then adds up the
/// distance travelled. When the server is reachable again it marks the END,
/// and if the stretch was at least [minLengthMeters] long it reports it.
///
/// Distances come from the GPS track, so they are approximate (roughly the
/// distance travelled in [checkEvery] more or less at each end).
class DeadZoneTracker {
  static const checkEvery = Duration(seconds: 10);
  static const failsToStart = 2;
  static const minLengthMeters = 100.0;

  final void Function(LatLng start, LatLng end, double lengthMeters) onDeadZone;
  DeadZoneTracker({required this.onDeadZone});

  Timer? _timer;
  bool _checking = false;
  bool _paused = false;
  LatLng? _lastPos;
  LatLng? _firstFailPos;
  int _fails = 0;

  // Set while inside a dead zone.
  LatLng? _zoneStart;
  LatLng? _zoneLast;
  double _zoneMeters = 0;

  bool get inDeadZone => _zoneStart != null;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(checkEvery, (_) => _check());
  }

  void pause(bool paused) => _paused = paused;

  /// Call with every accepted GPS point of the recording.
  void onPosition(LatLng p) {
    _lastPos = p;
    if (_zoneStart != null) {
      final last = _zoneLast;
      if (last != null) {
        _zoneMeters += Geolocator.distanceBetween(last.latitude, last.longitude, p.latitude, p.longitude);
      }
      _zoneLast = p;
    }
  }

  Future<void> _check() async {
    if (_checking || _paused) return;
    _checking = true;
    try {
      final ok = await _reachable();
      final pos = _lastPos;
      if (ok) {
        if (_zoneStart != null && pos != null && _zoneMeters >= minLengthMeters) {
          onDeadZone(_zoneStart!, pos, _zoneMeters);
        }
        _fails = 0;
        _firstFailPos = null;
        _zoneStart = null;
        _zoneLast = null;
        _zoneMeters = 0;
      } else {
        _fails++;
        _firstFailPos ??= pos;
        if (_fails >= failsToStart && _zoneStart == null && _firstFailPos != null) {
          _zoneStart = _firstFailPos;
          _zoneLast = pos;
          _zoneMeters = pos == null
              ? 0
              : Geolocator.distanceBetween(_firstFailPos!.latitude, _firstFailPos!.longitude, pos.latitude, pos.longitude);
        }
      }
    } finally {
      _checking = false;
    }
  }

  /// True if the server answers at all (any HTTP response counts).
  static Future<bool> _reachable() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.headUrl(Uri.parse('${Env.supabaseUrl}/auth/v1/health')).timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 4));
      await res.drain<void>();
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _zoneStart = null;
    _firstFailPos = null;
  }
}
