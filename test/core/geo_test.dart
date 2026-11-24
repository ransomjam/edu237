import 'package:edu237/core/services/geo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Geo.distanceKm', () {
    test('is ~0 for the same point', () {
      const p = GeoPoint(3.8480, 11.5021);
      expect(Geo.distanceKm(p, p), closeTo(0, 0.001));
    });

    test('is symmetric', () {
      const a = GeoPoint(3.8480, 11.5021); // Yaoundé
      const b = GeoPoint(4.0511, 9.7679); // Douala
      expect(Geo.distanceKm(a, b), closeTo(Geo.distanceKm(b, a), 0.0001));
    });

    test('Yaoundé → Douala is roughly 200 km', () {
      const yaounde = GeoPoint(3.8480, 11.5021);
      const douala = GeoPoint(4.0511, 9.7679);
      final km = Geo.distanceKm(yaounde, douala);
      expect(km, greaterThan(190));
      expect(km, lessThan(210));
    });
  });

  group('Geo.formatDistance', () {
    test('sub-kilometre rounds to metres', () {
      expect(Geo.formatDistance(0.42), '400 m away');
    });

    test('never shows falsely precise sub-50 m', () {
      expect(Geo.formatDistance(0.01), '50 m away');
    });

    test('one decimal km for >= 1 km', () {
      expect(Geo.formatDistance(1.84), '1.8 km away');
    });

    test('rejects negative / non-finite', () {
      expect(Geo.formatDistance(-1), isNull);
      expect(Geo.formatDistance(double.nan), isNull);
    });
  });
}
