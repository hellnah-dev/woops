import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../profile/domain/profile_models.dart';

enum SwipeAction { like, pass }

class SwipeResult {
  const SwipeResult({required this.matched, this.matchId, this.conversationId});

  final bool matched;
  final String? matchId;
  final String? conversationId;

  factory SwipeResult.fromJson(Map<String, dynamic> json) => SwipeResult(
        matched: json['matched'] as bool? ?? false,
        matchId: json['match_id'] as String?,
        conversationId: json['conversation_id'] as String?,
      );
}

/// Abstract so controllers can be unit-tested with a fake.
abstract class DiscoveryRepository {
  Future<List<ProfileCard>> fetchFeed({int limit = 20});
  Future<SwipeResult> swipe(String targetId, SwipeAction action);
  Future<String> undoLastPass();
  Future<List<ProfileCard>> fetchLikesReceived({int limit = 30, int offset = 0});
}

class SupabaseDiscoveryRepository implements DiscoveryRepository {
  SupabaseDiscoveryRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<ProfileCard>> fetchFeed({int limit = 20}) async {
    final rows = await _client.rpc('get_discovery_feed', params: {'p_limit': limit}) as List;
    return rows.map((r) => ProfileCard.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  @override
  Future<SwipeResult> swipe(String targetId, SwipeAction action) async {
    final res = await _client.rpc('swipe', params: {'p_target': targetId, 'p_action': action.name});
    return SwipeResult.fromJson(Map<String, dynamic>.from(res as Map));
  }

  @override
  Future<String> undoLastPass() async => await _client.rpc('undo_last_swipe') as String;

  @override
  Future<List<ProfileCard>> fetchLikesReceived({int limit = 30, int offset = 0}) async {
    final rows = await _client.rpc('get_likes_received', params: {'p_limit': limit, 'p_offset': offset}) as List;
    return rows.map((r) => ProfileCard.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }
}

final discoveryRepositoryProvider = Provider<DiscoveryRepository>(
  (ref) => SupabaseDiscoveryRepository(ref.watch(supabaseClientProvider)),
);
