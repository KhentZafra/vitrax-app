import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/achievement.dart';

/// A metallic medal for one badge. The higher the tier, the more ornate it
/// gets: bronze is a dialled ring, silver adds sparkles, gold adds a laurel
/// wreath, platinum a crowning star, diamond a gem and light rays, and elite
/// a crown, a double ring and the most sparkle. Colours follow the tier.
class BadgeMedal extends StatelessWidget {
  final BadgeTier tier;
  final IconData icon;
  final double size;
  final bool showLabel;

  const BadgeMedal({super.key, required this.tier, required this.icon, this.size = 150, this.showLabel = false});

  @override
  Widget build(BuildContext context) {
    final locked = tier == BadgeTier.none;
    final p = _Palette.of(tier);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size.square(size), painter: _MedalPainter(tier, p)),
          Icon(icon, color: locked ? Colors.grey.shade700 : p.hi, size: size * .30),
          if (showLabel && !locked)
            Positioned(
              bottom: size * .1,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: size * .08, vertical: size * .022),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [p.hi, p.mid, p.lo]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .5), blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Text(tier.label.toUpperCase(),
                    style: TextStyle(color: Colors.black, fontSize: size * .075, fontWeight: FontWeight.w900, letterSpacing: .8)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Palette {
  final Color hi, mid, lo;
  const _Palette(this.hi, this.mid, this.lo);

  static _Palette of(BadgeTier t) {
    if (t == BadgeTier.none) return _Palette(Colors.grey.shade600, Colors.grey.shade700, Colors.grey.shade900);
    final base = t.color;
    final hsl = HSLColor.fromColor(base);
    Color shade(double l, [double s = 0]) =>
        hsl.withLightness((hsl.lightness + l).clamp(0.05, 0.92)).withSaturation((hsl.saturation + s).clamp(0.0, 1.0)).toColor();
    return _Palette(shade(.28, -.1), base, shade(-.28, .05));
  }
}

class _MedalPainter extends CustomPainter {
  final BadgeTier tier;
  final _Palette p;
  _MedalPainter(this.tier, this.p);

  int get _lv => tier.index; // 0 locked, 1 bronze .. 6 elite

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * (_lv >= 3 ? .27 : .31); // ring radius; wreath needs room
    final locked = _lv == 0;

    // glow
    canvas.drawCircle(
      c,
      r * 1.7,
      Paint()
        ..shader = RadialGradient(colors: [p.mid.withValues(alpha: locked ? 0 : .30), p.mid.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r * 1.7)),
    );

    // light rays (diamond, elite)
    if (_lv >= 5) {
      final n = _lv == 6 ? 24 : 16;
      final rp = Paint()
        ..color = p.hi.withValues(alpha: .28)
        ..strokeWidth = size.width * .006
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < n; i++) {
        final a = 2 * math.pi * i / n;
        canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * (r * 1.32), c + Offset(math.cos(a), math.sin(a)) * (r * (i.isEven ? 1.62 : 1.5)), rp);
      }
    }

    // laurel wreath (gold and up)
    if (_lv >= 3) _wreath(canvas, c, r, size.width);

    // outer ring (metal)
    final ringW = r * .22;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringW
      ..shader = SweepGradient(
        transform: const GradientRotation(-math.pi / 4),
        colors: [p.hi, p.mid, p.lo, p.mid, p.hi, p.mid, p.lo, p.hi],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, ring);
    if (_lv == 6) {
      canvas.drawCircle(
        c,
        r * 1.16,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringW * .35
          ..color = p.hi.withValues(alpha: .85),
      );
    }

    // inner disc
    final inner = r - ringW / 2;
    canvas.drawCircle(
      c,
      inner,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.3, -.35),
          colors: [Color.lerp(p.lo, Colors.black, .35)!, const Color(0xff0b0b0e)],
        ).createShader(Rect.fromCircle(center: c, radius: inner)),
    );
    canvas.drawCircle(
      c,
      inner * .86,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .004
        ..color = p.mid.withValues(alpha: .55),
    );

    // dial ticks (bronze, silver)
    if (_lv >= 1 && _lv <= 2) {
      final tp = Paint()
        ..color = p.hi.withValues(alpha: .75)
        ..strokeWidth = size.width * .005
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 48; i++) {
        final a = 2 * math.pi * i / 48;
        final long = i % 4 == 0;
        final o = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(c + o * (inner * .95), c + o * (inner * (long ? .84 : .89)), tp);
      }
    }

    // glint
    if (!locked) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        math.pi * 1.05,
        math.pi * .32,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringW * .45
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: .55),
      );
    }

    // crown piece on top
    if (_lv == 4) _star(canvas, c + Offset(0, -r * 1.42), size.width * .06, p.hi);
    if (_lv == 5) _gem(canvas, c + Offset(0, -r * 1.38), size.width * .06);
    if (_lv == 6) _crown(canvas, c + Offset(0, -r * 1.36), size.width * .09);

    // sparkles
    final spots = <Offset>[
      const Offset(-1.25, -.85), const Offset(1.3, -.1), const Offset(-1.05, .7), const Offset(1.1, .95),
      const Offset(.2, -1.5), const Offset(-1.45, -.05), const Offset(.95, -1.1), const Offset(-.4, 1.45),
    ];
    final count = const [0, 0, 3, 4, 5, 6, 8][_lv];
    for (var i = 0; i < count; i++) {
      _star(canvas, c + spots[i] * r, size.width * (i.isEven ? .035 : .024), Colors.white.withValues(alpha: .9), tint: p.hi);
    }
  }

  void _wreath(Canvas canvas, Offset c, double r, double w) {
    final leaves = _lv >= 5 ? 8 : 6;
    final len = r * (_lv >= 6 ? .5 : .42);
    final fill = Paint()
      ..shader = LinearGradient(colors: [p.hi, p.mid, p.lo]).createShader(Rect.fromCircle(center: c, radius: r * 1.5));
    for (final side in [-1.0, 1.0]) {
      for (var i = 0; i < leaves; i++) {
        // from the bottom, curling up each side
        final t = i / (leaves - 1);
        final ang = math.pi / 2 + side * (math.pi * .22 + t * math.pi * .62);
        final pos = c + Offset(math.cos(ang), math.sin(ang)) * (r * 1.2);
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(ang + (side < 0 ? -math.pi / 2 : math.pi / 2) + side * -.35);
        final path = Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(len * .42, -len * .5, 0, -len)
          ..quadraticBezierTo(-len * .42, -len * .5, 0, 0);
        canvas.drawPath(path, fill);
        canvas.restore();
      }
    }
  }

  Path _starPath(Offset c, double r, double inner) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      final rr = i.isEven ? r : r * inner;
      final o = c + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    return path..close();
  }

  void _star(Canvas canvas, Offset c, double r, Color color, {Color? tint}) {
    canvas.drawCircle(c, r * 1.6, Paint()..color = (tint ?? color).withValues(alpha: .18));
    canvas.drawPath(_starPath(c, r, .22), Paint()..color = color);
  }

  void _gem(Canvas canvas, Offset c, double r) {
    final path = Path()
      ..moveTo(c.dx - r, c.dy - r * .25)
      ..lineTo(c.dx - r * .55, c.dy - r * .85)
      ..lineTo(c.dx + r * .55, c.dy - r * .85)
      ..lineTo(c.dx + r, c.dy - r * .25)
      ..lineTo(c.dx, c.dy + r)
      ..close();
    canvas.drawPath(path, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, p.hi, p.mid]).createShader(path.getBounds()));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: .7));
  }

  void _crown(Canvas canvas, Offset c, double r) {
    final path = Path()
      ..moveTo(c.dx - r, c.dy + r * .5)
      ..lineTo(c.dx - r, c.dy - r * .35)
      ..lineTo(c.dx - r * .5, c.dy + r * .05)
      ..lineTo(c.dx, c.dy - r * .7)
      ..lineTo(c.dx + r * .5, c.dy + r * .05)
      ..lineTo(c.dx + r, c.dy - r * .35)
      ..lineTo(c.dx + r, c.dy + r * .5)
      ..close();
    canvas.drawPath(path, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, p.hi, p.mid]).createShader(path.getBounds()));
    for (final dx in [-r, 0.0, r]) {
      canvas.drawCircle(Offset(c.dx + dx, c.dy - (dx == 0 ? r * .78 : r * .42)), r * .13, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _MedalPainter old) => old.tier != tier;
}
