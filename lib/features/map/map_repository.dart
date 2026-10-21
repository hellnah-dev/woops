import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';

/// Someone on the map. The position is approximate (snapped to ~2 km by the
/// server), never their real location.
class MapPerson {
  const MapPerson({
    required this.id,
    required this.name,
    required this.age,
    required this.position,
    required this.distanceKm,
    this.photo,
    this.isVerified = false,
    this.matchId,
    this.conversationId,
  });

  final String id;
  final String name;
  final int age;
  final LatLng position;
  final int distanceKm;
  final String? photo;
  final bool isVerified;

  /// Set for matches: tapping them opens the chat.
  final String? matchId;
  final String? conversationId;

  bool get isMatch => conversationId != null;

  factory MapPerson.fromJson(Map<String, dynamic> j) => MapPerson(
    id: j['id'] as String,
    name: j['display_name'] as String,
    age: (j['age'] as num).toInt(),
    position: LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
    distanceKm: (j['distance_km'] as num).toInt(),
    photo: j['photo'] as String?,
    isVerified: j['is_verified'] as bool? ?? false,
    matchId: j['match_id'] as String?,
    conversationId: j['conversation_id'] as String?,
  );
}

class MapData {
  const MapData({required this.me, required this.people, this.matches = const []});

  /// My own saved (rounded) position; null until location is shared.
  final LatLng? me;

  /// People I could meet, nearest first.
  final List<MapPerson> people;

  /// My matches who share their distance, nearest first.
  final List<MapPerson> matches;
}

class MapRepository {
  MapRepository(this._client);
  final SupabaseClient _client;

  /// Everything for the map in one request (`get_map_view`).
  Future<MapData> load() async {
    final j = Map<String, dynamic>.from(await _client.rpc('get_map_view', params: {'p_limit': 50}) as Map);
    final me = j['me'] == null
        ? null
        : LatLng(((j['me'] as Map)['lat'] as num).toDouble(), ((j['me'] as Map)['lng'] as num).toDouble());
    List<MapPerson> list(String key) =>
        ((j[key] as List?) ?? const []).map((r) => MapPerson.fromJson(Map<String, dynamic>.from(r as Map))).toList()
          ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return MapData(me: me, people: list('people'), matches: list('matches'));
  }
}

final mapRepositoryProvider = Provider<MapRepository>((ref) => MapRepository(ref.watch(supabaseClientProvider)));

final mapDataProvider = FutureProvider.autoDispose<MapData>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(mapRepositoryProvider).load();
});
