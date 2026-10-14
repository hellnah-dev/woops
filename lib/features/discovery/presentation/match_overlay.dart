import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/love_widgets.dart';
import '../../../core/widgets/profile_photo.dart';

/// "It's a match!" celebration. Returns true if the user wants to message now.
Future<bool?> showMatchOverlay(
  BuildContext context, {
  required String? myPhoto,
  required String? theirPhoto,
  required String theirName,
}) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 450),
    pageBuilder: (context, _, _) => _MatchOverlay(myPhoto: myPhoto, theirPhoto: theirPhoto, theirName: theirName),
    transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
  );
}

class _MatchOverlay extends StatefulWidget {
  const _MatchOverlay({required this.myPhoto, required this.theirPhoto, required this.theirName});

  final String? myPhoto;
  final String? theirPhoto;
  final String theirName;

  @override
  State<_MatchOverlay> createState() => _MatchOverlayState();
}

class _MatchOverlayState extends State<_MatchOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slide = CurvedAnimation(
      parent: _c,
      curve: const Interval(0, 0.7, curve: Curves.easeOutBack),
    );
    final title = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.35, 1, curve: Curves.elasticOut),
    );

    Widget avatar(String? path, double dir) => AnimatedBuilder(
      animation: slide,
      builder: (context, child) => Transform.translate(
        offset: Offset(dir * 120 * (1 - slide.value), 0),
        child: Transform.rotate(angle: dir * 0.12, child: child),
      ),
      child: Container(
        width: 132,
        height: 172,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20)],
        ),
        child: ProfilePhoto(storagePath: path, borderRadius: BorderRadius.circular(AppRadius.lg - 4)),
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          const Positioned.fill(child: FloatingHearts(count: 24, opacity: 0.45)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  const Spacer(),
                  ScaleTransition(
                    scale: title,
                    child: ShaderMask(
                      shaderCallback: (rect) => AppColors.brandGradient.createShader(rect),
                      child: const Text(
                        'It’s a match!',
                        style: TextStyle(fontFamily: AppFonts.script, color: Colors.white, fontSize: 48, height: 1.3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'You and ${widget.theirName} like each other.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [avatar(widget.myPhoto, -1), const SizedBox(width: 8), avatar(widget.theirPhoto, 1)],
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.chat_bubble_rounded),
                    label: Text('Message ${widget.theirName}'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep swiping'),
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
