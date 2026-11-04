import 'package:flutter/material.dart';
import '../models/hazard_report.dart';

/// The bottom sheet itself. Nothing about the hazard icons is built or
/// shown until this widget is actually pushed via showModalBottomSheet
/// from RecordScreen's "Report Hazard" button — so the icon grid only
/// appears after that tap, exactly like the design.
Future<HazardType?> showReportHazardSheet(BuildContext context) {
  return showModalBottomSheet<HazardType>(
    context: context,
    backgroundColor: const Color(0xff141414),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => const _ReportHazardSheet(),
  );
}

class _ReportHazardSheet extends StatelessWidget {
  const _ReportHazardSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade700,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Report Hazard',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                      child: const Icon(Icons.close, color: Colors.white70, size: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Select the type of hazard on your route.',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 15),
              ),
              const SizedBox(height: 22),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.85,
                // No Signal is detected automatically while recording, not reported by hand.
                children: HazardType.values
                    .where((type) => type != HazardType.noSignal)
                    .map((type) => _HazardOption(type: type, onTap: () => Navigator.pop(context, type)))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HazardOption extends StatelessWidget {
  final HazardType type;
  final VoidCallback onTap;

  const _HazardOption({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xff1c1c1c),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(shape: BoxShape.circle, color: type.color.withValues(alpha: .18)),
              child: Icon(type.icon, color: type.color, size: 24),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                type.label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
