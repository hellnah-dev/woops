import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The app logo.
///
/// Drop your logo at `assets/branding/logo.png` (square, transparent
/// background, at least 512×512 px) and it appears everywhere this widget is
/// used. Until then a neutral placeholder of the same size is shown, so layouts
/// do not shift when the real logo is added.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 96, this.showWordmark = false});

  static const assetPath = 'assets/branding/logo.png';
  static const appName = 'Woops';

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: '$appName logo',
      errorBuilder: (context, error, stackTrace) => _Placeholder(size: size),
    );

    if (!showWordmark) return logo;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        SizedBox(height: size * 0.16),
        Text(
          appName,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Semantics(
      label: 'Logo placeholder',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
          color: AppColors.rose.withValues(alpha: 0.06),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          child: Padding(
            padding: EdgeInsets.all(size * 0.12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.image_outlined, color: color),
                Text('LOGO', style: TextStyle(color: color, fontWeight: FontWeight.w700, letterSpacing: 2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
