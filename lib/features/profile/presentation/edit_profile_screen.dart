import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/countries.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/country_picker.dart';
import '../../../core/widgets/state_views.dart';
import '../application/profile_providers.dart';
import '../data/profile_repository.dart';
import '../domain/profile_enums.dart';
import '../domain/profile_models.dart';
import 'photo_grid_editor.dart';
import 'profile_field_widgets.dart';
import 'username_field.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _bio;
  late final TextEditingController _job;
  late final TextEditingController _city;
  late Gender _gender;
  late Intention _intention;
  late Set<int> _interests;
  String? _country;
  late String _username;
  bool _usernameOk = true;
  late List<ProfilePrompt> _prompts;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(myProfileProvider).requireValue!;
    _name = TextEditingController(text: p.displayName);
    _bio = TextEditingController(text: p.bio);
    _job = TextEditingController(text: p.jobTitle);
    _city = TextEditingController(text: p.city);
    _gender = p.gender;
    _intention = p.intention;
    _interests = {...p.interestIds};
    _country = p.countryCode;
    _username = p.username ?? '';
    _usernameOk = p.username != null;
    _prompts = [...p.prompts];
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _job.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (!_usernameOk) {
      showSnack(context, 'Choose an available username', isError: true);
      return;
    }
    if (_interests.isEmpty) {
      showSnack(context, 'Pick at least one interest', isError: true);
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(profileRepositoryProvider);
    String? nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();
    try {
      await repo.updateProfile({
        'display_name': _name.text.trim(),
        'bio': _bio.text.trim(),
        'job_title': nullIfEmpty(_job.text),
        'city': nullIfEmpty(_city.text),
        'gender': _gender.value,
        'intention': _intention.value,
        'country_code': _country,
        'username': _username.trim().toLowerCase(),
      });
      await repo.setInterests(_interests);
      await repo.savePrompts(_prompts);
      await ref.read(myProfileProvider.notifier).refresh();
      if (!mounted) return;
      showSnack(context, 'Profile saved');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
            children: [
              const SectionLabel('Photos', trailing: 'Tap a photo for options'),
              const PhotoGridEditor(),
              const SectionLabel('Name'),
              TextFormField(
                controller: _name,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                validator: Validators.displayName,
              ),
              const SectionLabel('Username'),
              UsernameField(
                initial: _username,
                current: ref.read(myProfileProvider).valueOrNull?.username,
                onChanged: (v, ok) => setState(() {
                  _username = v;
                  _usernameOk = ok;
                }),
              ),
              const SectionLabel('About me'),
              TextFormField(
                controller: _bio,
                maxLength: 500,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'A few lines about you…'),
              ),
              const SectionLabel('Prompts', trailing: 'Up to 3'),
              PromptsEditor(prompts: _prompts, onChanged: (p) => setState(() => _prompts = p)),
              const SectionLabel('Work'),
              TextFormField(
                controller: _job,
                maxLength: 60,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Job title'),
              ),
              const SectionLabel('Country'),
              OutlinedButton.icon(
                onPressed: () async {
                  final c = await showCountryPicker(context, selected: _country);
                  if (c != null) setState(() => _country = c.code);
                },
                icon: Text(countryByCode(_country)?.flag ?? '🌍', style: const TextStyle(fontSize: 20)),
                label: Text(countryByCode(_country)?.name ?? 'Choose your country'),
              ),
              const SectionLabel('City'),
              TextFormField(
                controller: _city,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Where you live'),
              ),
              const SectionLabel('Gender'),
              ChoiceChipGroup<Gender>(
                options: Gender.values,
                selected: {_gender},
                multiSelect: false,
                labelOf: (g) => g.label,
                onChanged: (s) => setState(() => _gender = s.first),
              ),
              const SectionLabel('Looking for'),
              ChoiceChipGroup<Intention>(
                options: Intention.values,
                selected: {_intention},
                multiSelect: false,
                labelOf: (i) => i.label,
                leadingOf: (i) => i.emoji,
                onChanged: (s) => setState(() => _intention = s.first),
              ),
              SectionLabel('Interests', trailing: '${_interests.length}/10'),
              InterestPicker(selected: _interests, onChanged: (s) => setState(() => _interests = s)),
            ],
          ),
        ),
      ),
    );
  }
}
