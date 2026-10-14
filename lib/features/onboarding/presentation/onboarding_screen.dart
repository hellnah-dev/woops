import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/countries.dart';
import '../../../core/permissions/permission_gate.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/country_picker.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/data/auth_repository.dart';
import '../../legal/legal_screen.dart';
import '../../profile/application/profile_providers.dart';
import '../../profile/data/location_service.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/domain/profile_enums.dart';
import '../../profile/domain/profile_models.dart';
import '../../profile/presentation/photo_grid_editor.dart';
import '../../profile/presentation/profile_field_widgets.dart';
import '../../profile/presentation/username_field.dart';

enum _Step { consent, name, place, birthday, gender, interestedIn, intention, interests, photos, about, location }

/// Profile setup wizard.
///  * consent: shown only if the legal documents haven't been accepted yet
///    (e.g. Apple/Google sign-in skipped the sign-up form)
///  * the profile row is created after "interests"; photos upload straight away
///  * onboarding is marked complete on the server, which checks photo + consent
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _bio = TextEditingController();
  String _username = '';
  bool _usernameOk = false;
  DateTime? _birthdate;
  bool _birthdateLocked = false;
  String? _country;
  int _minAge = 18;
  Gender? _gender;
  Set<Gender> _interestedIn = {};
  Intention? _intention;
  Set<int> _interestIds = {};
  List<ProfilePrompt> _prompts = [];
  bool _consentAdult = false;
  bool _consentTerms = false;

  List<_Step>? _steps;
  int _index = 0;
  bool _busy = false;
  bool _profileCreated = false;

  _Step get _step => _steps![_index];

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authRepositoryProvider);
    final gate = auth.ageGateData;
    if (gate.birthdate != null) {
      _birthdate = gate.birthdate;
      _birthdateLocked = true;
    }
    _country = gate.countryCode ?? deviceCountryCode();

    final existing = ref.read(myProfileProvider).valueOrNull;
    if (existing != null) {
      _profileCreated = true;
      _name.text = existing.displayName;
      _bio.text = existing.bio;
      _prompts = existing.prompts;
    }
    _init(auth);
  }

  Future<void> _init(AuthRepository auth) async {
    var accepted = false;
    try {
      accepted = await auth.hasAcceptedLegal();
    } catch (_) {}
    if (_country != null) _minAge = await auth.minAgeFor(_country!);
    if (!mounted) return;
    setState(() {
      _steps = [
        if (!accepted) _Step.consent,
        if (!_profileCreated) ...[
          _Step.name,
          _Step.place,
          _Step.birthday,
          _Step.gender,
          _Step.interestedIn,
          _Step.intention,
          _Step.interests,
        ],
        _Step.photos,
        _Step.about,
        _Step.location,
      ];
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _bio.dispose();
    super.dispose();
  }

  bool get _canContinue => switch (_step) {
    _Step.consent => _consentAdult && _consentTerms,
    _Step.name => Validators.displayName(_name.text) == null && _usernameOk,
    _Step.place => _country != null && Validators.maxLength(_city.text, 80) == null,
    _Step.birthday => _birthdate != null && ageFromBirthdate(_birthdate!) >= _minAge,
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
        case _Step.consent:
          await ref.read(authRepositoryProvider).acceptLegal(LegalDoc.version);
        case _Step.place:
          _minAge = await ref.read(authRepositoryProvider).minAgeFor(_country!);
        case _Step.interests when !_profileCreated:
          await ref
              .read(profileRepositoryProvider)
              .createProfile(
                ProfileDraft(
                  displayName: _name.text,
                  birthdate: _birthdate!,
                  gender: _gender!,
                  interestedIn: _interestedIn,
                  intention: _intention!,
                  interestIds: _interestIds,
                  countryCode: _country!,
                  username: _username,
                  city: _city.text,
                ),
              );
          _profileCreated = true;
          await ref.read(myProfileProvider.notifier).refresh();
        case _Step.about:
          final repo = ref.read(profileRepositoryProvider);
          await repo.updateProfile({'bio': _bio.text.trim()});
          await repo.savePrompts(_prompts);
        default:
          break;
      }
      if (_index == _steps!.length - 1) {
        await _finish();
        return;
      }
      setState(() => _index++);
    } catch (e) {
      if (mounted) showSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enableLocation() async {
    if (!await PermissionGate.request(context, AppPermission.location)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(locationServiceProvider).updateMyLocation();
      await _finish();
    } catch (e) {
      if (!mounted) return;
      final error = AppException.from(e);
      showSnack(context, error.message, isError: true);
      if (error.code == 'location_denied_forever') await ref.read(locationServiceProvider).openSettings();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    await ref.read(profileRepositoryProvider).completeOnboarding();
    // Refreshing the profile makes the router move to the home screen.
    await ref.read(myProfileProvider.notifier).refresh();
  }

  /// Steps before the profile exists can't be revisited once it's created.
  bool get _canGoBack {
    if (_index == 0) return false;
    final previous = _steps![_index - 1];
    if (_step == _Step.photos && _profileCreated) return false;
    return previous != _Step.consent;
  }

  void _back() {
    if (_canGoBack) setState(() => _index--);
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthdate ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'Your birthday',
      initialEntryMode: DatePickerEntryMode.input,
    );
    if (picked != null) setState(() => _birthdate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_steps == null) return const Scaffold(body: LoadingView());
    final progress = (_index + 1) / _steps!.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _canGoBack
              ? IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded), onPressed: _busy ? null : _back)
              : null,
          automaticallyImplyLeading: false,
          title: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(value: progress, minHeight: 6),
          ),
          actions: [
            TextButton(onPressed: () => ref.read(authRepositoryProvider).signOut(), child: const Text('Sign out')),
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
                        label: _step == _Step.consent ? 'I agree' : 'Continue',
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
      case _Step.consent:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(theme, 'Before you start', 'Woops is a community for adults. Please confirm the following.'),
            CheckboxListTile(
              value: _consentAdult,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => _consentAdult = v ?? false),
              title: Text('I am at least $_minAge years old'),
              subtitle: const Text('Or older, if the law in my country requires it.'),
            ),
            CheckboxListTile(
              value: _consentTerms,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => _consentTerms = v ?? false),
              title: const Text('I agree to the Terms, Privacy Policy and Community Guidelines'),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final doc in LegalDoc.values)
                  TextButton(onPressed: () => openLegal(context, doc), child: Text(doc.title)),
              ],
            ),
          ],
        );
      case _Step.name:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(theme, 'What’s your first name?', 'This is how you’ll appear on Woops.'),
            TextField(
              key: const Key('onboarding-name'),
              controller: _name,
              autofocus: true,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'First name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Pick a username', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            UsernameField(
              onChanged: (v, ok) => setState(() {
                _username = v;
                _usernameOk = ok;
              }),
            ),
          ],
        );
      case _Step.place:
        final country = countryByCode(_country);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(
              theme,
              'Where are you based?',
              'Shown on your profile. People anywhere in the world can use Woops.',
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final c = await showCountryPicker(context, selected: _country);
                if (c != null) setState(() => _country = c.code);
              },
              icon: Text(country?.flag ?? '🌍', style: const TextStyle(fontSize: 20)),
              label: Text(country?.name ?? 'Choose your country'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _city,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'City (optional)'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        );
      case _Step.birthday:
        final age = _birthdate == null ? null : ageFromBirthdate(_birthdate!);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(theme, 'When’s your birthday?', 'Only your age is shown. You can’t change this later.'),
            OutlinedButton.icon(
              onPressed: _birthdateLocked ? null : _pickBirthdate,
              icon: const Icon(Icons.cake_outlined),
              label: Text(_birthdate == null ? 'Select date' : DateFormat.yMMMMd().format(_birthdate!)),
            ),
            if (_birthdateLocked)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('From your sign-up.', style: theme.textTheme.bodySmall),
              ),
            if (age != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                age >= _minAge ? 'You’re $age.' : 'Sorry, you must be at least $_minAge to use Woops in your country.',
                style: theme.textTheme.titleMedium?.copyWith(color: age >= _minAge ? null : theme.colorScheme.error),
              ),
            ],
          ],
        );
      case _Step.gender:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(theme, 'How do you identify?'),
            for (final g in Gender.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OptionTile(label: g.label, selected: _gender == g, onTap: () => setState(() => _gender = g)),
              ),
          ],
        );
      case _Step.interestedIn:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
          ],
        );
      case _Step.intention:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
          ],
        );
      case _Step.interests:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(theme, 'What are you into?', 'Pick up to 10. Shared interests make great openers.'),
            InterestPicker(selected: _interestIds, onChanged: (s) => setState(() => _interestIds = s)),
          ],
        );
      case _Step.photos:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(
              theme,
              'Add your photos',
              'Add at least one. Clear photos of your face work best. '
                  'Photos are compressed and their hidden location data is removed before upload.',
            ),
            const PhotoGridEditor(),
          ],
        );
      case _Step.about:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
          ],
        );
      case _Step.location:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(theme, 'See people near you'),
            const _Explainer(
              icon: Icons.near_me_outlined,
              text: 'We use your location to show people nearby and how far away they are.',
            ),
            const _Explainer(
              icon: Icons.lock_outline_rounded,
              text: 'Your exact location is never stored or shown. We round it to about 1 km.',
            ),
            const _Explainer(
              icon: Icons.public_rounded,
              text: 'Prefer meeting people anywhere? Choose "Anywhere" in filters.',
            ),
          ],
        );
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
