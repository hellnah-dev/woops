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

  /// People this close are shown as "less than" this, never closer, so
  /// nobody can tell someone lives next door.
  static const nearKm = 2;

  /// "Less than 2 km away" / "12 km away" / "8 mi away". [km] is already
  /// rounded up by the server.
  static String away(int km, {String? regionCode}) => '${short(km, regionCode: regionCode)} away';

  /// "Less than 2 km" / "12 km" / "8 mi", for compact labels.
  static String short(int km, {String? regionCode}) {
    final miles = usesMiles(regionCode);
    if (km <= nearKm) return miles ? 'Less than 2 mi' : 'Less than $nearKm km';
    if (miles) return '${(km / _kmPerMile).ceil().clamp(2, 1 << 30)} mi';
    return '$km km';
  }

  /// Label for a max-distance setting, e.g. "50 km", "31 mi", "Anywhere".
  static String limit(int km, {String? regionCode}) {
    if (km >= anywhereKm) return 'Anywhere';
    if (usesMiles(regionCode)) return '${(km / _kmPerMile).round()} mi';
    return '$km km';
  }
}
