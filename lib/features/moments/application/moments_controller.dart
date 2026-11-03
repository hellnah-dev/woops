import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../chat/application/chat_controllers.dart';
import '../../matches/application/match_insights.dart';
import '../data/moments_repository.dart';

/// Everyone's live moments, one group per person: mine first, then people
/// with something I haven't seen, newest first.
class MomentGroup {
  const MomentGroup(this.moments);

  /// Oldest first, so they play in order.
  final List<Moment> moments;

  Moment get latest => moments.last;
  String get userId => latest.userId;
  String get name => latest.displayName;
  String? get avatar => latest.avatar;
  bool get isMine => latest.isMine;

  bool hasUnseen(Set<String> seen) => moments.any((m) => !seen.contains(m.id));
}

List<MomentGroup> groupMoments(List<Moment> moments, Set<String> seen) {
  final byUser = <String, List<Moment>>{};
  for (final m in moments) {
    byUser.putIfAbsent(m.userId, () => []).add(m);
  }
  final groups = [
    for (final list in byUser.values) MomentGroup(list..sort((a, b) => a.createdAt.compareTo(b.createdAt))),
  ];
  groups.sort((a, b) {
    if (a.isMine != b.isMine) return a.isMine ? -1 : 1;
    final unseen = (b.hasUnseen(seen) ? 1 : 0) - (a.hasUnseen(seen) ? 1 : 0);
    if (unseen != 0) return unseen;
    return b.latest.createdAt.compareTo(a.latest.createdAt);
  });
  return groups;
}

class MomentsController extends AsyncNotifier<List<Moment>> {
  MomentsRepository get _repo => ref.read(momentsRepositoryProvider);

  @override
  Future<List<Moment>> build() async {
    if (ref.watch(currentUserIdProvider) == null) return const [];
    // A new match (or an unmatch) changes whose moments I can see.
    ref.listen(inboxProvider.select(matchIdsKey), (prev, next) {
      if (prev != null && prev != next) refresh();
    });
    await _repo.cleanUpExpired().catchError((_) {});
    return _repo.fetch();
  }

  Future<void> refresh() async {
    final next = await AsyncValue.guard(_repo.fetch);
    // Keep showing what we had if a background refresh fails.
    if (next.hasError && state.hasValue) return;
    state = next;
  }

  Future<void> postText(String text, {int style = 0}) async {
    await _repo.postText(text, style: style);
    await refresh();
  }

  Future<void> postPhoto(Uint8List bytes, {String? caption}) async {
    await _repo.postPhoto(bytes, caption: caption);
    await refresh();
  }

  Future<void> delete(Moment m) async {
    state = AsyncData([
      for (final x in state.valueOrNull ?? const <Moment>[])
        if (x.id != m.id) x,
    ]);
    await _repo.delete(m);
  }
}

final momentsProvider = AsyncNotifierProvider<MomentsController, List<Moment>>(MomentsController.new);

/// Moments this phone has already shown (never sent to the server).
class SeenMoments extends Notifier<Set<String>> {
  static const _key = 'moments_seen';

  @override
  Set<String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = {...state, ...(prefs.getStringList(_key) ?? const [])};
    } catch (_) {}
  }

  Future<void> markSeen(String id) async {
    if (state.contains(id)) return;
    state = {...state, id};
    try {
      final prefs = await SharedPreferences.getInstance();
      // Only live moments matter; drop ids of ones that have expired.
      final live = {for (final m in ref.read(momentsProvider).valueOrNull ?? const <Moment>[]) m.id};
      await prefs.setStringList(_key, (live.isEmpty ? state : state.where(live.contains)).toList());
    } catch (e) {
      debugPrint('Couldn’t remember seen moments: $e');
    }
  }
}

final seenMomentsProvider = NotifierProvider<SeenMoments, Set<String>>(SeenMoments.new);

final momentGroupsProvider = Provider<List<MomentGroup>>((ref) {
  final now = DateTime.now();
  // Moments that expired while the app stayed open disappear on the next rebuild.
  final moments = [
    for (final m in ref.watch(momentsProvider).valueOrNull ?? const <Moment>[])
      if (m.expiresAt.isAfter(now)) m,
  ];
  return groupMoments(moments, ref.watch(seenMomentsProvider));
});
