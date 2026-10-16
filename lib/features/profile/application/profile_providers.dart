import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../data/profile_repository.dart';
import '../domain/profile_models.dart';

/// The signed-in user's profile. `null` = no profile yet (needs onboarding).
class MyProfileController extends AsyncNotifier<MyProfile?> {
  @override
  Future<MyProfile?> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return null;
    return ref.read(profileRepositoryProvider).fetchMyProfile();
  }

  Future<void> refresh() async {
    final next = await AsyncValue.guard(() => ref.read(profileRepositoryProvider).fetchMyProfile());
    // A failed background refresh (e.g. offline on resume) keeps the last good
    // profile; otherwise the router would bounce to the splash error screen.
    if (next.hasError && state.hasValue) return;
    state = next;
  }
}

final myProfileProvider = AsyncNotifierProvider<MyProfileController, MyProfile?>(MyProfileController.new);

final interestsProvider = FutureProvider<List<Interest>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(profileRepositoryProvider).fetchInterests();
});

final discoveryPreferencesProvider = FutureProvider.autoDispose<DiscoveryPreferences>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(profileRepositoryProvider).fetchPreferences();
});

/// Another user's public profile (matches / people who liked you).
final publicProfileProvider = FutureProvider.autoDispose.family<ProfileCard?, String>((ref, userId) {
  return ref.watch(profileRepositoryProvider).fetchPublicProfile(userId);
});

/// My media on the server vs. the 5 MB allowance (profile + chat photos).
final mediaUsageProvider = FutureProvider.autoDispose<({int used, int limit})>((ref) {
  ref.watch(currentUserIdProvider);
  ref.watch(myProfileProvider); // refresh when photos change
  return ref.watch(profileRepositoryProvider).mediaUsage();
});
