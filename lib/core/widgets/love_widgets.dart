import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_colors.dart';

/// Builds a heart shape that fits in [rect].
Path heartPath(Rect rect) {
  final w = rect.width;
  final h = rect.height;
  final x = rect.left;
  final y = rect.top;
  return Path()
    ..moveTo(x + w / 2, y + h * 0.95)
    ..cubicTo(x - w * 0.1, y + h * 0.55, x + w * 0.05, y - h * 0.05, x + w / 2, y + h * 0.25)
    ..cubicTo(x + w * 0.95, y - h * 0.05, x + w * 1.1, y + h * 0.55, x + w / 2, y + h * 0.95)
    ..close();
}

/// Gently rising hearts in the background. Purely decorative and
/// excluded from accessibility; respects "reduce motion".
class FloatingHearts extends StatefulWidget {
  const FloatingHearts({super.key, this.count = 14, this.opacity = 0.18, this.color = AppColors.rose});

  final int count;
  final double opacity;
  final Color color;

  @override
  State<FloatingHearts> createState() => _FloatingHeartsState();
}

class _FloatingHeartsState extends State<FloatingHearts> with SingleTickerProviderStateMixin {
  // Continuous time (in 18 s cycles) rather than a repeating 0→1 controller,
  // so hearts with different speeds never jump when the cycle wraps.
  final _time = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker((elapsed) => _time.value = elapsed.inMicroseconds / 18e6)..start();
  late final List<_Heart> _hearts = List.generate(widget.count, (i) => _Heart(math.Random(i * 97 + 13)));

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ticker.muted = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _HeartsPainter(_time, _hearts, widget.color, widget.opacity),
          ),
        ),
      ),
    );
  }
}

class _Heart {
  _Heart(math.Random r)
    : x = r.nextDouble(),
      size = 10 + r.nextDouble() * 22,
      speed = 0.5 + r.nextDouble(),
      phase = r.nextDouble(),
      sway = 8 + r.nextDouble() * 18;
  final double x, size, speed, phase, sway;
}

class _HeartsPainter extends CustomPainter {
  _HeartsPainter(this.time, this.hearts, this.color, this.opacity) : super(repaint: time);
  final ValueListenable<double> time;
  final List<_Heart> hearts;
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    for (final h in hearts) {
      final t = (time.value * h.speed + h.phase) % 1.0;
      final y = size.height * (1.1 - t * 1.25);
      final x = size.width * h.x + math.sin((t + h.phase) * math.pi * 2) * h.sway;
      final fade = t < 0.15 ? t / 0.15 : (t > 0.85 ? (1 - t) / 0.15 : 1.0);
      final paint = Paint()..color = color.withValues(alpha: opacity * fade);
      canvas.drawPath(heartPath(Rect.fromCenter(center: Offset(x, y), width: h.size, height: h.size)), paint);
    }
  }

  @override
  bool shouldRepaint(_HeartsPainter old) => false;
}

/// Soft romantic background: pastel gradient + floating hearts.
class DreamyBackground extends StatelessWidget {
  const DreamyBackground({super.key, required this.child, this.hearts = true});
  final Widget child;
  final bool hearts;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: dark ? AppColors.dreamyGradientDark : AppColors.dreamyGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hearts) const Positioned.fill(child: FloatingHearts()),
          child,
        ],
      ),
    );
  }
}

/// "Woops" in the script font with the brand gradient.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 40, this.text = 'Woops'});
  final double size;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => AppColors.brandGradient.createShader(rect),
      // The gradient only colours what's inside this box, and the script
      // font's "p" hangs far below the line: the padding must reach its tip,
      // or the tip is drawn plain white.
      child: Padding(
        padding: EdgeInsets.only(bottom: size * 0.45),
        child: Text(
          text,
          style: TextStyle(fontFamily: AppFonts.script, fontSize: size, color: Colors.white, height: 1.25),
        ),
      ),
    );
  }
}

/// Big heart-shaped like button with a little "pop" when pressed.
class HeartButton extends StatefulWidget {
  const HeartButton({super.key, required this.onPressed, this.size = 76, this.tooltip = 'Like'});
  final VoidCallback? onPressed;
  final double size;
  final String tooltip;

  @override
  State<HeartButton> createState() => _HeartButtonState();
}

class _HeartButtonState extends State<HeartButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    lowerBound: 0.85,
    upperBound: 1.0,
  )..value = 1.0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    if (widget.onPressed == null) return;
    await _c.reverse();
    _c.forward();
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: GestureDetector(
          onTap: _tap,
          child: ScaleTransition(
            scale: _c,
            child: SizedBox(
              width: s,
              height: s,
              child: CustomPaint(
                painter: _HeartButtonPainter(enabled: widget.onPressed != null),
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: s * 0.06),
                    child: Icon(Icons.favorite_rounded, color: Colors.white, size: s * 0.36),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeartButtonPainter extends CustomPainter {
  _HeartButtonPainter({required this.enabled});
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = heartPath(rect.deflate(2));
    canvas.drawShadow(path, AppColors.rose.withValues(alpha: 0.6), 8, false);
    canvas.drawPath(
      path,
      Paint()
        ..shader = (enabled ? AppColors.brandGradient : const LinearGradient(colors: [Colors.grey, Colors.grey]))
            .createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_HeartButtonPainter old) => old.enabled != enabled;
}
