import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/countries.dart';
import '../../../core/i18n/units.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/country_picker.dart';
import '../../../core/widgets/state_views.dart';
import '../../profile/application/profile_providers.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/domain/profile_enums.dart';
import '../../profile/domain/profile_models.dart';
import '../../profile/presentation/profile_field_widgets.dart';
import '../application/discovery_controller.dart';

/// Opens the discovery preferences editor. Saves to the server and reloads
/// the feed when the user taps "Apply".
Future<void> showFiltersSheet(BuildContext context) => showModalBottomSheet<void>(
  // Over the whole screen, never under the glass tab bar.
  useRootNavigator: true,
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => const FiltersSheet(),
);

class FiltersSheet extends ConsumerStatefulWidget {
  const FiltersSheet({super.key});

  @override
  ConsumerState<FiltersSheet> createState() => _FiltersSheetState();
}

/// Slider stops in km; the last one means "Anywhere".
const _distanceStops = [1, 2, 5, 10, 15, 25, 40, 50, 75, 100, 150, 200, 300, 500, 1000, 2000, DistanceUnits.anywhereKm];

int _stopIndex(int km) {
  for (var i = 0; i < _distanceStops.length; i++) {
    if (_distanceStops[i] >= km) return i;
  }
  return _distanceStops.length - 1;
}

class _FiltersSheetState extends ConsumerState<FiltersSheet> {
  DiscoveryPreferences? _prefs;
  bool _saving = false;

  Future<void> _apply() async {
    final prefs = _prefs;
    if (prefs == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).savePreferences(prefs);
      ref.invalidate(discoveryPreferencesProvider);
      ref.read(discoveryControllerProvider.notifier).load(reset: true);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(discoveryPreferencesProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, scroll) => async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(discoveryPreferencesProvider)),
        data: (loaded) {
          final p = _prefs ??= loaded;
          final theme = Theme.of(context);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                  children: [
                    Text('Discovery filters', style: theme.textTheme.headlineSmall),
                    SectionLabel('Age range', trailing: '${p.minAge} – ${p.maxAge == 99 ? '99+' : p.maxAge}'),
                    RangeSlider(
                      min: 18,
                      max: 99,
                      divisions: 81,
                      values: RangeValues(p.minAge.toDouble(), p.maxAge.toDouble()),
                      labels: RangeLabels('${p.minAge}', '${p.maxAge}'),
                      onChanged: (v) =>
                          setState(() => _prefs = p.copyWith(minAge: v.start.round(), maxAge: v.end.round())),
                    ),
                    SectionLabel('Maximum distance', trailing: DistanceUnits.limit(p.maxDistanceKm)),
                    Slider(
                      min: 0,
                      max: _distanceStops.length - 1,
                      divisions: _distanceStops.length - 1,
                      value: _stopIndex(p.maxDistanceKm).toDouble(),
                      label: DistanceUnits.limit(p.maxDistanceKm),
                      onChanged: (v) => setState(() => _prefs = p.copyWith(maxDistanceKm: _distanceStops[v.round()])),
                    ),
                    const SectionLabel('Countries', trailing: 'Any if none selected'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final code in p.countryCodes)
                          if (countryByCode(code) case final c?)
                            InputChip(
                              label: Text('${c.flag} ${c.name}'),
                              onDeleted: () =>
                                  setState(() => _prefs = p.copyWith(countryCodes: {...p.countryCodes}..remove(code))),
                            ),
                        ActionChip(
                          avatar: const Icon(Icons.add_rounded, size: 18),
                          label: Text(p.countryCodes.isEmpty ? 'Choose countries' : 'Edit'),
                          onPressed: () async {
                            final chosen = await showCountryMultiPicker(context, selected: p.countryCodes);
                            if (chosen != null && mounted) setState(() => _prefs = p.copyWith(countryCodes: chosen));
                          },
                        ),
                      ],
                    ),
                    const SectionLabel('Show me'),
                    ChoiceChipGroup<Gender>(
                      options: Gender.values,
                      selected: p.genders,
                      labelOf: (g) => g.pluralLabel,
                      onChanged: (s) {
                        if (s.isEmpty) return; // at least one
                        setState(() => _prefs = p.copyWith(genders: s));
                      },
                    ),
                    const SectionLabel('Looking for', trailing: 'Any if none selected'),
                    ChoiceChipGroup<Intention>(
                      options: Intention.values,
                      selected: p.intentions,
                      labelOf: (i) => i.label,
                      leadingOf: (i) => i.emoji,
                      onChanged: (s) => setState(() => _prefs = p.copyWith(intentions: s)),
                    ),
                    const SectionLabel('Shares an interest', trailing: 'Any if none selected'),
                    InterestPicker(
                      selected: p.interestIds,
                      onChanged: (s) => setState(() => _prefs = p.copyWith(interestIds: s)),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() => _prefs = DiscoveryPreferences(genders: p.genders)),
                          child: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: _saving ? null : _apply,
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.4),
                                )
                              : const Text('Apply'),
                        ),
                      ),
                    ],
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
