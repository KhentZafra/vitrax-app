import 'package:flutter/material.dart';

/// Custom nav-bar icon: two map pins joined by a winding route line —
/// a smaller pin at the bottom-left (start) connected to a larger pin
/// at the top-right (destination). Monochrome, matching how every other
/// nav icon behaves — grey when unselected, blue when selected — rather
/// than a fixed multi-color look.
class RouteNavIcon extends StatelessWidget {
  final double size;
  final Color color;
  const RouteNavIcon({super.key, this.size = 24, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _RouteIconPainter(color)),
    );
  }
}

class _RouteIconPainter extends CustomPainter {
  final Color color;
  _RouteIconPainter(this.color);

  /// A classic teardrop map-pin: a circular head with a pointed tip
  /// hanging below it, drawn solid and centered on [tipAnchor] — where
  /// [tipAnchor] is the pin's bottom point (so pins of different sizes
  /// still line up with the connecting road at the right spot).
  Path _pinPath(Offset tipAnchor, double headRadius) {
    final headCenter = Offset(tipAnchor.dx, tipAnchor.dy - headRadius * 2.1);
    final path = Path();
    // Two bezier curves from the tip up to each side of the head, plus
    // the head's own circle — together these read as one solid teardrop
    // rather than a circle-plus-triangle stuck together.
    path.moveTo(tipAnchor.dx, tipAnchor.dy);
    path.cubicTo(
      tipAnchor.dx - headRadius * 1.15,
      tipAnchor.dy - headRadius * 1.35,
      headCenter.dx - headRadius,
      headCenter.dy + headRadius * 0.55,
      headCenter.dx - headRadius,
      headCenter.dy,
    );
    path.arcTo(Rect.fromCircle(center: headCenter, radius: headRadius), 3.14159, 3.14159, false);
    path.cubicTo(
      headCenter.dx + headRadius,
      headCenter.dy + headRadius * 0.55,
      tipAnchor.dx + headRadius * 1.15,
      tipAnchor.dy - headRadius * 1.35,
      tipAnchor.dx,
      tipAnchor.dy,
    );
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final startTip = Offset(w * 0.20, h * 0.70);
    final startHeadRadius = w * 0.15;
    final endTip = Offset(w * 0.80, h * 0.42);
    final endHeadRadius = w * 0.15;

    // Wavy connecting road, drawn UNDER the pins so it visually tucks
    // behind each pin's tip rather than overlapping on top of it.
    final road = Path()
      ..moveTo(startTip.dx, startTip.dy - h * 0.04)
      ..cubicTo(w * 0.42, h * 0.98, w * 0.30, h * 0.58, w * 0.52, h * 0.62)
      ..cubicTo(w * 0.74, h * 0.66, w * 0.58, h * 0.40, endTip.dx, endTip.dy + h * 0.02);

    canvas.drawPath(
      road,
      Paint()
        ..color = color
        ..strokeWidth = w * 0.09
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Larger destination pin first, then the smaller start pin on top,
    // matching the layering in the reference icon — drawn inside one
    // layer so the "hole" punched below can clear through to the
    // transparent background instead of a solid pin drawn underneath.
    final holePaint = Paint()..blendMode = BlendMode.clear;
    canvas.saveLayer(Rect.fromLTWH(0, 0, w, h), Paint());
    canvas.drawPath(_pinPath(endTip, endHeadRadius), fill);
    canvas.drawPath(_pinPath(startTip, startHeadRadius), fill);
    canvas.drawCircle(Offset(endTip.dx, endTip.dy - endHeadRadius * 2.1), endHeadRadius * 0.45, holePaint);
    canvas.drawCircle(Offset(startTip.dx, startTip.dy - startHeadRadius * 2.1), startHeadRadius * 0.45, holePaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RouteIconPainter oldDelegate) => oldDelegate.color != color;
}
