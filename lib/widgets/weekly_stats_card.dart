import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/activity_provider.dart';

/// Drop-in replacement for the hardcoded "This Week" container in
/// home_screen.dart. Reads live weekly totals from ActivityProvider.
class WeeklyStatsCard extends StatelessWidget {
  const WeeklyStatsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ActivityProvider>(
      builder: (context, provider, _) {
        final loading = provider.isLoading;
        final distance = provider.weeklyDistanceKm;
        final time = provider.formattedWeeklyTime;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xff111111),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This Week',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 25),
              Row(
                children: [
                  Expanded(
                    child: _StatColumn(
                      icon: Icons.trending_up,
                      iconColor: Colors.blue,
                      value: loading ? '000.0' : distance.toStringAsFixed(1),
                      unit: 'km',
                      label: 'Distance',
                    ),
                  ),
                  Container(height: 120, width: 1, color: Colors.white10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: _StatColumn(
                        icon: Icons.timer_outlined,
                        iconColor: Colors.greenAccent,
                        value: loading ? '00h 00m' : time,
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
      },
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
        Icon(icon, color: iconColor),
        const SizedBox(height: 15),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 42,
          ),
        ),
        if (unit != null) Text(unit!, style: const TextStyle(color: Colors.blue)),
        const SizedBox(height: 15),
        Text(label, style: TextStyle(color: Colors.grey.shade500)),
      ],
    );
  }
}
