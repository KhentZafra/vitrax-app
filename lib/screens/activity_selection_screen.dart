import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import '../widgets/skeleton_views.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity.dart';
import 'subtype_selection_screen.dart';

class _Palette {
  static const background = Color(0xff050505);
  static const card = Color(0xff111111);
  static const border = Colors.white10;
}

/// Shown right after login. User picks an activity type, which then
/// opens RecordScreen directly.
///
/// Uses the same skeleton-loading + offline-detection pattern as
/// HomeScreen: while the profile name is loading (e.g. slow connection),
/// a shimmering placeholder shows instead of a blank/loading string; if
/// there's no internet at all, an offline banner appears and loading
/// stops gracefully rather than hanging.
class ActivitySelectionScreen extends StatefulWidget {
  /// Set only when reached from "Track" on PlanRouteScreen — a route the
  /// user just found (Safest Itinerary or Direct Route) that still needs
  /// an activity type before recording can start. All three are simply
  /// forwarded through SubtypeSelectionScreen to RecordScreen once an
  /// activity (and then a subtype) is picked.
  final List<GpsPoint>? referenceRoute;
  final String? referenceRouteLabel;
  final Color? referenceRouteColor;

  const ActivitySelectionScreen({
    super.key,
    this.referenceRoute,
    this.referenceRouteLabel,
    this.referenceRouteColor,
  });

  bool get _isTrackingRoute => referenceRoute != null;

  @override
  State<ActivitySelectionScreen> createState() => _ActivitySelectionScreenState();
}

class _ActivitySelectionScreenState extends State<ActivitySelectionScreen> {
  final _supabase = Supabase.instance.client;
  StreamSubscription<List<ConnectivityResult>>? _connectionSub;

  String? _firstName;
  bool _isLoading = true;
  bool _isConnected = true;

  @override
  void initState() {
    super.initState();
    if (widget._isTrackingRoute) {
      // Reached mid-flow from "Track" on a planned route — this isn't
      // the post-login greeting screen here, so skip the profile-name
      // load and offline-banner machinery entirely.
      _isLoading = false;
      return;
    }
    _checkInternet();
    _connectionSub =
        Connectivity().onConnectivityChanged.listen((_) => _checkInternet());
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    super.dispose();
  }

  Future<void> _checkInternet() async {
    final connected = await InternetConnection().hasInternetAccess;
    if (!mounted) return;

    setState(() => _isConnected = connected);

    if (connected) {
      await _loadFirstName();
    } else {
      // No internet — stop the shimmer rather than spinning forever;
      // the offline banner explains why the name isn't loading.
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFirstName() async {
    setState(() => _isLoading = true);

    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final profile = await _supabase
          .from('profiles')
          .select('first_name')
          .eq('id', user.id)
          .single();

      if (!mounted) return;
      setState(() {
        _firstName = profile['first_name'] as String?;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _selectActivity(ActivityType type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubtypeSelectionScreen(
          activityType: type,
          referenceRoute: widget.referenceRoute,
          referenceRouteLabel: widget.referenceRouteLabel,
          referenceRouteColor: widget.referenceRouteColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tracking = widget._isTrackingRoute;

    return Scaffold(
      backgroundColor: _Palette.background,
      appBar: tracking
          ? AppBar(
              backgroundColor: _Palette.background,
              iconTheme: const IconThemeData(color: Colors.white),
              title: const Text('Track Route', style: TextStyle(color: Colors.white)),
            )
          : null,
      body: SafeArea(
        child: DelayedSkeletonizer(
          enabled: _isLoading,
          child: RefreshIndicator(
            onRefresh: tracking ? () async {} : _checkInternet,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!tracking && !_isConnected) _OfflineBanner(onRetry: _checkInternet),
                  if (tracking) ...[
                    Text(
                      'Choose an activity',
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "What are you tracking ${widget.referenceRouteLabel ?? 'this route'} as?",
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
                    ),
                  ] else ...[
                    Text(
                      'Good Day 👋',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isLoading ? 'Loading Name' : '${_firstName ?? 'there'}!',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'What would you like to do today?',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 20),
                    ),
                  ],
                  const SizedBox(height: 32),
                  _ActivityCard(
                    title: 'Cycling',
                    subtitle: 'Track your cycling routes',
                    tags: const ['Road', 'Mountain', 'Gravel'],
                    accentColor: Colors.blue,
                    icon: Icons.pedal_bike,
                    onTap: () => _selectActivity(ActivityType.ride),
                  ),
                  const SizedBox(height: 20),
                                    _ActivityCard(
                    title: 'Running',
                    subtitle: 'Log your running sessions',
                    tags: const ['Road', 'Trail', 'Marathon'],
                    accentColor: const Color(0xff4FC3F7),
                    icon: Icons.directions_run,
                    onTap: () => _selectActivity(ActivityType.run),
                  ),
                  if (!tracking) ...[
                    const SizedBox(height: 24),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false),
                        child: Text(
                          'Not today, just browsing',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const _OfflineBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.red),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "No Internet connection, Please connect it to the internet",
              style: TextStyle(color: Colors.red),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<String> tags;
  final Color accentColor;
  final IconData icon;
  final VoidCallback onTap;

  const _ActivityCard({
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.accentColor,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _Palette.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _Palette.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              height: 68,
              width: 68,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accentColor, accentColor.withValues(alpha: .6)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tags.join(' • '),
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade600, size: 28),
          ],
        ),
      ),
    );
  }
}
