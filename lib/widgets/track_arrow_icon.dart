import 'package:flutter/material.dart';

/// The app's "track" icon: a solid navigation arrowhead pointing up-right,
/// with a notch cut into its back edge. Drawn with a painter so it takes
/// any colour and size like a normal icon.
class TrackArrowIcon extends StatelessWidget {
  final double size;
  final Color color;
  const TrackArrowIcon({super.key, this.size = 24, required this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _TrackArrowPainter(color)),
      );
}

class _TrackArrowPainter extends CustomPainter {
  final Color color;
  _TrackArrowPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Slight inset so the tips are not clipped.
    final p = Path()
      ..moveTo(w * 0.98, h * 0.02) // tip (up-right)
      ..lineTo(w * 0.02, h * 0.46) // left wing
      ..lineTo(w * 0.40, h * 0.60) // notch
      ..lineTo(w * 0.54, h * 0.98) // bottom wing
      ..close();
    canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = size.width * 0.04,
    );
  }

  @override
  bool shouldRepaint(_TrackArrowPainter old) => old.color != color;
}
