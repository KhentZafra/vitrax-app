import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  Widget skeletonPost() {
    return Card(
      color: const Color(0xff1A1A1A),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [

            Row(
              children: [

                CircleAvatar(radius: 24),

                SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      Text("Loading User"),

                      SizedBox(height: 6),

                      Text("2 hours ago"),

                    ],
                  ),
                ),

              ],
            ),

            SizedBox(height: 18),

            Text(
              "Loading Loading Loading Loading Loading Loading Loading Loading",
            ),

            SizedBox(height: 16),

            AspectRatio(
              aspectRatio: 16 / 9,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(
                    Radius.circular(12),
                  ),
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          skeletonPost(),

          skeletonPost(),

          skeletonPost(),

        ],
      ),
    );
  }
}