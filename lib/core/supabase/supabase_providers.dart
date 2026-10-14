import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

/// Emits on every sign-in, sign-out and token refresh.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

/// The signed-in user's id, or null. Rebuilds dependants when it changes.
final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseClientProvider).auth.currentUser?.id;
});

/// Builds the URL + auth headers needed to load a file from the private
/// `profile-photos` bucket. Storage RLS decides whether the viewer may see it.
class PhotoUrlResolver {
  const PhotoUrlResolver(this._client);
  final SupabaseClient _client;

  String url(String storagePath) =>
      '${Env.supabaseUrl}/storage/v1/object/authenticated/profile-photos/$storagePath';

  Map<String, String> get headers {
    final token = _client.auth.currentSession?.accessToken;
    return {
      'apikey': Env.supabasePublishableKey,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
}

final photoUrlResolverProvider = Provider<PhotoUrlResolver>((ref) {
  ref.watch(authStateProvider);
  return PhotoUrlResolver(ref.watch(supabaseClientProvider));
});
