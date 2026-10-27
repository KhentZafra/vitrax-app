import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Dark background with faint topographic contour lines and a glowing blue
/// accent curve, used by the login and register screens.
class ContourBackground extends StatelessWidget {
  final Widget child;
  final bool curveTopRight;
  final bool curveBottomLeft;

  const ContourBackground({
    super.key,
    required this.child,
    this.curveTopRight = false,
    this.curveBottomLeft = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ContourPainter(curveTopRight: curveTopRight, curveBottomLeft: curveBottomLeft),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _ContourPainter extends CustomPainter {
  final bool curveTopRight;
  final bool curveBottomLeft;
  const _ContourPainter({required this.curveTopRight, required this.curveBottomLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xff2f6bff).withValues(alpha: 0.07);
    const lines = 16;
    for (var i = 0; i < lines; i++) {
      final y = size.height * (i / (lines - 1));
      final path = Path()..moveTo(0, y);
      for (double x = 0; x <= size.width; x += 8) {
        final dy = math.sin(x / size.width * 2 * math.pi * 1.3 + i * 0.6) * 14 +
            math.sin(x / size.width * 2 * math.pi * 0.6 + i) * 10;
        path.lineTo(x, y + dy);
      }
      canvas.drawPath(path, faint);
    }

    void accent(Path p) {
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = const Color(0xff2f6bff).withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xff2f7bff),
      );
    }

    if (curveTopRight) {
      accent(Path()
        ..moveTo(size.width * 0.5, 0)
        ..cubicTo(size.width * 0.75, size.height * 0.04, size.width * 0.8, size.height * 0.1, size.width * 0.9, size.height * 0.19)
        ..cubicTo(size.width * 0.96, size.height * 0.24, size.width, size.height * 0.2, size.width * 1.02, size.height * 0.19));
    }
    if (curveBottomLeft) {
      accent(Path()
        ..moveTo(0, size.height * 0.86)
        ..cubicTo(size.width * 0.25, size.height * 0.88, size.width * 0.3, size.height * 0.95, size.width * 0.5, size.height * 1.02));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Wide blue gradient button with a soft glow and an arrow at the end.
class GlowButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool spaced;
  final double height;

  const GlowButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.spaced = false,
    this.height = 58,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(colors: [Color(0xff0a4dff), Color(0xff0aa5ff)]),
        boxShadow: [
          BoxShadow(color: const Color(0xff1f6bff).withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (loading)
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
              else
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: spaced ? 17 : 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: spaced ? 8 : 0.5,
                    fontFamily: spaced ? 'Orbitron' : null,
                    fontVariations: spaced ? const [FontVariation('wght', 700)] : null,
                  ),
                ),
              if (!loading)
                const Positioned(right: 22, child: Icon(Icons.arrow_forward, color: Colors.white, size: 24)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Orbitron (techno) text style used for headings on the auth screens.
TextStyle techText(double size, {double weight = 700, double letterSpacing = 0, Color color = Colors.white, bool italic = false}) {
  return TextStyle(
    fontFamily: 'Orbitron',
    fontSize: size,
    color: color,
    letterSpacing: letterSpacing,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    fontVariations: [FontVariation('wght', weight)],
  );
}

/// Shared small-text styles so the login and register screens match:
/// field labels use Orbitron 12, every other small text is 16.
const TextStyle authBodyStyle = TextStyle(color: Color(0xffbdbdbd), fontSize: 16, fontWeight: FontWeight.w300);
const TextStyle authLinkStyle = TextStyle(color: Color(0xff0a77ff), fontSize: 16, fontWeight: FontWeight.w600);
TextStyle get authLabelStyle => techText(12, weight: 800, letterSpacing: 4);

/// Register-screen background: the blue curves from the design, top right
/// and bottom left, behind the form.
class AuthImageDecor extends StatelessWidget {
  final Widget child;
  const AuthImageDecor({super.key, required this.child});

  Widget _fade(Widget image, {required List<Color> colors, required Alignment begin, required Alignment end}) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => LinearGradient(begin: begin, end: end, colors: colors, stops: const [0, 0.6, 1]).createShader(r),
      child: image,
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Stack(
      children: [
        Positioned(
          top: 0,
          right: 0,
          width: w * 372 / 842,
          child: IgnorePointer(
            child: _fade(
              Image.asset('assets/img/register_top.jpg', fit: BoxFit.fitWidth),
              colors: const [Colors.white, Colors.white, Colors.transparent],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          width: w * 230 / 842,
          child: IgnorePointer(
            child: _fade(
              Image.asset('assets/img/register_bottom.jpg', fit: BoxFit.fitWidth),
              colors: const [Colors.transparent, Colors.white, Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        child,
      ],
    );
  }
}
