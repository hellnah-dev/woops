import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/love_widgets.dart';

/// The Woops opening screen: the logo pops in with a heartbeat, the wordmark
/// rises, then the whole thing fades away to reveal the app (which keeps
/// loading underneath, so this adds no waiting time).
class IntroOverlay extends StatefulWidget {
  const IntroOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<IntroOverlay> createState() => _IntroOverlayState();
}

class _IntroOverlayState extends State<IntroOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2300));
  bool _done = false;

  late final _logoScale = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 0.4, end: 1.08).chain(CurveTween(curve: Curves.easeOutBack)), weight: 22),
    TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 8),
    // Heartbeat: two quick pulses.
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.12).chain(CurveTween(curve: Curves.easeOut)), weight: 7),
    TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 7),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.1).chain(CurveTween(curve: Curves.easeOut)), weight: 7),
    TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 9),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 40),
  ]).animate(_c);

  late final _logoFade = CurvedAnimation(parent: _c, curve: const Interval(0, 0.15));
  late final _wordFade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.2, 0.4, curve: Curves.easeOut),
  );
  late final _wordSlide = Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(
    CurvedAnimation(
      parent: _c,
      curve: const Interval(0.2, 0.45, curve: Curves.easeOutCubic),
    ),
  );
  late final _tagFade = CurvedAnimation(parent: _c, curve: const Interval(0.38, 0.55));
  late final _exit = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.8, 1, curve: Curves.easeInOut),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reduceMotion) _c.duration = const Duration(milliseconds: 700);
      _c.forward().whenComplete(() {
        if (mounted) setState(() => _done = true);
      });
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The app always stays at index 0 of the same Stack, so removing the
    // overlay never remounts (and flashes) the app underneath.
    return Stack(
      children: [
        widget.child,
        if (!_done)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => IgnorePointer(
                ignoring: _exit.value > 0.5,
                child: Opacity(
                  opacity: 1 - _exit.value,
                  child: Transform.scale(
                    scale: 1 + _exit.value * 0.08,
                    child: Material(
                      type: MaterialType.transparency,
                      child: DreamyBackground(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FadeTransition(
                                opacity: _logoFade,
                                child: Transform.scale(scale: _logoScale.value, child: const AppLogo(size: 120)),
                              ),
                              const SizedBox(height: 18),
                              FadeTransition(
                                opacity: _wordFade,
                                child: SlideTransition(
                                  position: _wordSlide,
                                  child: const Wordmark(size: 52, text: AppLogo.appName),
                                ),
                              ),
                              const SizedBox(height: 8),
                              FadeTransition(
                                opacity: _tagFade,
                                child: Text(
                                  'Find your someone ♡',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: AppColors.berry.withValues(alpha: 0.8),
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
