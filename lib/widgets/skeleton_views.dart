import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// Placeholder layouts shown while a screen is loading OR while there is no
/// internet, so a screen never shows an empty page or a lone spinner.

/// Rows with an avatar and two lines of text (chats, notifications, lists).
class ListSkeleton extends StatelessWidget {
  final int count;
  const ListSkeleton({super.key, this.count = 8});

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (_, _) => const Row(
          children: [
            CircleAvatar(radius: 24),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Loading name here'),
                  SizedBox(height: 6),
                  Text('Loading a longer line of text for this row'),
                ],
              ),
            ),
            SizedBox(width: 12),
            Text('2h ago'),
          ],
        ),
      ),
    );
  }
}

/// Cards with a title, a line of text and a wide block (challenges, activities).
class CardsSkeleton extends StatelessWidget {
  final int count;
  const CardsSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (_, _) => Card(
          color: const Color(0xff141414),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Loading challenge title'),
                SizedBox(height: 8),
                Text('Loading description text that runs on a little longer'),
                SizedBox(height: 14),
                SizedBox(height: 70, width: double.infinity, child: DecoratedBox(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(12))))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar, name, a row of stat tiles and a couple of cards (profile pages).
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget tile() => const Expanded(
          child: Card(
            color: Color(0xff141414),
            elevation: 0,
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text('00.0'), SizedBox(height: 6), Text('Loading')],
              ),
            ),
          ),
        );
    return Skeletonizer(
      enabled: true,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          const Center(child: CircleAvatar(radius: 46)),
          const SizedBox(height: 14),
          const Center(child: Text('Loading User Name', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
          const SizedBox(height: 6),
          const Center(child: Text('Member since Jan 2026')),
          const SizedBox(height: 22),
          Row(children: [tile(), const SizedBox(width: 10), tile(), const SizedBox(width: 10), tile()]),
          const SizedBox(height: 18),
          const Card(
            color: Color(0xff141414),
            elevation: 0,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Loading section title'),
                  SizedBox(height: 10),
                  Text('Loading some text for this section so it has a shape'),
                  SizedBox(height: 10),
                  Text('Loading some more text here'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Card(
            color: Color(0xff141414),
            elevation: 0,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text('Loading recent activity'), SizedBox(height: 10), Text('Loading details here')],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
