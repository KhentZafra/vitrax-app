
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/achievement.dart';
import '../models/activity.dart';
import '../providers/activity_provider.dart';
import '../services/badge_service.dart';
import '../services/community_impact_service.dart';
import '../widgets/route_nav_icon.dart';
import '../widgets/user_avatar.dart';
import 'activity_detail_screen.dart';
import 'all_activities_screen.dart';
import 'community_feed_screen.dart';
import 'edit_profile_screen.dart';
import 'routes_screen.dart';

/// Real Profile screen. Structured as Overview / Activities / Achievements
/// tabs to match the target design, but every number shown is backed by
/// something the app actually tracks:
///  - Overview: activity count, lifetime distance & time (ActivityProvider),
///    a preview of Recent Activities, and the Community Impact summary.
///  - Activities: the full activity list, filterable by type.
///  - Achievements: the real tier/score system from CommunityImpactService
///    (peer-verified hazard/obstacle actions — see that service for why
///    this isn't a raw self-reported count). A "Badges" section is shown
///    as an honest coming-soon state rather than fabricated unlocks,
///    since there's no achievements/badges backend yet.
/// There's deliberately no fake percentile ("Top 5%"), points total, or
/// elevation/calorie stats — nothing in the data model tracks those.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

enum _ProfileTab { overview, activities, achievements }

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;

  String _name = '';
  String _email = '';
  String? _memberSince;
  String? _avatarUrl;
  CommunityImpactStats? _stats;
  Map<String, int>? _badgeStats;
  bool _isLoading = true;

  _ProfileTab _tab = _ProfileTab.overview;
  ActivityType? _activityFilter; // null = All, for the Activities tab

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final profile = await _supabase.from('profiles').select('first_name, last_name, avatar_url').eq('id', user.id).maybeSingle();
      final first = profile?['first_name'] as String? ?? '';
      final last = profile?['last_name'] as String? ?? '';
      _name = ('$first $last').trim();
      _avatarUrl = profile?['avatar_url'] as String?;
    } catch (_) {
      _name = '';
    }

    _email = user.email ?? '';

    // Supabase's auth User carries its own createdAt — real account
    // creation date, no extra table needed.
    try {
      _memberSince = DateFormat('MMM yyyy').format(DateTime.parse(user.createdAt));
    } catch (_) {
      _memberSince = null;
    }

    _stats = await CommunityImpactService.fetchStats(user.id);
    _badgeStats = await BadgeService.fetchStats();
    BadgeService.check();

    // Make sure ActivityProvider has data to show even if this is the
    // first screen visited this session.
    if (mounted) {
      await context.read<ActivityProvider>().loadActivities();
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff141414),
        title: const Text('Sign out?', style: TextStyle(color: Colors.white)),
        content: const Text('You can sign back in any time.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign Out', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _openEditProfile() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
    );
    if (changed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff050505),
      bottomNavigationBar: _buildBottomNav(),
      appBar: AppBar(
        backgroundColor: const Color(0xff050505),
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        title: const Text('My Profile', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Opens right under the gear (a dropdown), not as a bottom sheet.
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            color: const Color(0xff141414),
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (value) {
              if (value == 'edit') _openEditProfile();
              if (value == 'signout') _signOut();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit_outlined, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Text('Edit Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ]),
              ),
              PopupMenuItem(
                value: 'signout',
                child: Row(children: [
                  Icon(Icons.logout, color: Colors.red, size: 20),
                  SizedBox(width: 12),
                  Text('Sign Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : RefreshIndicator(
              onRefresh: _load,
              child: Consumer<ActivityProvider>(
                builder: (context, provider, _) {
                  final activities = provider.allActivities;
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 24),
                        _buildTabRow(),
                        const SizedBox(height: 20),
                        if (_tab == _ProfileTab.overview) _buildOverviewTab(activities),
                        if (_tab == _ProfileTab.activities) _buildActivitiesTab(activities),
                        if (_tab == _ProfileTab.achievements) _buildAchievementsTab(),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }

  // ---------- Bottom nav (Home / Routes / Record / Community / You) ----------
  //
  // You/Profile is the currently-selected tab here.

  void _navigateFromNav(int index) {
    const currentIndex = 4; // You
    if (index == currentIndex) return;

    switch (index) {
      case 0:
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
        break;
      case 1:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const RoutesScreen()));
        break;
      case 2:
        Navigator.of(context).pushNamedAndRemoveUntil('/activitySelection', (route) => false);
        break;
      case 3:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityFeedScreen()));
        break;
    }
  }

  Widget _buildBottomNav() {
    return Container(
      height: 90,
      padding: const EdgeInsets.only(top: 6),
      decoration: const BoxDecoration(color: Colors.black, border: Border(top: BorderSide(color: Colors.white10))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NavTab(icon: Icons.home_rounded, label: 'Home', selected: false, onTap: () => _navigateFromNav(0)),
          _NavTab(customIcon: (color) => RouteNavIcon(color: color), label: 'Routes', selected: false, onTap: () => _navigateFromNav(1)),
          _RecordNavTab(onTap: () => _navigateFromNav(2)),
          _NavTab(icon: Icons.chat_bubble_outline, label: 'Community', selected: false, onTap: () => _navigateFromNav(3)),
          _NavTab(icon: Icons.person_outline, label: 'You', selected: true, onTap: () => _navigateFromNav(4)),
        ],
      ),
    );
  }

  // ---------- Header ----------

  Color get _tierColor {
    final tier = _stats?.tier;
    switch (tier) {
      case SafetyTier.trustedContributor:
        return const Color(0xff2F6FED);
      case SafetyTier.safetyGuardian:
        return const Color(0xffFB8C00);
      case SafetyTier.elite:
        return const Color(0xff9B59B6);
      case SafetyTier.newReporter:
      case null:
        return Colors.grey;
    }
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UserAvatar(
          avatarUrl: _avatarUrl,
          radius: 38,
          backgroundColor: Colors.blue.withValues(alpha: .15),
          iconColor: Colors.blue,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _name.isEmpty ? 'Vitrax user' : _name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (_stats != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: _tierColor, borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.workspace_premium, color: Colors.white, size: 12),
                          const SizedBox(width: 4),
                          Text(_stats!.tier.label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(_email, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              if (_memberSince != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, color: Colors.grey.shade600, size: 13),
                    const SizedBox(width: 6),
                    Text('Member since $_memberSince', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ---------- Tabs ----------

  Widget _buildTabRow() {
    Widget tab(_ProfileTab t, String label, IconData icon) {
      final selected = _tab == t;
      final color = selected ? Colors.blue : Colors.grey.shade500;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = t),
          child: Column(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
              const SizedBox(height: 8),
              Container(height: 2, color: selected ? Colors.blue : Colors.transparent),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
      child: Row(
        children: [
          tab(_ProfileTab.overview, 'Overview', Icons.person_outline),
          tab(_ProfileTab.activities, 'Activities', Icons.directions_run),
          tab(_ProfileTab.achievements, 'Achievements', Icons.emoji_events_outlined),
        ],
      ),
    );
  }

  // ---------- Overview ----------

  Widget _buildOverviewTab(List<Activity> activities) {
    final totalDistance = activities.fold(0.0, (sum, a) => sum + a.distanceKm);
    final totalDuration = activities.fold(Duration.zero, (sum, a) => sum + a.duration);
    final recent = activities.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('OVERVIEW', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: .5)),
        const SizedBox(height: 4),
        Text('Your journey at a glance.', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _OverviewStat(
                icon: Icons.flag_outlined,
                iconColor: Colors.blue,
                value: '${activities.length}',
                label: 'Activities\nCompleted',
              ),
            ),
            Expanded(
              child: _OverviewStat(
                icon: Icons.map_outlined,
                iconColor: Colors.greenAccent,
                value: totalDistance.toStringAsFixed(1),
                label: 'Total\nKm',
              ),
            ),
            Expanded(
              child: _OverviewStat(
                icon: Icons.access_time,
                iconColor: Colors.blue,
                value: '${totalDuration.inHours}h ${totalDuration.inMinutes.remainder(60)}m',
                label: 'Total\nTime',
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        if (_stats != null) _CommunityImpactCard(stats: _stats!),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Recent Activities', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AllActivitiesScreen())),
              child: const Text('View All', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No activities yet.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ),
          )
        else
          ...recent.map((a) => _ActivityCard(activity: a, onTap: () => _openDetail(a))),
      ],
    );
  }

  // ---------- Activities ----------

  Widget _buildActivitiesTab(List<Activity> all) {
    final filtered = _activityFilter == null ? all : all.where((a) => a.type == _activityFilter).toList();

    Widget chip(String label, ActivityType? type) {
      final selected = _activityFilter == type;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => setState(() => _activityFilter = type),
          backgroundColor: const Color(0xff141414),
          selectedColor: Colors.blue,
          labelStyle: TextStyle(color: selected ? Colors.white : Colors.grey.shade400, fontSize: 13, fontWeight: FontWeight.w600),
          side: BorderSide(color: selected ? Colors.blue : Colors.white10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Activities', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text('Your recent activities and journey.', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              chip('All', null),
              chip('Cycling', ActivityType.ride),
              chip('Running', ActivityType.run),
              
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No activities in this category.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ),
          )
        else
          ...filtered.map((a) => _ActivityCard(activity: a, onTap: () => _openDetail(a))),
      ],
    );
  }

  void _openDetail(Activity a) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityDetailScreen(activity: a)));
  }

  // ---------- Achievements ----------

  Widget _buildAchievementsTab() {
    final stats = _stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Achievements', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text('Your real, peer-verified community standing.', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        const SizedBox(height: 16),
        if (stats != null) _CommunityImpactCard(stats: stats),
        const SizedBox(height: 28),
        const Text('Badges', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text('Earned automatically as you ride, finish challenges and keep the map safe.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.05,
          children: _badgeStats != null && _badgeStats!.isNotEmpty
              ? BadgeService.buildBadges(_badgeStats!).map((b) => _BadgeCard(badge: b)).toList()
              : List.generate(BadgeService.defs.length, (_) => const _LockedBadgeSlot()),
        ),
      ],
    );
  }
}

class _OverviewStat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _OverviewStat({required this.icon, required this.iconColor, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(color: const Color(0xff141414), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 11, height: 1.2)),
        ],
      ),
    );
  }
}

IconData _activityIcon(ActivityType type) {
  switch (type) {
    case ActivityType.run:
      return Icons.directions_run;
    case ActivityType.walk:
      return Icons.directions_walk;
    case ActivityType.ride:
      return Icons.pedal_bike;
  }
}

class _ActivityCard extends StatelessWidget {
  final Activity activity;
  final VoidCallback onTap;
  const _ActivityCard({required this.activity, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = activity.duration.inHours;
    final m = activity.duration.inMinutes.remainder(60);
    final durationLabel = h > 0 ? '${h}h ${m}m' : '${m}min';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xff141414), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: activity.route.length > 1
                      ? _MiniRouteSketch(points: activity.route)
                      : Container(
                          color: const Color(0xff0b0b0b),
                          child: Icon(_activityIcon(activity.type), color: Colors.grey.shade700, size: 20),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            activity.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (activity.shared)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: Colors.blue.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
                            child: const Text('Shared', style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('MMM d, y · h:mm a').format(activity.startedAt),
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.route_outlined, color: Colors.grey.shade500, size: 13),
                        const SizedBox(width: 4),
                        Text('${activity.distanceKm.toStringAsFixed(1)} km', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                        const SizedBox(width: 12),
                        Icon(Icons.access_time, color: Colors.grey.shade500, size: 13),
                        const SizedBox(width: 4),
                        Text(durationLabel, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: Colors.grey.shade600, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small abstract route sketch for list tiles — a lightweight
/// CustomPainter rather than a real map, same technique used on the
/// Routes screen's cards.
class _MiniRouteSketch extends StatelessWidget {
  final List<GpsPoint> points;
  const _MiniRouteSketch({required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xff0b0b0b),
      child: CustomPaint(painter: _MiniRoutePainter(points), child: const SizedBox.expand()),
    );
  }
}

class _MiniRoutePainter extends CustomPainter {
  final List<GpsPoint> points;
  _MiniRoutePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final lats = points.map((p) => p.lat);
    final lngs = points.map((p) => p.lng);
    final minLat = lats.reduce((a, b) => a < b ? a : b);
    final maxLat = lats.reduce((a, b) => a > b ? a : b);
    final minLng = lngs.reduce((a, b) => a < b ? a : b);
    final maxLng = lngs.reduce((a, b) => a > b ? a : b);

    final latRange = (maxLat - minLat).abs() < 0.0001 ? 0.0001 : (maxLat - minLat);
    final lngRange = (maxLng - minLng).abs() < 0.0001 ? 0.0001 : (maxLng - minLng);

    const padding = 6.0;
    Offset project(GpsPoint p) {
      final x = padding + ((p.lng - minLng) / lngRange) * (size.width - padding * 2);
      final y = size.height - padding - ((p.lat - minLat) / latRange) * (size.height - padding * 2);
      return Offset(x, y);
    }

    final path = Path()..moveTo(project(points.first).dx, project(points.first).dy);
    for (final p in points.skip(1)) {
      final o = project(p);
      path.lineTo(o.dx, o.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.blue
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniRoutePainter oldDelegate) => oldDelegate.points != points;
}

class _BadgeCard extends StatelessWidget {
  final AchievementBadge badge;
  const _BadgeCard({required this.badge});

  void _showDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xff141414),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: badge.tier.color.withValues(alpha: .15), shape: BoxShape.circle),
                    child: Icon(badge.icon, color: badge.isLocked ? Colors.grey.shade600 : badge.tier.color, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(badge.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(badge.tier.label, style: TextStyle(color: badge.isLocked ? Colors.grey.shade500 : badge.tier.color, fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(badge.description, style: TextStyle(color: Colors.grey.shade400, fontSize: 13, height: 1.4)),
              const SizedBox(height: 14),
              if (badge.remainingToNextTier != null)
                Text('${badge.remainingToNextTier} more to reach the next tier.', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))
              else
                const Text("You've reached the top tier on this badge.", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locked = badge.isLocked;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showDetail(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xff141414),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: locked ? Colors.white10 : badge.tier.color.withValues(alpha: .4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(badge.icon, color: locked ? Colors.grey.shade700 : badge.tier.color, size: 26),
            const Spacer(),
            Text(badge.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
              locked ? 'Locked' : badge.tier.label,
              style: TextStyle(color: locked ? Colors.grey.shade600 : badge.tier.color, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockedBadgeSlot extends StatelessWidget {
  const _LockedBadgeSlot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xff141414), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white10)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, color: Colors.grey.shade700, size: 22),
          const SizedBox(height: 6),
          Text('Locked', style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
        ],
      ),
    );
  }
}

class _CommunityImpactCard extends StatelessWidget {
  final CommunityImpactStats stats;
  const _CommunityImpactCard({required this.stats});

  Color get _tierColor {
    switch (stats.tier) {
      case SafetyTier.newReporter:
        return Colors.grey;
      case SafetyTier.trustedContributor:
        return const Color(0xff2F6FED);
      case SafetyTier.safetyGuardian:
        return const Color(0xffFB8C00);
      case SafetyTier.elite:
        return const Color(0xff2ECC71);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xff141414), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Community Impact', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Stats only count actions other users have independently confirmed.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _StatTile(icon: Icons.verified_outlined, label: 'Hazards\nVerified', value: '${stats.hazardsVerified}', color: Colors.blue)),
              Expanded(child: _StatTile(icon: Icons.cleaning_services_outlined, label: 'Obstacles\nCleared', value: '${stats.obstaclesCleared}', color: Colors.blue)),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _tierColor.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Icon(Icons.shield, color: _tierColor, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Community Safety Score', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                      Text(stats.tier.label, style: TextStyle(color: _tierColor, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                if (stats.scoreToNextTier > 0)
                  Text('+${stats.scoreToNextTier} to next', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatTile({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .15)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 11, height: 1.2)),
      ],
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
