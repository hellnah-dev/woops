import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/countries.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/i18n/units.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/profile_photo.dart';
import '../../profile/domain/profile_models.dart';

/// Full-bleed photo card with tap-to-browse photos and key details.
class ProfileCardView extends ConsumerStatefulWidget {
  const ProfileCardView({super.key, required this.card, this.onInfo});

  final ProfileCard card;
  final VoidCallback? onInfo;

  @override
  ConsumerState<ProfileCardView> createState() => _ProfileCardViewState();
}

class _ProfileCardViewState extends ConsumerState<ProfileCardView> {
  static const _photoWidth = 1080;
  int _photo = 0;
  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load every photo up front so tapping through them never flashes.
    if (_precached || widget.card.photos.isEmpty) return;
    _precached = true;
    precacheProfilePhotos(context, ref.read(photoUrlResolverProvider), widget.card.photos, memCacheWidth: _photoWidth);
  }

  void _tap(TapUpDetails details, double width) {
    final count = widget.card.photos.length;
    if (count < 2) return;
    setState(() {
      _photo = details.localPosition.dx > width / 2
          ? (_photo + 1).clamp(0, count - 1)
          : (_photo - 1).clamp(0, count - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final theme = Theme.of(context);
    final photos = card.photos;

    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        onTapUp: (d) => _tap(d, constraints.maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 10))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ProfilePhoto(
                  key: ValueKey(photos.isEmpty ? null : photos[_photo]),
                  storagePath: photos.isEmpty ? null : photos[_photo],
                  memCacheWidth: _photoWidth,
                ),
                const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.photoScrim)),
                if (photos.length > 1)
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Row(
                      children: [
                        for (var i = 0; i < photos.length; i++)
                          Expanded(
                            child: Container(
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: i == _photo ? 0.95 : 0.4),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                Positioned(
                  left: 20,
                  right: 12,
                  bottom: 20,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: card.displayName),
                                  TextSpan(
                                    text: '  ${card.age}',
                                    style: const TextStyle(fontWeight: FontWeight.w400),
                                  ),
                                  if (card.isVerified)
                                    const WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: Icon(
                                          Icons.verified_rounded,
                                          color: Colors.lightBlueAccent,
                                          size: 24,
                                          semanticLabel: 'Photo verified',
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (card.isRepeat)
                                  const _Pill(text: '👀 Second look')
                                else if (card.isRandom)
                                  const _Pill(text: '✨ Random pick'),
                                _Pill(text: '${card.intention.emoji} ${card.intention.label}'),
                                if (card.distanceKm != null)
                                  _Pill(icon: Icons.near_me_rounded, text: DistanceUnits.away(card.distanceKm!)),
                                if (card.zodiac case final z?) _Pill(text: '${z.symbol} ${z.label}'),
                                if (countryByCode(card.countryCode) case final c?)
                                  _Pill(text: '${c.flag} ${card.city?.isNotEmpty == true ? card.city! : c.name}'),
                                if ((card.jobTitle ?? '').isNotEmpty)
                                  _Pill(icon: Icons.work_outline_rounded, text: card.jobTitle!),
                              ],
                            ),
                            if (card.bio.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                card.bio,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.92),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (widget.onInfo != null)
                        IconButton(
                          tooltip: 'View full profile',
                          onPressed: widget.onInfo,
                          icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 32),
                          style: IconButton.styleFrom(backgroundColor: Colors.white24, minimumSize: const Size(48, 48)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: Colors.white), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
