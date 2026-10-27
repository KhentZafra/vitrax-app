import 'package:flutter/material.dart';

/// "Leave" icon: an open door with an arrow going out through it.
class LeaveDoorIcon extends StatelessWidget {
  final double size;
  final Color color;
  const LeaveDoorIcon({super.key, this.size = 24, required this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _LeaveDoorPainter(color)),
      );
}

class _LeaveDoorPainter extends CustomPainter {
  final Color color;
  _LeaveDoorPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Offset o(double x, double y) => Offset(w * x, h * y);
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // Open door panel.
    final door = Path()
      ..moveTo(w * 0.04, h * 0.10)
      ..lineTo(w * 0.40, h * 0.10)
      ..lineTo(w * 0.40, h * 0.96)
      ..lineTo(w * 0.04, h * 0.84)
      ..close();
    canvas.drawPath(door, fill);

    // Door frame (top and bottom of the opening).
    canvas.drawPath(
      Path()
        ..moveTo(o(0.40, 0.07).dx, o(0.40, 0.07).dy)
        ..lineTo(w * 0.64, h * 0.07)
        ..lineTo(w * 0.64, h * 0.27),
      line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.64, h * 0.73)
        ..lineTo(w * 0.64, h * 0.93)
        ..lineTo(w * 0.40, h * 0.93),
      line,
    );

    // Arrow leaving the door.
    canvas.drawRect(Rect.fromLTRB(w * 0.46, h * 0.43, w * 0.74, h * 0.57), fill);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.72, h * 0.28)
        ..lineTo(w * 0.98, h * 0.50)
        ..lineTo(w * 0.72, h * 0.72)
        ..close(),
      fill,
    );
  }

  @override
  bool shouldRepaint(_LeaveDoorPainter old) => old.color != color;
}
