import 'package:edu237/core/constants/cameroon_places.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CameroonPlaces.resolve', () {
    test('resolves a known city (case / accent tolerant)', () {
      expect(CameroonPlaces.resolve(city: 'Yaoundé'), isNotNull);
      expect(CameroonPlaces.resolve(city: 'yaounde'), isNotNull);
      expect(CameroonPlaces.resolve(city: 'BAMENDA'), isNotNull);
    });

    test('a known area beats the city centre', () {
      final area = CameroonPlaces.resolve(city: 'Yaoundé', area: 'Bastos');
      final city = CameroonPlaces.resolve(city: 'Yaoundé');
      expect(area, isNotNull);
      expect(city, isNotNull);
      // Bastos is offset from the Yaoundé centroid.
      expect(area != city, isTrue);
    });

    test('unknown place resolves to null (still appears in list elsewhere)', () {
      expect(CameroonPlaces.resolve(city: 'Nowhereville'), isNull);
      expect(CameroonPlaces.resolve(city: null, area: null), isNull);
    });
  });
}
