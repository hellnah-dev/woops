import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/app_exception.dart';
import '../../profile/domain/profile_models.dart';
import '../data/discovery_repository.dart';

class DiscoveryState {
  const DiscoveryState({
    this.queue = const [],
    this.isLoading = false,
    this.error,
    this.exhausted = false,
    this.lastPassed,
  });

  final List<ProfileCard> queue;
  final bool isLoading;
  final AppException? error;

  /// The server returned no more profiles.
  final bool exhausted;

  /// The most recent pass, which can be undone.
  final ProfileCard? lastPassed;

  ProfileCard? get current => queue.isEmpty ? null : queue.first;
  bool get canUndo => lastPassed != null;

  DiscoveryState copyWith({
    List<ProfileCard>? queue,
    bool? isLoading,
    AppException? error,
    bool clearError = false,
    bool? exhausted,
    ProfileCard? lastPassed,
    bool clearLastPassed = false,
  }) => DiscoveryState(
    queue: queue ?? this.queue,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
    exhausted: exhausted ?? this.exhausted,
    lastPassed: clearLastPassed ? null : (lastPassed ?? this.lastPassed),
  );
}

class DiscoveryController extends Notifier<DiscoveryState> {
  static const pageSize = 20;
  static const prefetchThreshold = 5;

  /// Ids with a swipe request in flight, so double taps never send twice and
  /// prefetched pages never re-add them.
  final Set<String> _inFlight = {};
  bool _fetching = false;

  DiscoveryRepository get _repo => ref.read(discoveryRepositoryProvider);

  @override
  DiscoveryState build() {
    final uid = ref.watch(currentUserIdProvider);
    _inFlight.clear();
    _fetching = false;
    if (uid == null) return const DiscoveryState();
    Future.microtask(() => load(reset: true));
    return const DiscoveryState(isLoading: true);
  }

  Future<void> load({bool reset = false}) async {
    if (_fetching) return;
    _fetching = true;
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      queue: reset ? const [] : null,
      exhausted: reset ? false : null,
    );
    try {
      final page = await _repo.fetchFeed(limit: pageSize);
      final known = {...state.queue.map((c) => c.id), ..._inFlight};
      final fresh = page.where((c) => !known.contains(c.id)).toList();
      state = state.copyWith(queue: [...state.queue, ...fresh], isLoading: false, exhausted: page.length < pageSize);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: AppException.from(e));
    } finally {
      _fetching = false;
    }
  }

  /// Optimistically removes the card, then records the swipe on the server.
  /// Returns the result, or throws [AppException] (the card is restored).
  Future<SwipeResult?> swipe(ProfileCard card, SwipeAction action) async {
    if (_inFlight.contains(card.id)) return null;
    _inFlight.add(card.id);
    state = state.copyWith(queue: state.queue.where((c) => c.id != card.id).toList());
    _maybePrefetch();

    try {
      final result = await _repo.swipe(card.id, action);
      state = action == SwipeAction.pass ? state.copyWith(lastPassed: card) : state.copyWith(clearLastPassed: true);
      return result;
    } catch (e) {
      final error = AppException.from(e);
      // Restore the card unless the profile is gone for good.
      if (error.code != 'unavailable') {
        state = state.copyWith(queue: [card, ...state.queue]);
      }
      throw error;
    } finally {
      _inFlight.remove(card.id);
    }
  }

  Future<void> undo() async {
    final passed = state.lastPassed;
    if (passed == null) return;
    try {
      final restoredId = await _repo.undoLastPass();
      final restored = restoredId == passed.id ? passed : null;
      state = state.copyWith(
        clearLastPassed: true,
        queue: restored == null ? null : [restored, ...state.queue.where((c) => c.id != restored.id)],
      );
      if (restored == null) await load(reset: true);
    } catch (e) {
      state = state.copyWith(clearLastPassed: true);
      throw AppException.from(e);
    }
  }

  void _maybePrefetch() {
    if (!state.exhausted && state.queue.length < prefetchThreshold) {
      load();
    }
  }
}

final discoveryControllerProvider = NotifierProvider<DiscoveryController, DiscoveryState>(DiscoveryController.new);

/// People who liked me (newest first).
final likesReceivedProvider = FutureProvider.autoDispose<List<ProfileCard>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(discoveryRepositoryProvider).fetchLikesReceived(limit: 60);
});
