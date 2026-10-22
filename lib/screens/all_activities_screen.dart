import 'package:flutter/material.dart';
import '../widgets/skeleton_views.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/activity.dart';
import '../providers/activity_provider.dart';
import 'activity_detail_screen.dart';

class _Palette {
  static const background = Color(0xff050505);
  static const card = Color(0xff111111);
  static const cardAlt = Color(0xff1b1b1b);
}

/// Every activity the user has recorded, regardless of date — reached
/// via "See all" on the Recent Activity section of HomeScreen. Grouped
/// by day (Today, Yesterday, then a weekday + date heading), newest
/// first — the same order ActivityProvider already loads activities in.
class AllActivitiesScreen extends StatelessWidget {
  const AllActivitiesScreen({super.key});

  String _dateHeading(DateTime date) {
    final now = DateTime.now();
    final isToday = now.year == date.year && now.month == date.month && now.day == date.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = yesterday.year == date.year && yesterday.month == date.month && yesterday.day == date.day;

    if (isToday) return 'Today';
    if (isYesterday) return 'Yesterday';
    return DateFormat('EEEE, MMM d').format(date);
  }

  /// Groups already-sorted (newest-first) activities by day heading,
  /// preserving that order — a LinkedHashMap-backed literal keeps
  /// insertion order, so headings appear newest-to-oldest without a
  /// separate sort step.
  Map<String, List<Activity>> _groupByDay(List<Activity> activities) {
    final grouped = <String, List<Activity>>{};
    for (final a in activities) {
      final key = _dateHeading(a.startedAt);
      grouped.putIfAbsent(key, () => []).add(a);
    }
    return grouped;
  }

  IconData _iconFor(Activity a) {
    switch (a.type) {
      case ActivityType.run:
        return Icons.directions_run;
      case ActivityType.walk:
        return Icons.directions_walk;
      case ActivityType.ride:
        return Icons.pedal_bike;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.background,
      appBar: AppBar(
        backgroundColor: _Palette.background,
        elevation: 0,
        title: const Text('All Activities', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Consumer<ActivityProvider>(
          builder: (context, provider, _) {
            final activities = provider.allActivities;

            if (provider.isLoading && activities.isEmpty) {
              return const ListSkeleton();
            }

            if (activities.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.directions_bike, color: Colors.grey.shade600, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        'No activities yet',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Everything you record will show up here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              );
            }

            final grouped = _groupByDay(activities);

            return RefreshIndicator(
              onRefresh: provider.loadActivities,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: grouped.entries.expand((entry) {
                  return [
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 10, left: 4),
                      child: Text(
                        entry.key,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    ...entry.value.map(
                      (activity) => _ActivityRow(
                        activity: activity,
                        icon: _iconFor(activity),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ActivityDetailScreen(activity: activity)),
                        ),
                      ),
                    ),
                  ];
                }).toList(),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final Activity activity;
  final IconData icon;
  final VoidCallback onTap;

  const _ActivityRow({required this.activity, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = activity.duration.inHours;
    final m = activity.duration.inMinutes.remainder(60);
    final durationLabel = h > 0 ? '${h}h ${m}m' : '${m}min';
    final timeLabel = DateFormat('h:mm a').format(activity.startedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: _Palette.card, borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: _Palette.cardAlt, child: Icon(icon, color: Colors.blue)),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(activity.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${activity.distanceKm.toStringAsFixed(1)} km • $durationLabel', style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(timeLabel, style: const TextStyle(color: Colors.grey)),
                  if (activity.pendingSync)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(Icons.cloud_off, color: Colors.blue, size: 14),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
