import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/i18n/units.dart';
import '../../core/permissions/permission_gate.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/love_ui.dart';
import '../../core/widgets/profile_photo.dart';
import '../../core/widgets/state_views.dart';
import '../discovery/application/discovery_controller.dart';
import '../discovery/data/discovery_repository.dart';
import '../discovery/presentation/match_flow.dart';
import '../profile/data/location_service.dart';
import '../profile/presentation/profile_detail_screen.dart';
import 'map_repository.dart';

/// People near you on a map, with how far away each one is. Positions are
/// approximate (~2 km); people who hide their distance are not shown.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _map = MapController();
  final _strip = PageController(viewportFraction: 0.82);
  String? _selected;
  bool _locating = false;

  /// Which pins and cards are shown: people nearby, or my matches.
  bool _showMatches = false;

  /// This phone's live position (only ever shown to you).
  LatLng? _here;

  @override
  void initState() {
    super.initState();
    _refreshHere();
  }

  /// Takes a fresh reading so the map isn't centred on an old saved location.
  Future<void> _refreshHere({bool recenter = false}) async {
    final pos = await ref.read(locationServiceProvider).refreshIfAllowed();
    if (pos == null || !mounted) return;
    final here = LatLng(pos.latitude, pos.longitude);
    setState(() => _here = here);
    ref.invalidate(mapDataProvider); // distances change with the new location
    if (recenter) _map.move(here, 12);
  }

  Future<void> _shareLocation() async {
    if (!await PermissionGate.request(context, AppPermission.location) || !mounted) return;
    setState(() => _locating = true);
    try {
      final pos = await ref.read(locationServiceProvider).updateMyLocation();
      if (mounted) setState(() => _here = LatLng(pos.latitude, pos.longitude));
      ref.invalidate(mapDataProvider);
      ref.read(discoveryControllerProvider.notifier).load(reset: true);
    } catch (e) {
      if (mounted) showSnack(context, e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _select(MapPerson p, List<MapPerson> people, {bool fromStrip = false}) {
    setState(() => _selected = p.id);
    _map.move(p.position, _map.camera.zoom < 11 ? 12 : _map.camera.zoom);
    if (!fromStrip && _strip.hasClients) {
      _strip.animateToPage(people.indexOf(p), duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  /// Refresh: a new location reading, then new people/matches.
  Future<void> _refresh() async {
    await _refreshHere();
    ref.invalidate(mapDataProvider);
  }

  void _toggle(bool matches) {
    if (matches == _showMatches) return;
    setState(() {
      _showMatches = matches;
      _selected = null;
    });
    if (_strip.hasClients) _strip.jumpToPage(0);
  }

  void _openChat(MapPerson p) => context.push(
    Routes.chat(p.conversationId!),
    extra: ChatRouteArgs(matchId: p.matchId!, otherUserId: p.id, otherName: p.name, otherPhoto: p.photo),
  );

  Future<void> _openProfile(MapPerson p) async {
    final controller = ref.read(discoveryControllerProvider.notifier);
    var card = ref.read(discoveryControllerProvider).queue.where((c) => c.id == p.id).firstOrNull;
    try {
      card ??= (await ref.read(discoveryRepositoryProvider).fetchFeed(limit: 50))
          .where((c) => c.id == p.id)
          .firstOrNull;
    } catch (_) {}
    if (!mounted) return;
    if (card == null) {
      showSnack(context, 'This profile isn’t available right now.');
      return;
    }
    final action = await context.push<SwipeAction>(
      Routes.user(card.id),
      extra: ProfileDetailArgs(card: card, actions: ProfileDetailActions.swipe),
    );
    if (action == null || !mounted) return;
    try {
      final result = await controller.swipe(card, action);
      ref.invalidate(mapDataProvider);
      if (result != null && result.matched && mounted) await celebrateMatch(context, ref, result, card);
    } catch (e) {
      if (mounted) showSnack(context, e);
    }
  }

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(mapDataProvider);
    final busy = data.isLoading || _locating;
    final d = data.valueOrNull;
    final canPop = Navigator.of(context).canPop();

    // Floating controls, always visible on top of the map.
    final topBar = Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              if (canPop)
                _MapButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Center(
                  child: _ModeSwitch(
                    matches: _showMatches,
                    nearbyCount: d?.people.length,
                    matchCount: d?.matches.length,
                    onChanged: _toggle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _MapButton(icon: Icons.refresh_rounded, tooltip: 'Refresh', busy: busy, onTap: busy ? null : _refresh),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      body: data.when(
        skipLoadingOnRefresh: true,
        loading: () => Stack(
          children: [
            const LoadingView(message: 'Finding people near you…'),
            topBar,
          ],
        ),
        error: (e, _) => Stack(
          children: [
            ErrorView(error: e, onRetry: _refresh),
            topBar,
          ],
        ),
        data: (d) {
          if (d.me == null) {
            return Stack(
              children: [
                EmptyState(
                  icon: Icons.near_me_outlined,
                  title: 'Share your location',
                  message: 'See who’s nearby and how far they are. Your location is rounded and never shown exactly.',
                  actionLabel: _locating ? 'Locating…' : 'Allow location',
                  onAction: _locating ? null : _shareLocation,
                ),
                topBar,
              ],
            );
          }
          final people = _showMatches ? d.matches : d.people;
          final me = _here ?? d.me!;
          return Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: me,
                  initialZoom: 11,
                  minZoom: 3,
                  maxZoom: 15, // approximate positions: no street-level zoom
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                  onTap: (_, _) => setState(() => _selected = null),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.woops.app',
                    // Restyled to match the app: dark tiles in dark mode,
                    // a soft blush wash (less busy colours) in light mode.
                    tileBuilder: Theme.of(context).brightness == Brightness.dark
                        ? darkModeTileBuilder
                        : (context, tile, _) => ColorFiltered(colorFilter: _blushTiles, child: tile),
                  ),
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: me,
                        radius: 1500,
                        useRadiusInMeter: true,
                        color: AppColors.rose.withValues(alpha: 0.12),
                        borderColor: AppColors.rose.withValues(alpha: 0.5),
                        borderStrokeWidth: 1.5,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(point: me, width: 26, height: 26, child: const _MeDot()),
                      for (final p in people)
                        Marker(
                          point: p.position,
                          width: 58,
                          height: 66,
                          alignment: Alignment.topCenter,
                          child: _PersonPin(person: p, selected: p.id == _selected, onTap: () => _select(p, people)),
                        ),
                    ],
                  ),
                  const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
                ],
              ),
              topBar,
              Positioned(
                right: 16,
                bottom: 124,
                child: SafeArea(
                  top: false,
                  child: _MapButton(
                    icon: Icons.my_location_rounded,
                    tooltip: 'Back to my location',
                    size: 52,
                    onTap: () {
                      _map.move(me, 12);
                      _refreshHere(recenter: true);
                    },
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: SafeArea(
                  top: false,
                  child: people.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                          child: SoftCard(
                            child: Text(
                              _showMatches
                                  ? 'None of your matches share their distance yet.'
                                  : 'No one nearby on the map yet. Try widening your distance in filters.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : SizedBox(
                          height: 92,
                          child: PageView.builder(
                            key: ValueKey(_showMatches),
                            controller: _strip,
                            itemCount: people.length,
                            onPageChanged: (i) => _select(people[i], people, fromStrip: true),
                            itemBuilder: (context, i) => Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: _PersonCard(
                                person: people[i],
                                onOpen: () => people[i].isMatch ? _openChat(people[i]) : _openProfile(people[i]),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Round, solid button that stays readable on any map.
class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.tooltip, required this.onTap, this.size = 46, this.busy = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: GlassSurface(
        blur: 14,
        strength: 1.25,
        borderRadius: BorderRadius.circular(size),
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: busy
                  ? Padding(
                      padding: EdgeInsets.all(size * 0.3),
                      child: const CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Icon(icon, color: scheme.onSurface, size: size * 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Nearby | Matches" switch at the top of the map.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.matches, required this.onChanged, this.nearbyCount, this.matchCount});
  final bool matches;
  final ValueChanged<bool> onChanged;
  final int? nearbyCount;
  final int? matchCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget option(String label, int? count, bool value, IconData icon) {
      final on = matches == value;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              gradient: on ? AppColors.brandGradient : null,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: on ? Colors.white : scheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    count == null ? label : '$label $count',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, color: on ? Colors.white : scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GlassSurface(
      blur: 14,
      strength: 1.25,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Row(
            children: [
              option('Nearby', nearbyCount, false, Icons.near_me_rounded),
              option('Matches', matchCount, true, Icons.favorite_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

/// Desaturates the map a little and warms it towards the brand's blush.
const _blushTiles = ColorFilter.matrix([
  0.567, 0.393, 0.040, 0, 10, //
  0.111, 0.801, 0.038, 0, 0, //
  0.113, 0.381, 0.475, 0, 8, //
  0, 0, 0, 1, 0,
]);

class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.blue,
      border: Border.all(color: Colors.white, width: 4),
      boxShadow: [BoxShadow(color: Colors.blue.withValues(alpha: 0.4), blurRadius: 10)],
    ),
  );
}

class _PersonPin extends StatelessWidget {
  const _PersonPin({required this.person, required this.selected, required this.onTap});
  final MapPerson person;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: selected ? 1.15 : 1,
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.bottomCenter,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.brandGradient,
                    boxShadow: [BoxShadow(color: AppColors.rose.withValues(alpha: 0.4), blurRadius: 8)],
                  ),
                  child: ProfileAvatar(storagePath: person.photo, size: 46),
                ),
                if (person.isMatch)
                  Positioned(
                    right: -4,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.favorite_rounded, size: 13, color: AppColors.rose),
                    ),
                  ),
              ],
            ),
            const Icon(Icons.arrow_drop_down_rounded, color: AppColors.rose, size: 16),
          ],
        ),
      ),
    );
  }
}

class _PersonCard extends ConsumerWidget {
  const _PersonCard({required this.person, required this.onOpen});
  final MapPerson person;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(10),
      onTap: onOpen,
      child: Row(
        children: [
          ProfileAvatar(storagePath: person.photo, size: 62),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${person.name}, ${person.age}',
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (person.isVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified_rounded, color: Colors.blue, size: 16),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.near_me_rounded, size: 14, color: AppColors.rose),
                    const SizedBox(width: 4),
                    Text(
                      DistanceUnits.away(person.distanceKm),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (person.isMatch)
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
              onPressed: onOpen,
              icon: const Icon(Icons.chat_bubble_rounded, size: 16),
              label: const Text('Chat'),
            )
          else
            const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
