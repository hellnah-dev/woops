import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../data/discovery_repository.dart';

/// A card that can be dragged left (pass) or right (like), or swiped
/// programmatically through its [GlobalKey] (`key.currentState!.swipe(...)`).
///
/// Feels like Tinder: the tilt follows where you grabbed the card, a flick
/// throws it at your finger's speed, and crossing the decision point gives a
/// small haptic tick.
class SwipeableCard extends StatefulWidget {
  const SwipeableCard({
    super.key,
    required this.child,
    required this.onSwiped,
    this.enabled = true,
    this.progress,
    this.enterFrom,
  });

  final Widget child;
  final ValueChanged<SwipeAction> onSwiped;
  final bool enabled;

  /// Receives the drag progress, -1 (pass) … 0 … 1 (like), so the screen can
  /// grow the next card and the matching button along with the drag.
  final ValueNotifier<double>? progress;

  /// When set, the card flies in from this offset on first build (undo).
  final Offset? enterFrom;

  @override
  State<SwipeableCard> createState() => SwipeableCardState();
}

class SwipeableCardState extends State<SwipeableCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  Offset _drag = Offset.zero;
  Animation<Offset>? _animation;
  bool _done = false;

  /// +1 when grabbed in the top half (tilts with the finger), -1 in the bottom.
  double _tiltSign = 1;

  /// Whether the drag is currently past the like/pass threshold.
  bool _pastThreshold = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final a = _animation;
      if (a == null) return;
      setState(() => _drag = a.value);
      _reportProgress();
    });
    final from = widget.enterFrom;
    if (from != null) {
      _drag = from;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animateTo(Offset.zero, duration: const Duration(milliseconds: 420), curve: Curves.easeOutBack);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _width => MediaQuery.sizeOf(context).width;
  double get _threshold => _width * 0.28;
  double get _progress => (_drag.dx / (_width * 0.35)).clamp(-1.0, 1.0);

  void _reportProgress() {
    final p = widget.progress;
    if (p != null && widget.enabled) p.value = _progress;
  }

  Future<void> _animateTo(
    Offset target, {
    Duration duration = const Duration(milliseconds: 260),
    Curve curve = Curves.easeOut,
  }) async {
    _animation = Tween(begin: _drag, end: target).animate(CurvedAnimation(parent: _controller, curve: curve));
    _controller.duration = duration;
    await _controller.forward(from: 0);
  }

  /// Animates the card off-screen and reports the action. [velocity] (from a
  /// flick) sets the direction and speed; buttons use a default throw.
  Future<void> swipe(SwipeAction action, {Offset velocity = Offset.zero}) async {
    if (_done || !mounted) return;
    _done = true;
    HapticFeedback.lightImpact();
    final dir = action == SwipeAction.like ? 1.0 : -1.0;
    final target = Offset(dir * _width * 1.6, _drag.dy + velocity.dy * 0.12 + 40);
    // Faster flicks leave faster: 140–300 ms depending on finger speed.
    final speed = velocity.dx.abs();
    final ms = speed > 0 ? (300 - (speed / 12)).clamp(140, 300).round() : 300;
    await _animateTo(
      target,
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
    );
    widget.progress?.value = 0;
    widget.onSwiped(action);
  }

  void _onPanStart(DragStartDetails details) {
    // Grabbing the card mid snap-back takes over from the animation.
    _controller.stop();
    _animation = null;
    final box = context.findRenderObject() as RenderBox?;
    final height = box?.size.height ?? 1;
    _tiltSign = details.localPosition.dy < height / 2 ? 1 : -1;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() => _drag += details.delta);
    _reportProgress();
    final past = _drag.dx.abs() > _threshold;
    if (past != _pastThreshold) {
      _pastThreshold = past;
      if (past) HapticFeedback.selectionClick();
    }
  }

  void _onPanEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    _pastThreshold = false;
    if (_drag.dx > _threshold || velocity.dx > 900) {
      swipe(SwipeAction.like, velocity: velocity);
    } else if (_drag.dx < -_threshold || velocity.dx < -900) {
      swipe(SwipeAction.pass, velocity: velocity);
    } else {
      // Soft spring back with a hint of overshoot.
      _animateTo(Offset.zero, duration: const Duration(milliseconds: 380), curve: Curves.easeOutBack);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final angle = progress * math.pi / 18 * _tiltSign;
    final interactive = widget.enabled && !_done;

    return GestureDetector(
      onPanStart: interactive ? _onPanStart : null,
      onPanUpdate: interactive ? _onPanUpdate : null,
      onPanEnd: interactive ? _onPanEnd : null,
      child: Transform.translate(
        offset: _drag,
        child: Transform.rotate(
          angle: angle,
          // Pivot below/above the card so it swings like it's held by a corner.
          origin: Offset(0, _tiltSign * 260),
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              if (progress > 0.05)
                _Stamp(
                  label: 'LOVE 💖',
                  color: AppColors.like,
                  opacity: progress,
                  alignment: Alignment.topLeft,
                  angle: -0.35,
                ),
              if (progress < -0.05)
                _Stamp(
                  label: 'NOPE',
                  color: AppColors.pass,
                  opacity: -progress,
                  alignment: Alignment.topRight,
                  angle: 0.35,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.label,
    required this.color,
    required this.opacity,
    required this.alignment,
    required this.angle,
  });

  final String label;
  final Color color;
  final double opacity;
  final Alignment alignment;
  final double angle;

  @override
  Widget build(BuildContext context) {
    final t = opacity.clamp(0.0, 1.0);
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Opacity(
          opacity: t,
          // "Stamped on": starts a little big and settles as it appears.
          child: Transform.scale(
            scale: 1.35 - 0.35 * Curves.easeOut.transform(t),
            child: Transform.rotate(
              angle: angle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  border: Border.all(color: color, width: 4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label,
                  style: TextStyle(color: color, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
