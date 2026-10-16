import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../../core/i18n/countries.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/country_picker.dart';
import '../../../core/widgets/state_views.dart';
import '../../legal/legal_screen.dart';
import '../data/auth_repository.dart';
import 'auth_cooldown.dart';

/// Shared scaffold for the auth forms.
class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppLogo(size: 56),
              const SizedBox(height: AppSpacing.lg),
              Text(title, style: theme.textTheme.headlineMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(subtitle, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.xl),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({super.key, required this.controller, this.label = 'Password', this.validator, this.onSubmitted});

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      autofillHints: const [AutofillHints.password],
      validator: widget.validator,
      onFieldSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _cooldown = GlobalKey<CooldownBuilderState>();
  bool _loading = false;
  int _wrongPasswords = 0;
  bool _unconfirmed = false;
  bool _resending = false;

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await ref.read(authRepositoryProvider).resendConfirmation(_email.text);
      if (mounted) showSnack(context, 'Confirmation email sent to ${_email.text.trim()}. Check your inbox and spam.');
    } catch (e) {
      if (AuthCooldown.isRateLimited(e)) {
        await AuthCooldown.start('resend', AuthCooldown.waitFor(e));
        if (mounted) showSnack(context, 'Too many emails for now. Please try again in about an hour.', isError: true);
      } else if (mounted) {
        showSnack(context, e);
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).signIn(email: _email.text, password: _password.text);
      // The router redirects automatically once the session exists.
    } catch (e) {
      if (AuthCooldown.isRateLimited(e)) {
        await AuthCooldown.start('sign_in', AuthCooldown.waitFor(e));
        await _cooldown.currentState?.reload();
      } else {
        final m = e is AuthException ? e.message.toLowerCase() : '';
        if (!mounted) return;
        if (m.contains('invalid login')) setState(() => _wrongPasswords++);
        if (m.contains('not confirmed')) {
          setState(() => _unconfirmed = true); // explained below the button, with a resend option
        } else if (mounted) {
          showSnack(context, e);
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to pick up where you left off.',
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('signin-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: Validators.email,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: AppSpacing.md),
              PasswordField(
                controller: _password,
                validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
                onSubmitted: (_) => _submit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.push(Routes.forgotPassword),
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              CooldownBuilder(
                key: _cooldown,
                action: 'sign_in',
                builder: (context, wait) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PrimaryButton(
                      label: wait == null ? 'Sign in' : 'Try again in ${formatWait(wait)}',
                      loading: _loading,
                      onPressed: wait == null ? _submit : null,
                    ),
                    if (wait != null) CooldownNotice(remaining: wait, what: 'sign in'),
                    if (wait == null && _unconfirmed)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Please confirm your email first: open the link we sent to ${_email.text.trim()}.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              key: const Key('resend-confirmation'),
                              onPressed: _resending ? null : _resend,
                              icon: const Icon(Icons.mark_email_unread_outlined),
                              label: const Text('Resend confirmation email'),
                            ),
                          ],
                        ),
                      ),
                    if (wait == null && _wrongPasswords >= 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: OutlinedButton.icon(
                          onPressed: () => context.push(Routes.forgotPassword),
                          icon: const Icon(Icons.lock_reset_rounded),
                          label: const Text('Trouble signing in? Reset your password'),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: () => context.pushReplacement(Routes.signUp),
                child: const Text('New here? Create an account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

/// Sign-up with a neutral age gate: people enter their date of birth (we
/// never hint at the required age) and country, which decides the minimum age
/// (18, or higher where local law requires). The server re-checks both.
class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  DateTime? _birthdate;
  String? _country = deviceCountryCode();
  bool _acceptTerms = false;
  bool _acceptGuidelines = false;
  bool _showErrors = false;
  final _cooldown = GlobalKey<CooldownBuilderState>();
  bool _loading = false;
  int? _blockedMinAge;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthdate ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'Your date of birth',
      initialEntryMode: DatePickerEntryMode.input,
    );
    if (picked != null && mounted) setState(() => _birthdate = picked);
  }

  Future<void> _pickCountry() async {
    final c = await showCountryPicker(context, selected: _country);
    if (c != null && mounted) setState(() => _country = c.code);
  }

  bool get _gateComplete => _birthdate != null && _country != null && _acceptTerms && _acceptGuidelines;

  Future<void> _submit() async {
    final valid = _form.currentState!.validate();
    setState(() => _showErrors = true);
    if (!valid || !_gateComplete) return;

    setState(() => _loading = true);
    final auth = ref.read(authRepositoryProvider);
    try {
      final minAge = await auth.minAgeFor(_country!);
      if (ageFromBirthdate(_birthdate!) < minAge) {
        if (mounted) setState(() => _blockedMinAge = minAge);
        return;
      }
      final result = await auth.signUp(
        email: _email.text,
        password: _password.text,
        birthdate: _birthdate!,
        countryCode: _country!,
      );
      if (result == SignUpResult.signedIn) {
        await auth.acceptLegal(LegalDoc.version).catchError((_) {});
      }
      if (!mounted) return;
      if (result == SignUpResult.alreadyRegistered) {
        final goTo = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.person_search_outlined),
            title: const Text('You already have an account'),
            content: Text(
              '${_email.text.trim()} is already registered. Sign in, or reset your password if you forgot it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, Routes.forgotPassword),
                child: const Text('Reset password'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
                onPressed: () => Navigator.pop(context, Routes.signIn),
                child: const Text('Sign in'),
              ),
            ],
          ),
        );
        if (mounted && goTo != null) context.go(goTo);
        return;
      }
      if (result == SignUpResult.confirmEmail) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.mark_email_unread_outlined),
            title: const Text('Check your email'),
            content: Text(
              'We sent a confirmation link to ${_email.text.trim()}. '
              'Open it on this phone to finish creating your account.',
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
        if (mounted) context.go(Routes.signIn);
      }
    } catch (e) {
      if (AuthCooldown.isRateLimited(e)) {
        await AuthCooldown.start('sign_up', AuthCooldown.waitFor(e));
        await _cooldown.currentState?.reload();
      } else if (mounted) {
        showSnack(context, e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;

    if (_blockedMinAge != null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.no_accounts_outlined,
          title: 'Sorry, you can’t join Woops',
          message: 'Woops is only for adults aged $_blockedMinAge or older in your country.',
          actionLabel: 'Back',
          onAction: () => context.go(Routes.welcome),
        ),
      );
    }

    final country = countryByCode(_country);
    return _AuthScaffold(
      title: 'Create your account',
      subtitle: 'Woops is for adults only. It takes about two minutes.',
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('signup-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: Validators.email,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: AppSpacing.md),
              PasswordField(key: const Key('signup-password'), controller: _password, validator: Validators.password),
              const SizedBox(height: AppSpacing.md),
              PasswordField(
                key: const Key('signup-confirm'),
                controller: _confirm,
                label: 'Confirm password',
                validator: (v) => v != _password.text ? 'Passwords don’t match' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              _GateTile(
                key: const Key('signup-country'),
                icon: Icons.public_rounded,
                label: 'Country',
                value: country == null ? null : '${country.flag}  ${country.name}',
                error: _showErrors && country == null ? 'Choose your country' : null,
                onTap: _pickCountry,
              ),
              const SizedBox(height: AppSpacing.sm),
              _GateTile(
                key: const Key('signup-birthdate'),
                icon: Icons.cake_outlined,
                label: 'Date of birth',
                value: _birthdate == null ? null : DateFormat.yMMMMd().format(_birthdate!),
                error: _showErrors && _birthdate == null ? 'Enter your date of birth' : null,
                onTap: _pickBirthdate,
              ),
              const SizedBox(height: AppSpacing.sm),
              CheckboxListTile(
                key: const Key('signup-terms'),
                value: _acceptTerms,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (v) => setState(() => _acceptTerms = v ?? false),
                title: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('I agree to the '),
                    _InlineLink('Terms', () => openLegal(context, LegalDoc.terms)),
                    const Text(' and '),
                    _InlineLink('Privacy Policy', () => openLegal(context, LegalDoc.privacy)),
                  ],
                ),
                subtitle: _showErrors && !_acceptTerms
                    ? Text('Please accept to continue', style: TextStyle(color: error))
                    : null,
              ),
              CheckboxListTile(
                key: const Key('signup-guidelines'),
                value: _acceptGuidelines,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (v) => setState(() => _acceptGuidelines = v ?? false),
                title: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('I will follow the '),
                    _InlineLink('Community Guidelines', () => openLegal(context, LegalDoc.guidelines)),
                  ],
                ),
                subtitle: _showErrors && !_acceptGuidelines
                    ? Text('Please accept to continue', style: TextStyle(color: error))
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              CooldownBuilder(
                key: _cooldown,
                action: 'sign_up',
                builder: (context, wait) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PrimaryButton(
                      label: wait == null ? 'Create account' : 'Try again in ${formatWait(wait)}',
                      loading: _loading,
                      onPressed: wait == null ? _submit : null,
                    ),
                    if (wait != null) CooldownNotice(remaining: wait, what: 'create an account'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GateTile extends StatelessWidget {
  const _GateTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.error,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), errorText: error),
        isEmpty: value == null,
        child: value == null ? null : Text(value!, style: theme.textTheme.bodyLarge),
      ),
    );
  }
}

class _InlineLink extends StatelessWidget {
  const _InlineLink(this.text, this.onTap);
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.underline,
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _cooldown = GlobalKey<CooldownBuilderState>();
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (AuthCooldown.isRateLimited(e)) {
        await AuthCooldown.start('reset', AuthCooldown.waitFor(e));
        await _cooldown.currentState?.reload();
      } else if (mounted) {
        showSnack(context, e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Reset password',
      subtitle: _sent
          ? 'If an account exists for ${_email.text.trim()}, a reset link is on its way. Open it on this phone.'
          : 'Enter your email and we’ll send you a link to reset your password.',
      child: _sent
          ? OutlinedButton(onPressed: () => context.pop(), child: const Text('Back to sign in'))
          : Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    validator: Validators.email,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  CooldownBuilder(
                    key: _cooldown,
                    action: 'reset',
                    builder: (context, wait) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PrimaryButton(
                          label: wait == null ? 'Send reset link' : 'Try again in ${formatWait(wait)}',
                          loading: _loading,
                          onPressed: wait == null ? _submit : null,
                        ),
                        if (wait != null) CooldownNotice(remaining: wait, what: 'request a reset link'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Opened from the password-reset email link (Supabase "password recovery").
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).updatePassword(_password.text);
      if (!mounted) return;
      showSnack(context, 'Password updated');
      widget.onDone();
    } catch (e) {
      if (mounted) showSnack(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Choose a new password',
      subtitle: 'Use at least 8 characters with letters and numbers.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PasswordField(controller: _password, label: 'New password', validator: Validators.password),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Save password', loading: _loading, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
