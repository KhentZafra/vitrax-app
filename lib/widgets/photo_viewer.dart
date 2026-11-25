import 'package:flutter/material.dart';

/// Full-screen photo viewer, like opening a photo on Facebook: black
/// background, the photo centred and as big as the screen allows, pinch to
/// zoom, double-tap to zoom in or out, drag to move around when zoomed, and a
/// close button (or the back button) to leave.
Future<void> showPhotoViewer(BuildContext context, String url) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, animation, secondaryAnimation) => _PhotoViewerPage(url: url),
      transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _PhotoViewerPage extends StatefulWidget {
  final String url;
  const _PhotoViewerPage({required this.url});

  @override
  State<_PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<_PhotoViewerPage> {
  // Own zoom/pan handling (no InteractiveViewer): the photo is always laid out
  // to the full screen first, then scaled/moved with a plain Transform.
  double _scale = 1;
  Offset _offset = Offset.zero;
  double _startScale = 1;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  Offset _clamp(Offset o, double scale, Size size) {
    final maxX = size.width * (scale - 1) / 2;
    final maxY = size.height * (scale - 1) / 2;
    return Offset(o.dx.clamp(-maxX, maxX), o.dy.clamp(-maxY, maxY));
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    final s = (_startScale * d.scale).clamp(1.0, 5.0);
    final moved = _startOffset + (d.localFocalPoint - _startFocal);
    setState(() {
      _scale = s;
      _offset = s <= 1.001 ? Offset.zero : _clamp(moved, s, size);
    });
  }

  void _onDoubleTap() {
    setState(() {
      if (_scale > 1.05) {
        _scale = 1;
        _offset = Offset.zero;
      } else {
        _scale = 2.5;
        _offset = Offset.zero;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: Colors.black,
      // The Scaffold body is laid out loosely, so without SizedBox.expand the
      // Stack shrinks to the size of the close button and the photo ends up
      // squeezed into that little box in the top-left corner.
      body: SizedBox.expand(
        child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: (d) => _onScaleUpdate(d, size),
              onDoubleTap: _onDoubleTap,
              child: ClipRect(
                child: Transform.translate(
                  offset: _offset,
                  child: Transform.scale(
                    scale: _scale,
                    child: SizedBox.expand(
                      child: Image.network(
                        widget.url,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        filterQuality: FilterQuality.high,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const Center(child: CircularProgressIndicator(color: Colors.white54));
                        },
                        errorBuilder: (context, error, stackTrace) => const Center(
                          child: Text("Couldn't show the photo.", style: TextStyle(color: Colors.white70)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                tooltip: 'Close',
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
