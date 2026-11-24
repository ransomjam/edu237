import '../services/geo.dart';

/// A tiny gazetteer of common Cameroon towns / city areas → approximate centre
/// coordinates.
///
/// Purpose: a teacher who has only entered a coarse city/area (no stored
/// coordinates) can still appear on the discovery map, pinned to the APPROXIMATE
/// centre of that place. These are town/neighbourhood centroids — never a
/// residential address — which is exactly the "service area, not home" model the
/// product requires.
///
/// This is intentionally small and hand-maintained for the MVP. It is a
/// convenience fallback, not a geocoder; unknown places simply resolve to null
/// and the teacher still appears in List view.
abstract final class CameroonPlaces {
  /// Approximate centre of each city we know about.
  static const Map<String, GeoPoint> _cities = {
    'yaounde': GeoPoint(3.8480, 11.5021),
    'yaoundé': GeoPoint(3.8480, 11.5021),
    'douala': GeoPoint(4.0511, 9.7679),
    'bamenda': GeoPoint(5.9631, 10.1591),
    'buea': GeoPoint(4.1537, 9.2920),
    'limbe': GeoPoint(4.0186, 9.2147),
    'bafoussam': GeoPoint(5.4781, 10.4176),
    'garoua': GeoPoint(9.3017, 13.3921),
    'maroua': GeoPoint(10.5910, 14.3159),
    'ngaoundere': GeoPoint(7.3167, 13.5833),
    'ngaoundéré': GeoPoint(7.3167, 13.5833),
    'bertoua': GeoPoint(4.5772, 13.6846),
    'ebolowa': GeoPoint(2.9000, 11.1500),
    'kumba': GeoPoint(4.6363, 9.4469),
    'edea': GeoPoint(3.8000, 10.1333),
    'edéa': GeoPoint(3.8000, 10.1333),
    'kribi': GeoPoint(2.9370, 9.9100),
    'dschang': GeoPoint(5.4500, 10.0667),
    'nkongsamba': GeoPoint(4.9547, 9.9404),
    'bali': GeoPoint(5.8886, 10.0186),
    'mbouda': GeoPoint(5.6250, 10.2528),
  };

  /// Well-known neighbourhoods/areas, keyed by "area" → point. These slightly
  /// offset the city centre so multiple teachers in the same city don't all
  /// stack on one pin.
  static const Map<String, GeoPoint> _areas = {
    'bastos': GeoPoint(3.8917, 11.5170), // Yaoundé
    'mvan': GeoPoint(3.8106, 11.5347), // Yaoundé
    'mvog-ada': GeoPoint(3.8560, 11.5260), // Yaoundé
    'biyem-assi': GeoPoint(3.8380, 11.4790), // Yaoundé
    'nkolbisson': GeoPoint(3.8700, 11.4370), // Yaoundé
    'mendong': GeoPoint(3.8250, 11.4770), // Yaoundé
    'essos': GeoPoint(3.8770, 11.5350), // Yaoundé
    'nkwen': GeoPoint(5.9930, 10.1780), // Bamenda
    'mankon': GeoPoint(5.9560, 10.1360), // Bamenda
    'up station': GeoPoint(5.9640, 10.1470), // Bamenda
    'bonanjo': GeoPoint(4.0450, 9.6920), // Douala
    'akwa': GeoPoint(4.0490, 9.7030), // Douala
    'bonaberi': GeoPoint(4.0810, 9.6820), // Douala
    'deido': GeoPoint(4.0680, 9.7060), // Douala
    'molyko': GeoPoint(4.1560, 9.2870), // Buea
    'great soppo': GeoPoint(4.1490, 9.2440), // Buea
  };

  static String _normalise(String? raw) =>
      (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Best-effort approximate coordinate for a coarse [city] / [area].
  ///
  /// Prefers a specific known area, then the city centre. Returns null when we
  /// can't place it — the teacher then simply won't have a map pin from the
  /// gazetteer (they still appear in List view, or on the map if they have
  /// stored coordinates).
  static GeoPoint? resolve({String? city, String? area}) {
    final a = _normalise(area);
    if (a.isNotEmpty && _areas.containsKey(a)) return _areas[a];
    final c = _normalise(city);
    if (c.isNotEmpty && _cities.containsKey(c)) return _cities[c];
    return null;
  }
}
