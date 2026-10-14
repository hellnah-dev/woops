import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/supabase/supabase_providers.dart';

class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  /// Returns true when the user is signed in immediately, false when they must
  /// first confirm their email (depends on Supabase "Confirm email" setting).
  Future<bool> signUp({required String email, required String password}) async {
    final res = await _auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: Env.authRedirectUrl,
    );
    return res.session != null;
  }

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
