import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_unread_provider.dart';
import 'nav_badge.dart';
import 'route_nav_icon.dart';

/// The bottom navigation bar shared by Home, Routes, Community and You:
/// a rounded container with a dot under the selected tab and a glowing
/// Record button in the middle.
/// Indexes: 0 Home, 1 Routes, 2 Record, 3 Community, 4 You.
class AppBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  const AppBottomNav({super.key, required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Container(
      height: 88,
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xff04080c),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xff1d2c3d), width: 1.2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NavTab(icon: Icons.home_rounded, label: 'Home', selected: selectedIndex == 0, onTap: () => onTap(0)),
          _NavTab(customIcon: (color) => RouteNavIcon(color: color, size: 28), label: 'Routes', selected: selectedIndex == 1, onTap: () => onTap(1)),
          _RecordNavTab(onTap: () => onTap(2)),
          Consumer<ChatUnreadProvider>(
            builder: (context, unread, _) => _NavTab(
              icon: Icons.chat_bubble_outline,
              label: 'Community',
              selected: selectedIndex == 3,
              badgeCount: unread.count,
              onTap: () => onTap(3),
            ),
          ),
          _NavTab(icon: Icons.person_outline, label: 'You', selected: selectedIndex == 4, onTap: () => onTap(4)),
        ],
      ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  static const _accent = Color(0xff0a77ff);

  final IconData? icon;
  final Widget Function(Color color)? customIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  const _NavTab({this.icon, this.customIcon, required this.label, required this.selected, required this.onTap, this.badgeCount = 0})
      : assert(icon != null || customIcon != null);

  @override
  Widget build(BuildContext context) {
    final color = selected ? _accent : Colors.grey.shade400;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: (MediaQuery.sizeOf(context).width / 5.2).clamp(48.0, 68.0).toDouble(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            NavBadge(count: badgeCount, child: customIcon != null ? customIcon!(color) : Icon(icon, color: color, size: 28)),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 12)),
            const SizedBox(height: 5),
            Container(width: 5, height: 5, decoration: BoxDecoration(color: selected ? _accent : Colors.transparent, shape: BoxShape.circle)),
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
            offset: const Offset(0, -16),
            child: Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xff1a8cff), Color(0xff0a5cff)]),
                boxShadow: [BoxShadow(color: const Color(0xff0a77ff).withValues(alpha: 0.55), blurRadius: 22)],
              ),
              // Nudged right so the triangle looks centred in the circle.
              child: const Center(child: Padding(padding: EdgeInsets.only(left: 3), child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 38))),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -12),
            child: Text('Record', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
