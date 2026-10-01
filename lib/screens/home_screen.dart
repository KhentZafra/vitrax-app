import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity.dart';
import '../providers/activity_provider.dart';
import 'activity_detail_screen.dart';
import 'all_activities_screen.dart';
import 'community_feed_screen.dart';
import 'routes_screen.dart';
import '../widgets/route_nav_icon.dart';
import '../widgets/user_avatar.dart';
import 'profile_screen.dart';

class _Palette {
  static const background = Color(0xff050505);
  static const card = Color(0xff111111);
  static const cardAlt = Color(0xff1b1b1b);
  static const border = Colors.white10;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;
  late final StreamSubscription<List<ConnectivityResult>> _connectionSub;

  String _fullName = 'Loading Username';
  String? _avatarUrl;
  bool _isLoadingProfile = true;
  bool _isConnected = true;

  @override
  void initState() {
    super.initState();
    _checkInternet();
    _connectionSub =
        Connectivity().onConnectivityChanged.listen((_) => _checkInternet());
  }

  @override
  void dispose() {
    _connectionSub.cancel();
    super.dispose();
  }

  Future<void> _checkInternet() async {
    final connected = await InternetConnection().hasInternetAccess;
    if (!mounted) return;

    setState(() => _isConnected = connected);

    if (connected) {
      // Load profile and activities in parallel — This Week / Recent
      // Activity both come from ActivityProvider, which HomeScreen reads
      // via Consumer below.
      await Future.wait([
        _loadUserProfile(),
        context.read<ActivityProvider>().loadActivities(),
      ]);
    } else {
      setState(() => _isLoadingProfile = false);
    }
  }

  Future<void> _loadUserProfile() async {
    setState(() => _isLoadingProfile = true);

    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() => _isLoadingProfile = false);
      return;
    }

    try {
      final profile = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      if (!mounted) return;
      setState(() {
        _fullName = '${profile['first_name']} ${profile['last_name']}';
        _avatarUrl = profile['avatar_url'] as String?;
        _isLoadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingProfile = false);

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Unable to load profile.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ---------- Navigation ----------

  void _openGpsRecording() {
    Navigator.pushNamed(context, '/activitySelection');
  }

  void _openCommunityFeed() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityFeedScreen()));
  }

  void _openProfile() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
  }

  void _openAllActivities() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AllActivitiesScreen()));
  }

  void _openActivityDetail(Activity activity) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityDetailScreen(activity: activity)));
  }

  void _navigateFromNav(int index) {
    const currentIndex = 0; // Home
    if (index == currentIndex) return;

    switch (index) {
      case 1:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const RoutesScreen()));
        break;
      case 2:
        _openGpsRecording();
        break;
      case 3:
        _openCommunityFeed();
        break;
      case 4:
        _openProfile();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.background,
      bottomNavigationBar: _buildBottomNav(),
      body: SafeArea(
        child: Consumer<ActivityProvider>(
          builder: (context, activityProvider, _) {
            final isLoading = _isLoadingProfile || activityProvider.isLoading;

            return Skeletonizer(
              enabled: isLoading,
              child: RefreshIndicator(
                onRefresh: () async {
                  await Future.wait([
                    _loadUserProfile(),
                    activityProvider.loadActivities(),
                  ]);
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_isConnected) _OfflineBanner(onRetry: _checkInternet),
                      _buildGreeting(),
                      const SizedBox(height: 24),
                      _buildWeeklyStatsCard(activityProvider, isLoading),
                      const SizedBox(height: 28),
                      _buildSectionTitle('Quick Access'),
                      const SizedBox(height: 18),
                      _buildQuickAccessRow(),
                      const SizedBox(height: 28),
                      _buildSectionHeaderRow('Recent Activity', onSeeAll: _openAllActivities),
                      const SizedBox(height: 14),
                      _buildRecentActivity(activityProvider, isLoading),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ---------- Sections ----------

  Widget _buildGreeting() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Good morning 👋',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                _isLoadingProfile ? 'Loading Username' : _fullName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: _openProfile,
          borderRadius: BorderRadius.circular(26),
          child: UserAvatar(avatarUrl: _avatarUrl, radius: 26, backgroundColor: _Palette.cardAlt),
        ),
      ],
    );
  }

  /// Real weekly distance/time from ActivityProvider. If the user has no
  /// activities this week (or ever), this naturally shows 0.0 km / 0h 0m
  /// — no fabricated numbers.
  Widget _buildWeeklyStatsCard(ActivityProvider provider, bool isLoading) {
    final distance = provider.weeklyDistanceKm;
    final time = provider.formattedWeeklyTime;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This Week',
            style: TextStyle(
              color: Colors.blue,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _StatColumn(
                  icon: Icons.trending_up,
                  iconColor: Colors.blue,
                  value: isLoading ? '000.0' : distance.toStringAsFixed(1),
                  unit: 'km',
                  label: 'Distance',
                ),
              ),
              Container(height: 90, width: 1, color: _Palette.border),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: _StatColumn(
                    icon: Icons.timer_outlined,
                    iconColor: Colors.greenAccent,
                    value: isLoading ? '00h 00m' : time,
                    unit: null,
                    label: 'Total Time',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAccessRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _QuickAccessButton(icon: Icons.gps_fixed, label: 'GPS', onTap: _openGpsRecording),
        _QuickAccessButton(icon: Icons.person, label: 'Profile', onTap: _openProfile),
        _QuickAccessButton(icon: Icons.route, label: 'Routes', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoutesScreen()))),
        _QuickAccessButton(icon: Icons.people, label: 'Community', onTap: _openCommunityFeed),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildSectionHeaderRow(String title, {required VoidCallback onSeeAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildSectionTitle(title),
        TextButton(
          onPressed: onSeeAll,
          child: const Text('See all', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  /// Real recent activities from ActivityProvider. If there are none yet,
  /// shows a friendly empty state instead of hardcoded sample tiles.
  Widget _buildRecentActivity(ActivityProvider provider, bool isLoading) {
    if (isLoading) {
      // Skeletonizer needs *something* to shimmer — two placeholder-shaped
      // tiles while loading, replaced by real data (or the empty state)
      // once loading finishes.
      return Column(
        children: const [
          _RecentActivityTile(title: 'Loading Activity', subtitle: '00.0 km • 00m', date: '—'),
          _RecentActivityTile(title: 'Loading Activity', subtitle: '00.0 km • 00m', date: '—'),
        ],
      );
    }

    final recent = provider.recentActivities(limit: 5);

    if (recent.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: _Palette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _Palette.border),
        ),
        child: Column(
          children: [
            Icon(Icons.directions_bike, color: Colors.grey.shade600, size: 36),
            const SizedBox(height: 12),
            Text(
              'No activities yet',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap GPS above to record your first ride or run.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      children: recent.map((activity) {
        final h = activity.duration.inHours;
        final m = activity.duration.inMinutes.remainder(60);
        final durationLabel = h > 0 ? '${h}h ${m}m' : '${m}min';
        return _RecentActivityTile(
          title: activity.title,
          subtitle: '${activity.distanceKm.toStringAsFixed(1)} km • $durationLabel',
          date: _relativeDateLabel(activity.startedAt),
          onTap: () => _openActivityDetail(activity),
        );
      }).toList(),
    );
  }

  String _relativeDateLabel(DateTime date) {
    final now = DateTime.now();
    final isToday = now.year == date.year && now.month == date.month && now.day == date.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = yesterday.year == date.year && yesterday.month == date.month && yesterday.day == date.day;

    if (isToday) return 'Today';
    if (isYesterday) return 'Yesterday';
    return DateFormat('MMM d').format(date);
  }

  // ---------- Bottom nav (Home / Challenges / Record / Feed / You) ----------

  Widget _buildBottomNav() {
    return Container(
      height: 90,
      padding: const EdgeInsets.only(top: 6),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NavTab(icon: Icons.home_rounded, label: 'Home', selected: true, onTap: () => _navigateFromNav(0)),
          _NavTab(customIcon: (color) => RouteNavIcon(color: color), label: 'Routes', selected: false, onTap: () => _navigateFromNav(1)),
          _RecordNavTab(onTap: () => _navigateFromNav(2)),
          _NavTab(icon: Icons.chat_bubble_outline, label: 'Community', selected: false, onTap: () => _navigateFromNav(3)),
          _NavTab(icon: Icons.person_outline, label: 'You', selected: false, onTap: () => _navigateFromNav(4)),
        ],
      ),
    );
  }
}

/// Small offline notice shown at the top when there's no internet access.
/// Includes a Retry button that re-runs the same connectivity + data
/// load flow as pull-to-refresh, so the user isn't stuck waiting for
/// the next automatic connectivity change event.
class _OfflineBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const _OfflineBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.orange),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "You're offline. Showing available data.",
              style: TextStyle(color: Colors.orange),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String? unit;
  final String label;

  const _StatColumn({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.unit,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(height: 12),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28),
        ),
        if (unit != null) Text(unit!, style: const TextStyle(color: Colors.blue, fontSize: 13)),
        const SizedBox(height: 10),
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
      ],
    );
  }
}

class _QuickAccessButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _QuickAccessButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Column(
        children: [
          Container(
            height: 64,
            width: 64,
            decoration: BoxDecoration(
              color: _Palette.card,
              shape: BoxShape.circle,
              border: Border.all(color: _Palette.border),
            ),
            child: Icon(icon, color: Colors.blue, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
        ],
      ),
    );
  }
}

class _RecentActivityTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String date;
  final VoidCallback? onTap;

  const _RecentActivityTile({
    required this.title,
    required this.subtitle,
    required this.date,
    this.onTap,
  });

  IconData get _icon {
    if (title.toLowerCase().contains('run')) return Icons.directions_run;
    if (title.toLowerCase().contains('walk')) return Icons.directions_walk;
    return Icons.pedal_bike;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _Palette.card, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              CircleAvatar(radius: 20, backgroundColor: _Palette.cardAlt, child: Icon(_icon, color: Colors.blue, size: 18)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                  ],
                ),
              ),
              Text(date, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: Colors.grey.shade600, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final IconData? icon;
  final Widget Function(Color color)? customIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({this.icon, this.customIcon, required this.label, required this.selected, required this.onTap})
      : assert(icon != null || customIcon != null);

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.blueAccent : Colors.grey;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            customIcon != null ? customIcon!(color) : Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _RecordNavTab extends StatelessWidget {
  final VoidCallback onTap;
  const _RecordNavTab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            offset: const Offset(0, -6),
            child: Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.blueAccent),
              // Nudged 2px right so the triangle's visual center (its
              // bulk sits left of its bounding box) lines up with the
              // circle's actual center instead of looking off-balance.
              child: const Center(child: Padding(padding: EdgeInsets.only(left: 2), child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30))),
            ),
          ),
          const Text('Record', style: TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }
}
