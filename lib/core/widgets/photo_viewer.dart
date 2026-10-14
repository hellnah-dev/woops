import 'package:flutter/material.dart';

import 'profile_photo.dart';

/// Opens a full-screen photo viewer: swipe between photos, pinch or
/// double-tap to zoom, swipe down (or tap ✕) to close.
Future<void> showPhotoViewer(BuildContext context, {required List<String> photos, int initialIndex = 0}) {
  if (photos.isEmpty) return Future.value();
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (_, _, _) => PhotoViewer(photos: photos, initialIndex: initialIndex),
    transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
  ));
}

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.photos, this.initialIndex = 0});

  final List<String> photos;
  final int initialIndex;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _zoomed = false;
  double _dragY = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = (1 - (_dragY.abs() / 400)).clamp(0.3, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: opacity),
      body: Stack(
        children: [
          GestureDetector(
            // Swipe down to dismiss (only when not zoomed in).
            onVerticalDragUpdate: _zoomed ? null : (d) => setState(() => _dragY += d.delta.dy),
            onVerticalDragEnd: _zoomed
                ? null
                : (d) {
                    if (_dragY.abs() > 120 || d.velocity.pixelsPerSecond.dy.abs() > 900) {
                      Navigator.pop(context);
                    } else {
                      setState(() => _dragY = 0);
                    }
                  },
            child: Transform.translate(
              offset: Offset(0, _dragY),
              child: PageView.builder(
                controller: _pages,
                physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
                itemCount: widget.photos.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _ZoomablePhoto(
                  path: widget.photos[i],
                  onZoomChanged: (z) => setState(() => _zoomed = z),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                  ),
                  const Spacer(),
                  if (widget.photos.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        '${_index + 1} / ${widget.photos.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({required this.path, required this.onZoomChanged});
  final String path;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
    ..addListener(() => _transform.value = _animation!.value);
  Animation<Matrix4>? _animation;
  TapDownDetails? _doubleTap;

  @override
  void dispose() {
    _transform.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    _animation = Matrix4Tween(begin: _transform.value, end: target).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward(from: 0);
    widget.onZoomChanged(target != Matrix4.identity());
  }

  void _onDoubleTap() {
    if (_transform.value.getMaxScaleOnAxis() > 1.01) {
      _animateTo(Matrix4.identity());
    } else {
      final p = _doubleTap?.localPosition ?? Offset.zero;
      const scale = 2.5;
      _animateTo(Matrix4.identity()
        ..translateByDouble(-p.dx * (scale - 1), -p.dy * (scale - 1), 0, 1)
        ..scaleByDouble(scale, scale, 1, 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTap = d,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 5,
        onInteractionEnd: (_) => widget.onZoomChanged(_transform.value.getMaxScaleOnAxis() > 1.01),
        child: Center(
          child: ProfilePhoto(storagePath: widget.path, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
