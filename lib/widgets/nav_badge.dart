import 'package:flutter/material.dart';

/// Wraps [child] with a small red circle in the top-right corner showing
/// [count] — the standard "unread messages" badge. Shows nothing at all
/// when count is 0, and caps the printed number at "9+" so it never
/// stretches the badge or overlaps neighboring nav items.
class NavBadge extends StatelessWidget {
  final Widget child;
  final int count;
  const NavBadge({super.key, required this.child, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -6,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xff050505), width: 1.5),
            ),
            child: Text(
              count > 9 ? '9+' : '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, height: 1.2),
            ),
          ),
        ),
      ],
    );
  }
}
