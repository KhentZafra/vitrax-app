import 'package:flutter/material.dart';

/// Flat gold trophy drawn in code (no image asset, so it stays sharp at any size).
class TrophyIcon extends StatelessWidget {
  final double size;
  const TrophyIcon({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _TrophyPainter()));
}

class _TrophyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    Offset o(double x, double y) => Offset(x * s, y * s);
    final gold = Paint()..color = const Color(0xffF9B90F);
    final goldLight = Paint()..color = const Color(0xffFCCB0B);
    final goldDark = Paint()..color = const Color(0xffF3A20A);
    final dark = Paint()..color = const Color(0xff26221f);
    final darker = Paint()..color = const Color(0xff1b1b1b);
    final plate = Paint()..color = const Color(0xffEBDBA6);

    // handles
    final handle = Paint()
      ..color = const Color(0xffF9B90F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2 * s
      ..strokeJoin = StrokeJoin.round;
    final hl = Path()
      ..moveTo(26 * s, 20 * s)
      ..lineTo(15 * s, 20 * s)
      ..quadraticBezierTo(15 * s, 38 * s, 33 * s, 47 * s);
    final hr = Path()
      ..moveTo(74 * s, 20 * s)
      ..lineTo(85 * s, 20 * s)
      ..quadraticBezierTo(85 * s, 38 * s, 67 * s, 47 * s);
    canvas.drawPath(hl, handle);
    canvas.drawPath(hr, handle);

    // cup (left half darker, right half lighter)
    final cupL = Path()
      ..moveTo(50 * s, 10 * s)
      ..lineTo(27 * s, 10 * s)
      ..lineTo(27 * s, 28 * s)
      ..quadraticBezierTo(29 * s, 52 * s, 50 * s, 60 * s)
      ..close();
    final cupR = Path()
      ..moveTo(50 * s, 10 * s)
      ..lineTo(73 * s, 10 * s)
      ..lineTo(73 * s, 28 * s)
      ..quadraticBezierTo(71 * s, 52 * s, 50 * s, 60 * s)
      ..close();
    canvas.drawPath(cupL, gold);
    canvas.drawPath(cupR, goldLight);
    canvas.drawRect(Rect.fromLTRB(27 * s, 10 * s, 73 * s, 12.5 * s), goldDark);

    // shine
    final shine = Path()
      ..moveTo(33 * s, 15 * s)
      ..lineTo(37.5 * s, 15 * s)
      ..quadraticBezierTo(38 * s, 40 * s, 47 * s, 52 * s)
      ..quadraticBezierTo(35 * s, 44 * s, 33 * s, 15 * s)
      ..close();
    canvas.drawPath(shine, Paint()..color = Colors.white);

    // stem + foot
    final stem = Path()
      ..moveTo(44 * s, 60 * s)
      ..lineTo(56 * s, 60 * s)
      ..quadraticBezierTo(54 * s, 72 * s, 58 * s, 80 * s)
      ..lineTo(42 * s, 80 * s)
      ..quadraticBezierTo(46 * s, 72 * s, 44 * s, 60 * s)
      ..close();
    canvas.drawPath(stem, gold);
    canvas.drawRRect(RRect.fromLTRBR(36 * s, 79 * s, 64 * s, 83.5 * s, Radius.circular(1.5 * s)), gold);

    // base
    canvas.drawRect(Rect.fromLTRB(32 * s, 83.5 * s, 68 * s, 93 * s), dark);
    canvas.drawRect(Rect.fromLTRB(42 * s, 85.5 * s, 58 * s, 90.5 * s), plate);
    canvas.drawRect(Rect.fromLTRB(28 * s, 93 * s, 72 * s, 97 * s), darker);

    // sparkles
    final sp = Paint()..color = Colors.white;
    void spark(double x, double y, double r) {
      final p = Path()
        ..moveTo(x * s, (y - r) * s)
        ..quadraticBezierTo(x * s, y * s, (x + r) * s, y * s)
        ..quadraticBezierTo(x * s, y * s, x * s, (y + r) * s)
        ..quadraticBezierTo(x * s, y * s, (x - r) * s, y * s)
        ..quadraticBezierTo(x * s, y * s, x * s, (y - r) * s)
        ..close();
      canvas.drawPath(p, sp);
    }
    spark(63, 30, 6);
    spark(68, 20, 3.5);
    spark(56, 20, 2.5);
    spark(45, 72, 3);
    o(0, 0);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
