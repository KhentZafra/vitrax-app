import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/activity_provider.dart';
import '../services/connectivity_service.dart';

/// A subtle, non-blocking status strip — per the panel's UX recommendation:
/// no intrusive "No Internet Connection" popup blocking the screen.
/// Instead: an orange indicator while offline, and a brief green
/// checkmark confirmation once back online and synced.
///
/// Drop this once near the top of your main navigation shell (e.g. right
/// above the body in HomeScreen's Scaffold, or wherever wraps all your
/// bottom-nav tabs) so it's visible everywhere, not per-screen.
class OfflineStatusBanner extends StatefulWidget {
  const OfflineStatusBanner({super.key});

  @override
  State<OfflineStatusBanner> createState() => _OfflineStatusBannerState();
}

class _OfflineStatusBannerState extends State<OfflineStatusBanner> {
  bool _offline = false;
  bool _showSyncComplete = false;
  StreamSubscription<bool>? _sub;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _offline = !ConnectivityService().lastKnownOnline;
    _sub = ConnectivityService().onStatusChange.listen((isOnline) {
      if (!mounted) return;
      if (isOnline) {
        // Give syncPending() (triggered elsewhere on the same
        // reconnect event) a moment to actually finish before
        // declaring victory.
        Future.delayed(const Duration(seconds: 2), () async {
          if (!mounted) return;
          await context.read<ActivityProvider>().syncPending();
          if (!mounted) return;
          setState(() {
            _offline = false;
            _showSyncComplete = true;
          });
          _hideTimer?.cancel();
          _hideTimer = Timer(const Duration(seconds: 4), () {
            if (mounted) setState(() => _showSyncComplete = false);
          });
        });
      } else {
        setState(() {
          _offline = true;
          _showSyncComplete = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = context.watch<ActivityProvider>().pendingSyncCount;

    if (!_offline && !_showSyncComplete) return const SizedBox.shrink();

    final isOffline = _offline;
    final label = isOffline
        ? (pendingCount > 0 ? 'Offline Mode Active — $pendingCount saved locally' : 'Offline Mode Active — Local Caching Secure')
        : 'Sync Complete — Community Updated';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      color: isOffline ? const Color(0xff3D2A0A) : const Color(0xff0F2E1A),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isOffline ? Icons.cloud_off : Icons.check_circle, size: 15, color: isOffline ? Colors.orange : Colors.greenAccent),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: isOffline ? Colors.orange.shade200 : Colors.greenAccent.shade100, fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
