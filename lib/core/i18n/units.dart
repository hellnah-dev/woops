import 'countries.dart';

/// Distances are stored in km everywhere; only display changes by region.
class DistanceUnits {
  const DistanceUnits._();

  /// The server treats this value as "no distance limit".
  static const anywhereKm = 20000;

  static const _kmPerMile = 1.609344;

  /// Regions that use miles for road distances.
  static const _milesRegions = {'US', 'GB', 'LR', 'MM'};

  static bool usesMiles([String? regionCode]) =>
      _milesRegions.contains((regionCode ?? deviceCountryCode() ?? '').toUpperCase());

  /// "3 km away" / "2 mi away". [km] is already rounded up by the server.
  static String away(int km, {String? regionCode}) {
    if (usesMiles(regionCode)) {
      final miles = (km / _kmPerMile).ceil().clamp(1, 1 << 30);
      return '$miles mi away';
    }
    return '$km km away';
  }

  /// Label for a max-distance setting, e.g. "50 km", "31 mi", "Anywhere".
  static String limit(int km, {String? regionCode}) {
    if (km >= anywhereKm) return 'Anywhere';
    if (usesMiles(regionCode)) return '${(km / _kmPerMile).round()} mi';
    return '$km km';
  }
}
