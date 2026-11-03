import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import 'glass.dart';

/// Shrinks slightly while pressed, with a light haptic tap. Makes any card or
/// tile feel tactile.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.onTap, this.scale = 0.96});
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Flat rounded surface with a hairline border: the minimal card style.
class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpacing.md), this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Glass card: translucent pane, bright edge and sheen. No blur, so lists
    // of cards stay fast; it reads as glass over the colourful backdrop.
    final card = GlassSurface(padding: padding, child: child);
    return onTap == null ? card : PressableScale(onTap: onTap, scale: 0.98, child: card);
  }
}

enum BannerTone { info, error, success }

/// One-line tinted notice with an icon.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.icon, required this.text, this.tone = BannerTone.info});
  final IconData icon;
  final String text;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      BannerTone.info => (scheme.primaryContainer.withValues(alpha: 0.55), scheme.onPrimaryContainer),
      BannerTone.error => (scheme.errorContainer, scheme.onErrorContainer),
      BannerTone.success => (const Color(0xFFDDF6E6), const Color(0xFF145A32)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

/// Numbered step title: (1) Choose your document.
class StepHeader extends StatelessWidget {
  const StepHeader({super.key, required this.number, required this.title});
  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.brandGradient),
          child: Text(
            '$number',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
        const SizedBox(width: 10),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

/// Circular progress drawn with the brand gradient (profile completeness).
class GradientRing extends StatelessWidget {
  const GradientRing({super.key, required this.value, required this.size, this.stroke = 4, required this.child});
  final double value;
  final double size;
  final double stroke;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.surfaceContainerHighest;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => CustomPaint(
        painter: _RingPainter(v, stroke, track),
        child: SizedBox(
          width: size,
          height: size,
          child: Padding(padding: EdgeInsets.all(stroke + 3), child: child),
        ),
      ),
      child: child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.stroke, this.track);
  final double value;
  final double stroke;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      Paint()
        ..shader = const SweepGradient(
          colors: [Color(0xFFFF7EB3), AppColors.rose, AppColors.apricot, Color(0xFFFF7EB3)],
          transform: GradientRotation(-math.pi / 2),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.track != track;
}

/// Small round icon button with a soft tinted background (e.g. the pen on the avatar).
class TintedIconButton extends StatelessWidget {
  const TintedIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 36,
    this.filled = false,
  });
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        onTap: onPressed,
        scale: 0.9,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: filled ? AppColors.brandGradient : null,
            color: filled ? null : scheme.primaryContainer.withValues(alpha: 0.7),
            border: filled ? Border.all(color: scheme.surface, width: 2.5) : null,
          ),
          child: Icon(icon, size: size * 0.5, color: filled ? Colors.white : scheme.onPrimaryContainer),
        ),
      ),
    );
  }
}
