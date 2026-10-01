import 'package:flutter/material.dart';

/// A circular user profile photo, with a graceful fallback to the app's
/// existing "person" placeholder icon when no photo has been set, or if
/// the image fails to load — intentionally matching what every screen
/// already showed before avatars existed, so someone who hasn't set a
/// photo yet sees no visual change at all. Drop-in replacement for the
/// various `CircleAvatar(..., child: Icon(Icons.person, ...))` spots
/// across the app.
class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final double radius;
  final Color backgroundColor;
  final Color iconColor;

  const UserAvatar({
    super.key,
    required this.avatarUrl,
    this.radius = 20,
    this.backgroundColor = const Color(0xff222222),
    this.iconColor = Colors.grey,
  });

  Widget _fallback() {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      child: Icon(Icons.person, color: iconColor, size: radius * 0.95),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    if (url == null || url.isEmpty) return _fallback();

    return ClipOval(
      child: Image.network(
        url,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        // A dead/expired URL or a network hiccup falls back to the same
        // placeholder as "no photo set" — never a broken-image icon or
        // blank circle.
        errorBuilder: (context, error, stackTrace) => _fallback(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _fallback();
        },
      ),
    );
  }
}
