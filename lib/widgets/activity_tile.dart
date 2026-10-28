import 'package:flutter/material.dart';
import '../models/activity.dart';

/// Drop-in replacement for the old `recentActivity(...)` helper method —
/// now takes a real [Activity] instead of hardcoded title/subtitle/date.
class ActivityTile extends StatelessWidget {
  final Activity activity;
  final VoidCallback? onTap;

  const ActivityTile({super.key, required this.activity, this.onTap});

  String get _dateLabel {
    final now = DateTime.now();
    final d = activity.startedAt;
    final isToday = now.year == d.year && now.month == d.month && now.day == d.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        yesterday.year == d.year && yesterday.month == d.month && yesterday.day == d.day;

    if (isToday) return 'Today';
    if (isYesterday) return 'Yesterday';
    return '${d.month}/${d.day}';
  }

  String get _subtitle {
    final h = activity.duration.inHours;
    final m = activity.duration.inMinutes.remainder(60);
    final durationLabel = h > 0 ? '${h}h ${m}m' : '${m}min';
    return '${activity.distanceKm.toStringAsFixed(1)} km • $durationLabel';
  }

  IconData get _icon {
    switch (activity.type) {
      case ActivityType.ride:
        return Icons.pedal_bike;
      case ActivityType.run:
        return Icons.directions_run;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xff111111),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xff1f1f1f),
                child: Icon(_icon, color: Colors.blue),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(_subtitle, style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              Text(_dateLabel, style: const TextStyle(color: Colors.grey)),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
