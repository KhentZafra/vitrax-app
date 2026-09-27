import 'package:flutter/material.dart';

/// Temporary screen for sections not built out yet. Community Feed now
/// contains Challenges as a sub-tab (Feed / Challenges) rather than
/// Challenges having its own nav bar slot — that slot is now Routes.
class PlaceholderScreen extends StatelessWidget {
  final String title;
  const PlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    if (title == 'Community Feed') {
      return const _CommunityFeedScreen();
    }

    return Scaffold(
      backgroundColor: const Color(0xff050505),
      appBar: AppBar(backgroundColor: const Color(0xff050505), title: Text(title)),
      body: Center(
        child: Text('$title — coming soon', style: const TextStyle(color: Colors.grey, fontSize: 16)),
      ),
    );
  }
}

class _CommunityFeedScreen extends StatefulWidget {
  const _CommunityFeedScreen();

  @override
  State<_CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends State<_CommunityFeedScreen> {
  int _tabIndex = 0; // 0 = Feed, 1 = Challenges

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff050505),
      appBar: AppBar(backgroundColor: const Color(0xff050505), title: const Text('Community Feed')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(color: const Color(0xff141414), borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(child: _SegmentButton(label: 'Feed', selected: _tabIndex == 0, onTap: () => setState(() => _tabIndex = 0))),
                  Expanded(child: _SegmentButton(label: 'Challenges', selected: _tabIndex == 1, onTap: () => setState(() => _tabIndex = 1))),
                ],
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                _tabIndex == 0 ? 'Community Feed  coming soon' : 'Challenges  coming soon',
                style: const TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(color: selected ? Colors.white : Colors.grey.shade400, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
