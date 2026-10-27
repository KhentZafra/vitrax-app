import 'package:flutter/material.dart';

/// Wraps a card that matches the user's chosen activity (Cyclist/Runner)
/// with a blue outline and a small "Your activity" label above it.
class PreferredHighlight extends StatelessWidget {
  final Widget child;
  final String label;
  const PreferredHighlight({super.key, required this.child, this.label = 'Matches your activity'});

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xff1E88FF);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, color: blue, size: 16),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(color: blue, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: blue.withValues(alpha: 0.7), width: 1.2),
            boxShadow: [BoxShadow(color: blue.withValues(alpha: 0.22), blurRadius: 14)],
          ),
          child: child,
        ),
      ],
    );
  }
}
