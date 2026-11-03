import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Colours used by the glass look, tuned for light and dark mode.
class GlassColors {
  const GlassColors._();

  static Color fill(BuildContext context, {double strength = 1}) => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF2A1A2A).withValues(alpha: 0.55 * strength)
      : Colors.white.withValues(alpha: 0.62 * strength);

  static Color edge(BuildContext context) => Theme.of(context).brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.white.withValues(alpha: 0.85);

  /// Soft light catching the top-left of a glass pane.
  static LinearGradient sheen(BuildContext context) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: Theme.of(context).brightness == Brightness.dark
        ? [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0.02)]
        : [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0.12)],
  );
}

/// The soft, colourful backdrop that makes glass panes visible: a blush
/// gradient with two large glowing colour blobs. It is static and drawn once
/// (RepaintBoundary), so it costs nothing while scrolling.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0xFF241221), Color(0xFF1C1119), Color(0xFF1A1430)]
                    : const [Color(0xFFFFE6EF), Color(0xFFFFF4F8), Color(0xFFF1EAFF)],
              ),
            ),
            child: CustomPaint(painter: _Blobs(dark: dark)),
          ),
        ),
        child,
      ],
    );
  }
}

class _Blobs extends CustomPainter {
  _Blobs({required this.dark});
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    void blob(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    final a = dark ? 0.22 : 0.30;
    blob(Offset(size.width * 0.1, size.height * 0.12), size.width * 0.7, AppColors.rose.withValues(alpha: a));
    blob(Offset(size.width * 0.95, size.height * 0.55), size.width * 0.75, AppColors.lavender.withValues(alpha: a));
    blob(Offset(size.width * 0.2, size.height * 0.95), size.width * 0.6, AppColors.apricot.withValues(alpha: a * 0.8));
  }

  @override
  bool shouldRepaint(_Blobs old) => old.dark != dark;
}

/// A frosted-glass pane. [blur] is real background blur: use it only for a
/// few surfaces that sit over moving content (tab bar, map buttons), since it
/// is the expensive part. Without blur it is a cheap translucent pane.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.md)),
    this.blur = 0,
    this.padding,
    this.strength = 1,
    this.shadow = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final double strength;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final pane = DecoratedBox(
      decoration: BoxDecoration(
        color: GlassColors.fill(context, strength: strength),
        borderRadius: borderRadius,
        border: Border.all(color: GlassColors.edge(context), width: 1),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: GlassColors.sheen(context), borderRadius: borderRadius),
        child: padding == null ? child : Padding(padding: padding!, child: child),
      ),
    );
    final framed = blur <= 0
        ? pane
        : ClipRRect(
            borderRadius: borderRadius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: pane,
            ),
          );
    if (!shadow) return framed;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: (Theme.of(context).brightness == Brightness.dark ? Colors.black : AppColors.rose).withValues(
              alpha: Theme.of(context).brightness == Brightness.dark ? 0.25 : 0.08,
            ),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: framed,
    );
  }
}
