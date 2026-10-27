import 'package:flutter/material.dart';

/// The app's route icon: three map pins, each standing on an oval base,
/// joined by two connecting lines. Monochrome — takes any colour.
class RouteNavIcon extends StatelessWidget {
  final double size;
  final Color color;
  const RouteNavIcon({super.key, this.size = 24, required this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _RouteIconPainter(color)),
      );
}

/// Drop-in for `Icon(...)`: shows the route icon wherever one of Flutter's
/// stock route icons would have been used, and a normal icon otherwise.
class AppIcon extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double? size;
  const AppIcon(this.icon, {super.key, this.color, this.size});

  @override
  Widget build(BuildContext context) {
    if (icon == Icons.route || icon == Icons.route_outlined || icon == Icons.alt_route) {
      return RouteNavIcon(
        size: size ?? IconTheme.of(context).size ?? 24,
        color: color ?? IconTheme.of(context).color ?? Colors.white,
      );
    }
    return Icon(icon, color: color, size: size);
  }
}

class _RouteIconPainter extends CustomPainter {
  final Color color;
  _RouteIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 1000.0;
    Offset o(double x, double y) => Offset(x * s, y * s);

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 34 * s
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;

    // Connecting lines (under everything else).
    canvas.drawLine(o(320, 375), o(700, 575), stroke);
    canvas.drawLine(o(320, 845), o(700, 645), stroke);

    void base(double cx, double cy) {
      canvas.drawOval(Rect.fromCenter(center: o(cx, cy), width: 250 * s, height: 100 * s), stroke);
    }

    void pin(double cx, double tipY) {
      final headR = 105.0;
      final hc = Offset(cx, tipY - 210);
      final path = Path()
        ..moveTo(cx * s, tipY * s)
        ..cubicTo((cx - 60) * s, (tipY - 60) * s, (cx - headR) * s, (hc.dy + 50) * s, (cx - headR) * s, hc.dy * s)
        ..arcTo(Rect.fromCircle(center: o(cx, hc.dy), radius: headR * s), 3.14159265, 3.14159265, false)
        ..cubicTo((cx + headR) * s, (hc.dy + 50) * s, (cx + 60) * s, (tipY - 60) * s, cx * s, tipY * s)
        ..close();
      canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
      canvas.drawPath(path, fill);
      canvas.drawCircle(o(cx, hc.dy), 55 * s, Paint()..blendMode = BlendMode.clear);
      canvas.restore();
    }

    // Top-left.
    base(205, 358);
    pin(205, 372);
    // Right.
    base(800, 610);
    pin(800, 622);
    // Bottom-left.
    base(205, 868);
    pin(205, 882);
  }

  @override
  bool shouldRepaint(covariant _RouteIconPainter old) => old.color != color;
}
