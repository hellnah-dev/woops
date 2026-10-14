import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/application/profile_providers.dart';
import '../../profile/data/location_service.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/domain/profile_enums.dart';
import '../../profile/domain/profile_models.dart';
import '../../profile/presentation/photo_grid_editor.dart';
import '../../profile/presentation/profile_field_widgets.dart';

enum _Step { name, birthday, gender, interestedIn, intention, interests, photos, about, location }

/// Profile setup wizard. The profile row is created after the "interests"
/// step; photos are uploaded straight away; onboarding is marked complete on
/// the server (which checks for a photo) at the end.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  DateTime? _birthdate;
  Gender? _gender;
  Set<Gender> _interestedIn = {};
  Intention? _intention;
  Set<int> _interestIds = {};
  List<ProfilePrompt> _prompts = [];

  var _step = _Step.name;
  bool _busy = false;
  bool _profileCreated = false;

  @override
  void initState() {
    super.initState();
    // Resume: profile exists but onboarding was not finished.
    final existing = ref.read(myProfileProvider).valueOrNull;
    if (existing != null) {
      _profileCreated = true;
      _name.text = existing.displayName;
      _bio.text = existing.bio;
      _prompts = existing.prompts;
      _step = _Step.photos;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  bool get _canContinue => switch (_step) {
        _Step.name => Validators.displayName(_name.text) == null,
        _Step.birthday => _birthdate != null && isAdult(_birthdate!),
        _Step.gender => _gender != null,
        _Step.interestedIn => _interestedIn.isNotEmpty,
        _Step.intention => _intention != null,
        _Step.interests => _interestIds.isNotEmpty,
        _Step.photos => (ref.watch(myProfileProvider).valueOrNull?.photos.length ?? 0) >= 1,
        _Step.about => Validators.maxLength(_bio.text, 500) == null,
        _Step.location => true,
      };

  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      switch (_step) {
        case _Step.interests when !_profileCreated:
          await ref.read(profileRepositoryProvider).createProfile(ProfileDraft(
                displayName: _name.text,
                birthdate: _birthdate!,
                gender: _gender!,
                interestedIn: _interestedIn,
                intention: _intention!,
                interestIds: _interestIds,
              ));
          _profileCreated = true;
          await ref.read(myProfileProvider.notifier).refresh();
        case _Step.about:
          final repo = ref.read(profileRepositoryProvider);
          await repo.updateProfile({'bio': _bio.text.trim()});
          await repo.savePrompts(_prompts);
        default:
          break;
      }
      if (_step == _Step.location) {
        await _finish();
        return;
      }
      setState(() => _step = _Step.values[_step.index + 1]);
    } catch (e) {
      if (mounted) showSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enableLocation() async {
    setState(() => _busy = true);
    try {
      await ref.read(locationServiceProvider).updateMyLocation();
      await _finish();
    } catch (e) {
      if (!mounted) return;
      final error = AppException.from(e);
      if (error.code == 'location_denied_forever') {
        showSnack(context, error.message, isError: true);
        await ref.read(locationServiceProvider).openSettings();
      } else {
        showSnack(context, error.message, isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    await ref.read(profileRepositoryProvider).completeOnboarding();
    // Refreshing the profile makes the router move to the home screen.
    await ref.read(myProfileProvider.notifier).refresh();
  }

  void _back() {
    final firstStep = _profileCreated ? _Step.photos : _Step.name;
    if (_step == firstStep) return;
    setState(() => _step = _Step.values[_step.index - 1]);
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthdate ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'Your birthday',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked != null) setState(() => _birthdate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstStep = _profileCreated ? _Step.photos : _Step.name;
    final progress = (_step.index + 1) / _Step.values.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _step == firstStep
              ? null
              : IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded), onPressed: _busy ? null : _back),
          automaticallyImplyLeading: false,
          title: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(value: progress, minHeight: 6),
          ),
          actions: [
            TextButton(
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
              child: const Text('Sign out'),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  ),
                  child: SingleChildScrollView(
                    key: ValueKey(_step),
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
                    child: _buildStep(theme),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
                child: _step == _Step.location
                    ? Column(
                        children: [
                          PrimaryButton(
                            label: 'Enable location',
                            icon: Icons.near_me_rounded,
                            loading: _busy,
                            onPressed: _enableLocation,
                          ),
                          const SizedBox(height: 8),
                          TextButton(onPressed: _busy ? null : _next, child: const Text('Not now')),
                        ],
                      )
                    : PrimaryButton(
                        label: 'Continue',
                        loading: _busy,
                        onPressed: _canContinue ? _next : null,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, String title, [String? subtitle]) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.headlineMedium),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(subtitle, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      );

  Widget _buildStep(ThemeData theme) {
    switch (_step) {
      case _Step.name:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _header(theme, 'What’s your first name?', 'This is how you’ll appear on Amora.'),
          TextField(
            key: const Key('onboarding-name'),
            controller: _name,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'First name'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _canContinue ? _next() : null,
          ),
        ]);
      case _Step.birthday:
        final age = _birthdate == null ? null : ageFromBirthdate(_birthdate!);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _header(theme, 'When’s your birthday?', 'Only your age is shown. You can’t change this later.'),
          OutlinedButton.icon(
            onPressed: _pickBirthdate,
            icon: const Icon(Icons.cake_outlined),
            label: Text(_birthdate == null ? 'Select date' : DateFormat.yMMMMd().format(_birthdate!)),
          ),
          if (age != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              age >= 18 ? 'You’re $age.' : 'You must be at least 18 to use Amora.',
              style: theme.textTheme.titleMedium?.copyWith(color: age >= 18 ? null : theme.colorScheme.error),
            ),
          ],
        ]);
      case _Step.gender:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _header(theme, 'How do you identify?'),
          for (final g in Gender.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _OptionTile(label: g.label, selected: _gender == g, onTap: () => setState(() => _gender = g)),
            ),
        ]);
      case _Step.interestedIn:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _header(theme, 'Who would you like to meet?', 'Choose all that apply. You can change this anytime.'),
          for (final g in Gender.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _OptionTile(
                label: g.pluralLabel,
                selected: _interestedIn.contains(g),
                multi: true,
                onTap: () => setState(() {
                  _interestedIn = {..._interestedIn};
                  _interestedIn.contains(g) ? _interestedIn.remove(g) : _interestedIn.add(g);
                }),
              ),
            ),
        ]);
      case _Step.intention:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _header(theme, 'What are you looking for?', 'Being upfront helps you find the right people.'),
          for (final i in Intention.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _OptionTile(
                label: '${i.emoji}  ${i.label}',
                selected: _intention == i,
                onTap: () => setState(() => _intention = i),
              ),
            ),
        ]);
      case _Step.interests:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _header(theme, 'What are you into?', 'Pick up to 10. Shared interests make great openers.'),
          InterestPicker(selected: _interestIds, onChanged: (s) => setState(() => _interestIds = s)),
        ]);
      case _Step.photos:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _header(theme, 'Add your photos', 'Add at least one. Clear photos of your face work best. '
              'Tap a photo to make it your main one or remove it.'),
          const PhotoGridEditor(),
        ]);
      case _Step.about:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _header(theme, 'Tell people about you', 'Optional, but profiles with a bio get more matches.'),
          TextField(
            controller: _bio,
            maxLength: 500,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'A few lines about you…'),
            onChanged: (_) => setState(() {}),
          ),
          const SectionLabel('Prompts', trailing: 'Optional'),
          PromptsEditor(prompts: _prompts, onChanged: (p) => setState(() => _prompts = p)),
        ]);
      case _Step.location:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _header(theme, 'See people near you'),
          _Explainer(icon: Icons.near_me_outlined, text: 'We use your location to show people nearby and how far away they are.'),
          _Explainer(icon: Icons.lock_outline_rounded, text: 'Your exact location is never stored or shown. We round it to about 1 km.'),
          _Explainer(icon: Icons.tune_rounded, text: 'You can hide your distance in Privacy settings at any time.'),
        ]);
    }
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.label, required this.selected, required this.onTap, this.multi = false});

  final String label;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
            color: selected ? scheme.primary.withValues(alpha: 0.08) : null,
          ),
          child: Row(
            children: [
              Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
              Icon(
                multi
                    ? (selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded)
                    : (selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                color: selected ? scheme.primary : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
