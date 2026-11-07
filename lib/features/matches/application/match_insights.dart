import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../chat/application/chat_controllers.dart';
import '../../chat/domain/chat_models.dart';
import '../../../core/i18n/units.dart';
import '../../profile/domain/profile_enums.dart';

/// What someone is here for, grouped the way people talk about it.
enum MatchMode {
  longTerm('Long-term', '💞'),
  dating('Dating', '🥂'),
  friends('Friends', '👋'),
  open('Open', '🤔');

  const MatchMode(this.label, this.emoji);
  final String label;
  final String emoji;

  static MatchMode of(Intention i) => switch (i) {
    Intention.longTerm || Intention.longTermOpen => MatchMode.longTerm,
    Intention.shortTermOpen || Intention.shortTerm => MatchMode.dating,
    Intention.friends => MatchMode.friends,
    Intention.figuringOut => MatchMode.open,
  };
}

/// Why two people matched: their mode, interests in common, how far.
class MatchInsight {
  const MatchInsight({required this.intention, this.sharedInterests = const [], this.distanceKm});

  final Intention intention;
  final List<String> sharedInterests;
  final int? distanceKm;

  MatchMode get mode => MatchMode.of(intention);

  /// "3 in common · 12 km", or null when there's nothing to say. Close
  /// matches read "Less than 2 km", like on profile cards.
  String? summaryFor({String? regionCode}) {
    final parts = [
      if (sharedInterests.isNotEmpty) '${sharedInterests.length} in common',
      if (distanceKm != null) DistanceUnits.short(distanceKm!, regionCode: regionCode),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String? get summary => summaryFor();

  factory MatchInsight.fromJson(Map<String, dynamic> j) => MatchInsight(
    intention: Intention.fromValue(j['intention'] as String? ?? 'figuring_out'),
    sharedInterests: [for (final s in (j['shared_interests'] as List? ?? const [])) s as String],
    distanceKm: (j['distance_km'] as num?)?.toInt(),
  );
}

/// Insights per matched user id. Reloads when the set of matches changes.
final matchInsightsProvider = FutureProvider<Map<String, MatchInsight>>((ref) async {
  // Only the match ids matter: new messages shouldn't reload this.
  ref.watch(inboxProvider.select(matchIdsKey));
  if (ref.watch(currentUserIdProvider) == null) return const {};
  final rows = await ref.read(supabaseClientProvider).rpc('get_match_insights') as List;
  return {
    for (final r in rows) (r as Map)['other_user_id'] as String: MatchInsight.fromJson(Map<String, dynamic>.from(r)),
  };
});

/// Who I'm matched with, as one sorted string: changes only when a match is
/// added or removed, not when a new message reorders the chat list.
String matchIdsKey(AsyncValue<List<ConversationSummary>> inbox) =>
    ([for (final c in inbox.valueOrNull ?? const <ConversationSummary>[]) c.otherUserId]..sort()).join(',');

/// The mode filter chosen on the Matches tab (null = all).
final matchModeFilterProvider = StateProvider<MatchMode?>((ref) => null);
