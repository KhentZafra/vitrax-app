import 'dart:math';

import 'package:flutter/material.dart';

/// A classic map "pin" marker — a teardrop shape with a hollow white
/// center ring — used everywhere a route's destination / end point is
/// shown (plan a route, recording a tracked route, viewing a shared
/// route). Distinct from [UserLocationDot], which marks the user's own
/// live position rather than a fixed destination.
///
/// Built from two overlapping shapes (a circle for the bulb, a rotated
/// square for the point) instead of a custom painter, so it stays
/// simple and renders identically everywhere it's used.
class MapPinMarker extends StatelessWidget {
  final double size;
  final Color color;
  final Color outlineColor;

  const MapPinMarker({
    super.key,
    this.size = 36,
    this.color = const Color(0xffE53935), // matches the reference pin design
    this.outlineColor = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    final bulbSize = size * 0.72;
    final pointSize = size * 0.4;
    final outlineWidth = (size * 0.06).clamp(1.5, 3.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: bulbSize * 0.52,
            child: Transform.rotate(
              angle: pi / 4,
              child: Container(
                width: pointSize,
                height: pointSize,
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(color: outlineColor, width: outlineWidth),
                ),
              ),
            ),
          ),
          Container(
            width: bulbSize,
            height: bulbSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: outlineColor, width: outlineWidth),
            ),
            child: Center(
              child: Container(
                width: bulbSize * 0.42,
                height: bulbSize * 0.42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: outlineColor, width: outlineWidth * 0.85),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The user's own live/current location on a map — a plain filled red
/// circle with a white ring, distinct from [MapPinMarker] (used for a
/// fixed destination, route end point, or another user's position).
class UserLocationDot extends StatelessWidget {
  final double size;
  final Color color;

  const UserLocationDot({super.key, this.size = 24, this.color = const Color(0xffE53935)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: max(2, size * 0.12)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .35), blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
    );
  }
}
