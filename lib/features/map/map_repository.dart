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
  });

  final String id;
  final String name;
  final int age;
  final LatLng position;
  final int distanceKm;
  final String? photo;
  final bool isVerified;

  factory MapPerson.fromJson(Map<String, dynamic> j) => MapPerson(
    id: j['id'] as String,
    name: j['display_name'] as String,
    age: (j['age'] as num).toInt(),
    position: LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
    distanceKm: (j['distance_km'] as num).toInt(),
    photo: j['photo'] as String?,
    isVerified: j['is_verified'] as bool? ?? false,
  );
}

class MapData {
  const MapData({required this.me, required this.people});

  /// My own saved (rounded) position; null until location is shared.
  final LatLng? me;

  /// Nearest first.
  final List<MapPerson> people;
}

class MapRepository {
  MapRepository(this._client);
  final SupabaseClient _client;

  Future<MapData> load() async {
    final results = await Future.wait([
      _client.rpc('get_my_location'),
      _client.rpc('get_map_people', params: {'p_limit': 50}),
    ]);
    final meRows = results[0] as List;
    final me = meRows.isEmpty
        ? null
        : LatLng((meRows.first['lat'] as num).toDouble(), (meRows.first['lng'] as num).toDouble());
    final people = (results[1] as List).map((r) => MapPerson.fromJson(Map<String, dynamic>.from(r as Map))).toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return MapData(me: me, people: people);
  }
}

final mapRepositoryProvider = Provider<MapRepository>((ref) => MapRepository(ref.watch(supabaseClientProvider)));

final mapDataProvider = FutureProvider.autoDispose<MapData>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(mapRepositoryProvider).load();
});
