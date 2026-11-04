import 'dart:math' as math;
import 'package:flutter/material.dart';

/// One-shot confetti: paper rectangles and thin streamers that burst up from
/// the top-centre, tumble in 3D and fall with gravity, then fade out.
/// Pure CustomPainter, no package. Wrap in IgnorePointer so it never blocks taps.
class ConfettiBurst extends StatefulWidget {
  final List<Color> colors;
  final int count;
  final Duration duration;
  const ConfettiBurst({
    super.key,
    this.colors = const [Color(0xffff4d4d), Color(0xffffb020), Color(0xff22c55e), Color(0xff27c4ff), Color(0xffa78bfa), Color(0xffffffff)],
    this.count = 70,
    this.duration = const Duration(milliseconds: 3200),
  });

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _Piece {
  late double vx, vy, w, h, spin, phase, tumble;
  late Color color;
  late bool streamer;
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)..forward();
  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final r = math.Random();
    _pieces = List.generate(widget.count, (_) {
      final p = _Piece();
      final angle = -math.pi / 2 + (r.nextDouble() - .5) * 1.9; // fan upward
      final speed = .55 + r.nextDouble() * .95;
      p.vx = math.cos(angle) * speed;
      p.vy = math.sin(angle) * speed;
      p.streamer = r.nextDouble() < .3;
      p.w = p.streamer ? 3 + r.nextDouble() * 2 : 6 + r.nextDouble() * 6;
      p.h = p.streamer ? 14 + r.nextDouble() * 10 : 9 + r.nextDouble() * 6;
      p.spin = (r.nextDouble() - .5) * 14;
      p.tumble = 4 + r.nextDouble() * 8;
      p.phase = r.nextDouble() * math.pi * 2;
      p.color = widget.colors[r.nextInt(widget.colors.length)];
      return p;
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(painter: _ConfettiPainter(_pieces, _c.value), size: Size.infinite),
        ),
      );
}

class _ConfettiPainter extends CustomPainter {
  final List<_Piece> pieces;
  final double t;
  _ConfettiPainter(this.pieces, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * .28);
    final reach = size.width * 1.1;
    final fade = t < .75 ? 1.0 : (1 - t) / .25;
    for (final p in pieces) {
      // ease-out for the burst, gravity pulls everything down over time
      final ease = 1 - math.pow(1 - t, 2.2);
      final x = origin.dx + p.vx * reach * ease + math.sin(t * 6 + p.phase) * 10 * t;
      final y = origin.dy + p.vy * reach * ease + 520 * t * t;
      final flip = math.cos(t * p.tumble + p.phase); // fake 3D flip
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.phase + t * p.spin);
      canvas.scale(1, flip.abs().clamp(.15, 1.0));
      final paint = Paint()..color = p.color.withValues(alpha: (fade.clamp(0.0, 1.0)) * (flip >= 0 ? 1 : .8));
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.w, height: p.h), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
