import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/utils/app_exception.dart';
import 'profile_repository.dart';

/// Gets a coarse position (only ever stored rounded to ~1 km on the server).
class LocationService {
  LocationService(this._profiles);
  final ProfileRepository _profiles;

  /// Asks for permission if needed and saves the approximate location.
  /// Throws [AppException] with a helpful message when not possible.
  Future<Position> updateMyLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const AppException('Location services are turned off. Turn them on in your phone settings.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const AppException('Location permission was not granted.', code: 'location_denied');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const AppException(
        'Location is blocked for Woops. Enable it in Settings to see people nearby.',
        code: 'location_denied_forever',
      );
    }
    final position = await _freshPosition();
    await _profiles.setLocation(lat: position.latitude, lng: position.longitude);
    return position;
  }

  /// Low accuracy (about 1 km, from Wi-Fi and cell towers): enough for "km
  /// away", easier on the battery, and the server rounds what it stores to
  /// ~1 km anyway. Falls back to the last known fix.
  Future<Position> _freshPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 12)),
      );
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      throw const AppException('Couldn’t get your location. Try again outdoors or check location settings.');
    }
  }

  /// Quietly refreshes the saved location if permission was already given.
  /// Never prompts. Returns the position, or null if not allowed.
  Future<Position?> refreshIfAllowed() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) return null;
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      return await updateMyLocation();
    } catch (_) {
      return null;
    }
  }

  Future<bool> openSettings() => Geolocator.openAppSettings();
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => LocationService(ref.watch(profileRepositoryProvider)),
);
