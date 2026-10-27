import '../widgets/route_nav_icon.dart';
import '../widgets/track_arrow_icon.dart';
import '../services/badge_service.dart';
import '../services/feed_notification_service.dart';
import '../services/table_watcher.dart';
import 'feed_notifications_screen.dart';
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../widgets/skeleton_views.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity.dart';
import '../providers/activity_provider.dart';
import 'activity_detail_screen.dart';
import 'all_activities_screen.dart';
import 'community_feed_screen.dart';
import 'routes_screen.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/user_avatar.dart';
import 'profile_screen.dart';

class _Palette {
  static const background = Color(0xff020507);
  static const card = Color(0xff070b10);
  static const cardAlt = Color(0xff0e1620);
  static const tile = Color(0xff081018);
  static const border = Color(0xff14202c);
  static const accent = Color(0xff0a77ff);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;
  late final StreamSubscription<List<ConnectivityResult>> _connectionSub;

  // Remembered between visits so coming back to Home shows instantly.
  static String? _cachedName;
  static String? _cachedAvatar;

  String _fullName = _cachedName ?? 'Loading Username';
  String? _avatarUrl = _cachedAvatar;
  bool _isLoadingProfile = _cachedName == null;
  bool _isConnected = true;
  int _notifCount = 0;
  TableWatcher? _notifWatcher;
  String _filter = 'all'; // all | ride | run | walk (This Week card)

  @override
  void initState() {
    super.initState();
    _checkInternet();
    // Anything earned while away (e.g. someone confirmed your hazard)?
    WidgetsBinding.instance.addPostFrameCallback((_) => BadgeService.check());
    _connectionSub =
        Connectivity().onConnectivityChanged.listen((_) => _checkInternet());
    _refreshNotifCount();
    final me = _supabase.auth.currentUser?.id;
    if (me != null) {
      _notifWatcher = TableWatcher(_refreshNotifCount, debounce: const Duration(milliseconds: 300))
        ..watch('feed_notifications', event: PostgresChangeEvent.insert, filterColumn: 'user_id', filterValue: me);
    }
  }

  Future<void> _refreshNotifCount() async {
    final n = await FeedNotificationService.unreadCount();
    if (!mounted) return;
    setState(() => _notifCount = n);
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FeedNotificationsScreen(items: const [], onCommentCount: (_, _) {})),
    );
    if (mounted) _refreshNotifCount();
  }

  @override
  void dispose() {
    _connectionSub.cancel();
    _notifWatcher?.dispose();
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
    if (_cachedName == null) setState(() => _isLoadingProfile = true);

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
        _cachedName = _fullName;
        _cachedAvatar = _avatarUrl;
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
      extendBody: true, // content shows behind the floating nav bar
      bottomNavigationBar: _buildBottomNav(),
      body: SafeArea(
        bottom: false,
        child: Consumer<ActivityProvider>(
          builder: (context, activityProvider, _) {
            final isLoading = _isLoadingProfile || (activityProvider.isLoading && activityProvider.allActivities.isEmpty);

            return DelayedSkeletonizer(
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
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_isConnected) _OfflineBanner(onRetry: _checkInternet),
                      _buildGreeting(),
                      const SizedBox(height: 26),
                      _buildWeeklyStatsCard(activityProvider, isLoading),
                      const SizedBox(height: 30),
                      _buildSectionTitle('Quick Access'),
                      const SizedBox(height: 16),
                      _buildQuickAccessRow(),
                      const SizedBox(height: 30),
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

  String get _greetingWord {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _circleButton({required Widget child, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(color: _Palette.cardAlt, shape: BoxShape.circle, border: Border.all(color: _Palette.border)),
        child: Center(child: child),
      ),
    );
  }

  Widget _buildGreeting() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$_greetingWord 👋', style: TextStyle(color: Colors.grey.shade400, fontSize: 19)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _isLoadingProfile ? 'Loading Username' : _fullName,
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white, height: 1.15),
                ),
              ),
              const SizedBox(height: 2),
              Text("Keep moving, you're doing great!", style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _circleButton(
          onTap: _openNotifications,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 24),
              if (_notifCount > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(9)),
                    child: Text(_notifCount > 99 ? '99+' : '$_notifCount', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _circleButton(
          onTap: _openProfile,
          child: ClipOval(child: UserAvatar(avatarUrl: _avatarUrl, radius: 22, backgroundColor: _Palette.cardAlt)),
        ),
      ],
    );
  }

  List<Activity> _weekList(ActivityProvider p, {required bool lastWeek}) {
    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final startLast = startOfWeek.subtract(const Duration(days: 7));
    return p.allActivities.where((a) {
      if (_filter != 'all' && a.type.value != _filter) return false;
      return lastWeek ? (a.startedAt.isAfter(startLast) && a.startedAt.isBefore(startOfWeek)) : a.startedAt.isAfter(startOfWeek);
    }).toList();
  }

  String get _filterLabel {
    switch (_filter) {
      case 'ride':
        return 'Cycling';
      case 'run':
        return 'Running';
      case 'walk':
        return 'Walking';
      default:
        return 'All Activities';
    }
  }

  Widget _filterPill() {
    return PopupMenuButton<String>(
      onSelected: (v) => setState(() => _filter = v),
      color: _Palette.cardAlt,
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'all', child: Text('All Activities', style: TextStyle(color: Colors.white))),
        PopupMenuItem(value: 'ride', child: Text('Cycling', style: TextStyle(color: Colors.white))),
        PopupMenuItem(value: 'run', child: Text('Running', style: TextStyle(color: Colors.white))),
        PopupMenuItem(value: 'walk', child: Text('Walking', style: TextStyle(color: Colors.white))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xff0c1624), borderRadius: BorderRadius.circular(20), border: Border.all(color: _Palette.border)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_filterLabel, style: const TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _delta(double current, double previous) {
    final has = previous > 0;
    final pct = has ? ((current - previous) / previous * 100).round() : 0;
    final up = pct >= 0;
    final color = has ? (up ? _Palette.accent : Colors.redAccent) : Colors.grey.shade600;
    return Row(
      children: [
        Icon(has ? (up ? Icons.north_east_rounded : Icons.south_east_rounded) : Icons.remove, color: color, size: 16),
        const SizedBox(width: 4),
        Text(has ? '${up ? '+' : ''}$pct%' : '—', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
      ],
    );
  }

  Widget _statBlock({required String label, required String value, String? unit, required double current, required double previous}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 15)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 40, height: 1.1)),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(unit, style: TextStyle(color: Colors.grey.shade300, fontSize: 20)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        _delta(current, previous),
        const SizedBox(height: 2),
        Text('vs last week', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
      ],
    );
  }

  Widget _weekBars(List<Activity> week) {
    final bars = List<double>.filled(7, 0);
    for (final a in week) {
      bars[(a.startedAt.weekday - 1).clamp(0, 6)] += a.distanceKm;
    }
    final maxBar = bars.fold<double>(0, (m, v) => v > m ? v : m);
    final today = DateTime.now().weekday - 1;
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return SizedBox(
      width: 104,
      height: 112,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < 7; i++)
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (i == today)
                  Container(width: 6, height: 6, margin: const EdgeInsets.only(bottom: 4), decoration: const BoxDecoration(color: _Palette.accent, shape: BoxShape.circle)),
                Container(
                  width: 11,
                  height: maxBar <= 0 ? 22 : 22 + (bars[i] / maxBar) * 52,
                  decoration: BoxDecoration(
                    color: i == today ? _Palette.accent : (bars[i] > 0 ? const Color(0xff06274f) : const Color(0xff0f1922)),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: i == today ? [BoxShadow(color: _Palette.accent.withValues(alpha: 0.5), blurRadius: 10)] : null,
                  ),
                ),
                const SizedBox(height: 8),
                Text(letters[i], style: TextStyle(color: i == today ? _Palette.accent : Colors.grey.shade600, fontSize: 12)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildWeeklyStatsCard(ActivityProvider provider, bool isLoading) {
    final week = _weekList(provider, lastWeek: false);
    final prev = _weekList(provider, lastWeek: true);
    final dist = week.fold<double>(0, (s, a) => s + a.distanceKm);
    final prevDist = prev.fold<double>(0, (s, a) => s + a.distanceKm);
    final dur = week.fold<Duration>(Duration.zero, (s, a) => s + a.duration);
    final prevDur = prev.fold<Duration>(Duration.zero, (s, a) => s + a.duration);
    final timeLabel = '${dur.inHours}h ${dur.inMinutes.remainder(60)}m';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xff0a1018), Color(0xff05080c)]),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xff16222f)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('This Week', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: _Palette.accent, size: 26),
              const Spacer(),
              _filterPill(),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _statBlock(
                  label: 'Distance',
                  value: isLoading ? '000.0' : dist.toStringAsFixed(1),
                  unit: 'km',
                  current: dist,
                  previous: prevDist,
                ),
              ),
              Container(height: 110, width: 1, color: _Palette.border),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: _statBlock(
                    label: 'Total Time',
                    value: isLoading ? '00h 00m' : timeLabel,
                    current: dur.inSeconds.toDouble(),
                    previous: prevDur.inSeconds.toDouble(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _weekBars(week),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAccessRow() {
    return Row(
      children: [
        Expanded(child: _QuickAccessButton(icon: Icons.gps_fixed, trackIcon: true, label: 'GPS', subtitle: 'Start tracking', onTap: _openGpsRecording)),
        const SizedBox(width: 10),
        Expanded(child: _QuickAccessButton(icon: Icons.person, label: 'Profile', subtitle: 'View stats', onTap: _openProfile)),
        const SizedBox(width: 10),
        Expanded(child: _QuickAccessButton(icon: Icons.route, label: 'Routes', subtitle: 'Explore', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoutesScreen())))),
        const SizedBox(width: 10),
        Expanded(child: _QuickAccessButton(icon: Icons.people, label: 'Community', subtitle: 'Join events', onTap: _openCommunityFeed)),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800));
  }

  Widget _buildSectionHeaderRow(String title, {required VoidCallback onSeeAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildSectionTitle(title),
        InkWell(
          onTap: onSeeAll,
          borderRadius: BorderRadius.circular(8),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('See all', style: TextStyle(color: _Palette.accent, fontSize: 16, fontWeight: FontWeight.w600)),
                Icon(Icons.chevron_right, color: _Palette.accent, size: 22),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Real recent activities from ActivityProvider. If there are none yet,
  /// shows a friendly empty state instead of hardcoded sample tiles.
  Widget _buildRecentActivity(ActivityProvider provider, bool isLoading) {
    if (isLoading) {
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
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _Palette.border),
        ),
        child: Column(
          children: [
            Icon(Icons.directions_bike, color: Colors.grey.shade600, size: 36),
            const SizedBox(height: 12),
            Text('No activities yet', style: TextStyle(color: Colors.grey.shade400, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Tap GPS above to record your first ride or run.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ],
        ),
      );
    }

    return Column(
      children: recent.map((activity) {
        final h = activity.duration.inHours;
        final m = activity.duration.inMinutes.remainder(60);
        final durationLabel = h > 0 ? '${h}h ${m}m' : '$m min';
        return _RecentActivityTile(
          title: activity.title,
          subtitle: '${activity.distanceKm.toStringAsFixed(1)} km • $durationLabel',
          date: _dateLabel(activity.startedAt),
          route: activity.route,
          onTap: () => _openActivityDetail(activity),
        );
      }).toList(),
    );
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final isToday = now.year == date.year && now.month == date.month && now.day == date.day;
    final time = DateFormat('h:mm a').format(date);
    if (isToday) return 'Today, $time';
    final yesterday = now.subtract(const Duration(days: 1));
    if (yesterday.year == date.year && yesterday.month == date.month && yesterday.day == date.day) return 'Yesterday, $time';
    return '${DateFormat('MMM d, yyyy').format(date)} • $time';
  }

  // ---------- Bottom nav (Home / Routes / Record / Community / You) ----------

  Widget _buildBottomNav() => AppBottomNav(selectedIndex: 0, onTap: _navigateFromNav);
}

/// Small offline notice shown at the top when there's no internet access.
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
            child: Text("No Internet connection, Please connect it to the internet", style: TextStyle(color: Colors.red)),
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

class _QuickAccessButton extends StatelessWidget {
  final IconData icon;
  final bool trackIcon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;

  const _QuickAccessButton({required this.icon, this.trackIcon = false, required this.label, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
        decoration: BoxDecoration(
          color: _Palette.tile,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _Palette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            trackIcon
                ? const TrackArrowIcon(color: _Palette.accent, size: 30)
                : AppIcon(icon, color: _Palette.accent, size: 34),
            const SizedBox(height: 12),
            FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
            const SizedBox(height: 3),
            FittedBox(fit: BoxFit.scaleDown, child: Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12))),
          ],
        ),
      ),
    );
  }
}

class _RecentActivityTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String date;
  final List<GpsPoint> route;
  final VoidCallback? onTap;

  const _RecentActivityTile({
    required this.title,
    required this.subtitle,
    required this.date,
    this.route = const [],
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
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          decoration: BoxDecoration(
            color: _Palette.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _Palette.border),
          ),
          child: Row(
            children: [
              CircleAvatar(radius: 28, backgroundColor: const Color(0xff0b141e), child: Icon(_icon, color: _Palette.accent, size: 28)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade400, fontSize: 15)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time, color: Colors.grey.shade500, size: 14),
                        const SizedBox(width: 5),
                        Flexible(child: Text(date, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade500, fontSize: 13))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(width: 84, height: 62, child: CustomPaint(painter: _RouteThumbPainter(route))),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade600, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiny map-style preview of an activity's recorded route.
class _RouteThumbPainter extends CustomPainter {
  final List<GpsPoint> route;
  const _RouteThumbPainter(this.route);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xff0c131b));
    final grid = Paint()
      ..color = const Color(0xff1a2634)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(Offset(0, size.height * i / 4), Offset(size.width, size.height * i / 4 + 6 * (i.isEven ? 1 : -1)), grid);
      canvas.drawLine(Offset(size.width * i / 4, 0), Offset(size.width * i / 4 - 5, size.height), grid);
    }
    if (route.length < 2) return;

    var minLat = route.first.lat, maxLat = route.first.lat, minLng = route.first.lng, maxLng = route.first.lng;
    for (final p in route) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
    const pad = 10.0;
    final w = size.width - pad * 2, h = size.height - pad * 2;
    final spanLng = (maxLng - minLng).abs() < 1e-9 ? 1e-9 : (maxLng - minLng);
    final spanLat = (maxLat - minLat).abs() < 1e-9 ? 1e-9 : (maxLat - minLat);
    final scale = (w / spanLng) < (h / spanLat) ? (w / spanLng) : (h / spanLat);
    final offX = pad + (w - spanLng * scale) / 2;
    final offY = pad + (h - spanLat * scale) / 2;
    Offset at(GpsPoint p) => Offset(offX + (p.lng - minLng) * scale, offY + (maxLat - p.lat) * scale);

    // Sample at most ~120 points so long routes stay cheap to draw.
    final step = (route.length / 120).ceil().clamp(1, route.length).toInt();
    final path = Path()..moveTo(at(route.first).dx, at(route.first).dy);
    for (var i = step; i < route.length; i += step) {
      final o = at(route[i]);
      path.lineTo(o.dx, o.dy);
    }
    final end = at(route.last);
    path.lineTo(end.dx, end.dy);

    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = const Color(0xff0a77ff).withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xff2b8cff));
    final start = at(route.first);
    for (final o in [start, end]) {
      canvas.drawCircle(o, 4.5, Paint()..color = const Color(0xff0a77ff));
      canvas.drawCircle(o, 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _RouteThumbPainter old) => old.route != route;
}

/// Forget remembered Home data (called on sign-out).
void clearHomeCache() {
  _HomeScreenState._cachedName = null;
  _HomeScreenState._cachedAvatar = null;
}
