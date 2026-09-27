import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Thin wrapper around connectivity_plus exposing a simple online/offline
/// stream. Note: this reports network *reachability* (WiFi/mobile radio
/// is on and connected to something), not "Supabase is definitely
/// reachable" — a captive portal or a paused Supabase project can still
/// cause requests to fail even when this reports online. Callers (like
/// ActivityProvider's sync) still need their own try/catch regardless.
class ConnectivityService {
  static final _instance = ConnectivityService._();
  factory ConnectivityService() => _instance;
  ConnectivityService._();

  final _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _lastKnownOnline = true;

  bool get lastKnownOnline => _lastKnownOnline;

  /// Emits true when transitioning to online, false when transitioning
  /// to offline. Call [start] once (e.g. from main.dart or the root
  /// widget's initState) before listening.
  Stream<bool> get onStatusChange => _controller.stream;

  void start() {
    _sub?.cancel();
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline != _lastKnownOnline) {
        _lastKnownOnline = isOnline;
        _controller.add(isOnline);
      }
    });
  }

  Future<bool> checkNow() async {
    final results = await _connectivity.checkConnectivity();
    _lastKnownOnline = results.any((r) => r != ConnectivityResult.none);
    return _lastKnownOnline;
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
