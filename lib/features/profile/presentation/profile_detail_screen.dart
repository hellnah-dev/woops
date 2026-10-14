import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/countries.dart';
import '../../../core/i18n/units.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/photo_viewer.dart';
import '../../../core/widgets/profile_photo.dart';
import '../../../core/widgets/state_views.dart';
import '../../discovery/data/discovery_repository.dart';
import '../../safety/presentation/safety_actions.dart';
import '../application/profile_providers.dart';
import '../domain/profile_models.dart';

enum ProfileDetailActions {
  /// No like/pass buttons (e.g. viewing a match).
  none,

  /// Like/pass buttons; the chosen action is returned with `pop`.
  swipe,
}

class ProfileDetailArgs {
  const ProfileDetailArgs({required this.card, this.actions = ProfileDetailActions.none});
  final ProfileCard card;
  final ProfileDetailActions actions;
}

class ProfileDetailScreen extends ConsumerWidget {
  const ProfileDetailScreen({super.key, required this.userId, this.initial, this.actions = ProfileDetailActions.none});

  final String userId;
  final ProfileCard? initial;
  final ProfileDetailActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initial != null) return _Body(card: initial!, actions: actions);

    final async = ref.watch(publicProfileProvider(userId));
    return async.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(error: e, onRetry: () => ref.invalidate(publicProfileProvider(userId))),
      ),
      data: (card) => card == null
          ? Scaffold(
              appBar: AppBar(),
              body: const EmptyState(
                icon: Icons.person_off_outlined,
                title: 'Profile unavailable',
                message: 'This person may have left Woops or is no longer available.',
              ),
            )
          : _Body(card: card, actions: actions),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.card, required this.actions});

  final ProfileCard card;
  final ProfileDetailActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final isMe = ref.watch(myProfileProvider).valueOrNull?.id == card.id;

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: size.height * 0.62,
                foregroundColor: Colors.white,
                backgroundColor: theme.colorScheme.surface,
                leading: Padding(
                  padding: const EdgeInsets.all(6),
                  child: IconButton.filled(
                    tooltip: 'Back',
                    style: IconButton.styleFrom(backgroundColor: Colors.black38),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ),
                actions: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: PopupMenuButton<String>(
                        tooltip: 'More',
                        icon: const CircleAvatar(
                          backgroundColor: Colors.black38,
                          child: Icon(Icons.more_horiz_rounded, color: Colors.white),
                        ),
                        onSelected: (v) async {
                          final Future<bool> action = v == 'report'
                              ? showReportSheet(context, ref, userId: card.id, name: card.displayName)
                              : confirmAndBlock(context, ref, userId: card.id, name: card.displayName);
                          if (await action && context.mounted) Navigator.maybePop(context);
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'report', child: Text('Report ${card.displayName}')),
                          PopupMenuItem(value: 'block', child: Text('Block ${card.displayName}')),
                        ],
                      ),
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(background: _PhotoPager(photos: card.photos)),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  actions == ProfileDetailActions.swipe ? 120 : AppSpacing.xl,
                ),
                sliver: SliverList.list(children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: card.displayName),
                      TextSpan(text: ', ${card.age}', style: const TextStyle(fontWeight: FontWeight.w400)),
                      if (card.isVerified)
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Tooltip(
                              message: 'Photo verified',
                              child: Icon(Icons.verified_rounded, color: Colors.blue, size: 26),
                            ),
                          ),
                        ),
                    ]),
                    style: theme.textTheme.headlineMedium,
                  ),
                  if (card.username != null)
                    Text('@${card.username}',
                        style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _Fact(icon: Icons.person_outline_rounded, text: card.gender.label),
                      if ((card.jobTitle ?? '').isNotEmpty) _Fact(icon: Icons.work_outline_rounded, text: card.jobTitle!),
                      if ((card.city ?? '').isNotEmpty || countryByCode(card.countryCode) != null)
                        _Fact(
                          icon: Icons.location_city_rounded,
                          text: [
                            if ((card.city ?? '').isNotEmpty) card.city!,
                            if (countryByCode(card.countryCode) case final c?) '${c.flag} ${c.name}',
                          ].join(', '),
                        ),
                      if (card.distanceKm != null)
                        _Fact(icon: Icons.near_me_outlined, text: DistanceUnits.away(card.distanceKm!)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _Section(
                    title: 'Looking for',
                    child: Text('${card.intention.emoji}  ${card.intention.label}', style: theme.textTheme.titleMedium),
                  ),
                  if (card.bio.isNotEmpty)
                    _Section(title: 'About', child: Text(card.bio, style: theme.textTheme.bodyLarge?.copyWith(height: 1.45))),
                  for (final p in card.prompts)
                    _Section(
                      title: p.prompt,
                      child: Text(p.answer, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  if (card.interests.isNotEmpty)
                    _Section(
                      title: 'Interests',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [for (final i in card.interests) Chip(label: Text(i))],
                      ),
                    ),
                ]),
              ),
            ],
          ),
          if (actions == ProfileDetailActions.swipe)
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RoundActionButton(
                      tooltip: 'Pass',
                      icon: Icons.close_rounded,
                      color: AppColors.pass,
                      size: 64,
                      onPressed: () => Navigator.pop(context, SwipeAction.pass),
                    ),
                    const SizedBox(width: 32),
                    RoundActionButton(
                      tooltip: 'Like',
                      icon: Icons.favorite_rounded,
                      color: AppColors.like,
                      size: 64,
                      onPressed: () => Navigator.pop(context, SwipeAction.like),
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

class _PhotoPager extends StatefulWidget {
  const _PhotoPager({required this.photos});
  final List<String> photos;

  @override
  State<_PhotoPager> createState() => _PhotoPagerState();
}

class _PhotoPagerState extends State<_PhotoPager> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          itemCount: photos.isEmpty ? 1 : photos.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) => GestureDetector(
            onTap: photos.isEmpty ? null : () => showPhotoViewer(context, photos: photos, initialIndex: i),
            child: ProfilePhoto(storagePath: photos.isEmpty ? null : photos[i], memCacheWidth: 1080),
          ),
        ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66000000), Color(0x00000000)],
                stops: [0, 0.25],
              ),
            ),
          ),
        ),
        if (photos.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < photos.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: i == _index ? 1 : 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(height: AppSpacing.sm),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
