import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../data/discovery_repository.dart';

/// A card that can be dragged left (pass) or right (like), or swiped
/// programmatically through its [GlobalKey] (`key.currentState!.swipe(...)`).
class SwipeableCard extends StatefulWidget {
  const SwipeableCard({super.key, required this.child, required this.onSwiped, this.enabled = true});

  final Widget child;
  final ValueChanged<SwipeAction> onSwiped;
  final bool enabled;

  @override
  State<SwipeableCard> createState() => SwipeableCardState();
}

class SwipeableCardState extends State<SwipeableCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  Offset _drag = Offset.zero;
  Animation<Offset>? _animation;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_animation != null) setState(() => _drag = _animation!.value);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _width => MediaQuery.sizeOf(context).width;

  Future<void> _animateTo(
    Offset target, {
    Duration duration = const Duration(milliseconds: 260),
    Curve curve = Curves.easeOut,
  }) async {
    _animation = Tween(begin: _drag, end: target).animate(CurvedAnimation(parent: _controller, curve: curve));
    _controller.duration = duration;
    await _controller.forward(from: 0);
  }

  /// Animates the card off-screen and reports the action.
  Future<void> swipe(SwipeAction action) async {
    if (_done || !mounted) return;
    _done = true;
    HapticFeedback.lightImpact();
    final dir = action == SwipeAction.like ? 1.0 : -1.0;
    await _animateTo(Offset(dir * _width * 1.5, _drag.dy + 40));
    widget.onSwiped(action);
  }

  void _onPanEnd(DragEndDetails details) {
    final threshold = _width * 0.28;
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (_drag.dx > threshold || velocity > 900) {
      swipe(SwipeAction.like);
    } else if (_drag.dx < -threshold || velocity < -900) {
      swipe(SwipeAction.pass);
    } else {
      _animateTo(Offset.zero, duration: const Duration(milliseconds: 400), curve: Curves.elasticOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_drag.dx / (_width * 0.35)).clamp(-1.0, 1.0);
    final angle = progress * math.pi / 22;

    return GestureDetector(
      onPanUpdate: widget.enabled && !_done ? (d) => setState(() => _drag += d.delta) : null,
      onPanEnd: widget.enabled && !_done ? _onPanEnd : null,
      child: Transform.translate(
        offset: _drag,
        child: Transform.rotate(
          angle: angle,
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
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Opacity(
          opacity: opacity.clamp(0, 1),
          child: Transform.rotate(
            angle: angle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
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
    );
  }
}
