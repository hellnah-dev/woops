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
  Future<void> updateMyLocation() async {
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
        'Location is blocked for Amora. Enable it in Settings to see people nearby.',
        code: 'location_denied_forever',
      );
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)),
    );
    await _profiles.setLocation(lat: position.latitude, lng: position.longitude);
  }

  Future<bool> openSettings() => Geolocator.openAppSettings();
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => LocationService(ref.watch(profileRepositoryProvider)),
);
