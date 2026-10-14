import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:intl/intl.dart';

import '../../../core/config/env.dart';
import '../../../core/supabase/supabase_providers.dart';

class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  /// Returns true when the user is signed in immediately, false when they must
  /// first confirm their email (depends on Supabase "Confirm email" setting).
  ///
  /// [birthdate] and [countryCode] from the age gate are stored with the
  /// account; the server rejects a profile whose birthdate doesn't match.
  Future<bool> signUp({
    required String email,
    required String password,
    required DateTime birthdate,
    required String countryCode,
  }) async {
    final res = await _auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: Env.authRedirectUrl,
      data: {
        'birthdate': DateFormat('yyyy-MM-dd').format(birthdate),
        'country_code': countryCode,
      },
    );
    return res.session != null;
  }

  /// Birthdate/country entered at the sign-up age gate, if any.
  ({DateTime? birthdate, String? countryCode}) get ageGateData {
    final meta = _auth.currentUser?.userMetadata ?? const {};
    final b = meta['birthdate'] as String?;
    return (birthdate: b == null ? null : DateTime.tryParse(b), countryCode: meta['country_code'] as String?);
  }

  /// Minimum age for a country (18, or higher where the law requires).
  Future<int> minAgeFor(String countryCode) async {
    try {
      final v = await _client.rpc('min_age_for_country', params: {'p_country': countryCode});
      return (v as num).toInt();
    } catch (_) {
      return 18; // The server still enforces the real rule.
    }
  }

  Future<bool> hasAcceptedLegal() async => await _client.rpc('has_accepted_legal') as bool;

  Future<void> acceptLegal(String version) =>
      _client.rpc('accept_legal_documents', params: {'p_version': version});

  Future<void> signIn({required String email, required String password}) =>
      _auth.signInWithPassword(email: email.trim(), password: password);

  /// Opens the provider's sign-in page in the browser; the app receives the
  /// session through the [Env.authRedirectUrl] deep link.
  Future<void> signInWithProvider(OAuthProvider provider) => _auth.signInWithOAuth(
        provider,
        redirectTo: Env.authRedirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

  Future<void> sendPasswordReset(String email) =>
      _auth.resetPasswordForEmail(email.trim(), redirectTo: Env.authRedirectUrl);

  Future<void> updatePassword(String newPassword) => _auth.updateUser(UserAttributes(password: newPassword));

  Future<void> signOut() => _auth.signOut();
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);
