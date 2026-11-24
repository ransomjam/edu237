import 'dart:math' as math;

/// A plain latitude/longitude pair, independent of any map package so it can be
/// used in pure-Dart logic and tests without importing `latlong2`.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}

/// Geospatial helpers for discovery. Deliberately tiny and dependency-free.
abstract final class Geo {
  static const double _earthRadiusKm = 6371.0088;

  static double _rad(double deg) => deg * math.pi / 180.0;

  /// Great-circle distance in kilometres between two points (Haversine).
  ///
  /// Accurate enough for "how far is this teacher" — we only ever show an
  /// approximate distance, never navigation.
  static double distanceKm(GeoPoint a, GeoPoint b) {
    final dLat = _rad(b.latitude - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final lat1 = _rad(a.latitude);
    final lat2 = _rad(b.latitude);

    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return _earthRadiusKm * c;
  }

  /// A short, parent-friendly distance label, e.g. "800 m away" or "1.8 km
  /// away". Returns null for non-finite input.
  static String? formatDistance(double km) {
    if (!km.isFinite || km < 0) return null;
    if (km < 1.0) {
      final metres = (km * 1000).round();
      // Round to the nearest 50 m so it never looks falsely precise.
      final rounded = ((metres / 50).round() * 50).clamp(50, 950);
      return '$rounded m away';
    }
    return '${km.toStringAsFixed(1)} km away';
  }
}
