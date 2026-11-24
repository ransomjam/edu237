import 'package:edu237/core/models/teaching_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TeachingMode', () {
    test('round-trips through its stored value', () {
      for (final mode in TeachingMode.values) {
        expect(TeachingMode.fromString(mode.value), mode);
      }
    });

    test('unknown / null falls back to in person', () {
      expect(TeachingMode.fromString(null), TeachingMode.inPerson);
      expect(TeachingMode.fromString('nonsense'), TeachingMode.inPerson);
    });

    test('capability flags', () {
      expect(TeachingMode.online.supportsOnline, isTrue);
      expect(TeachingMode.online.supportsInPerson, isFalse);
      expect(TeachingMode.inPerson.supportsInPerson, isTrue);
      expect(TeachingMode.inPerson.supportsOnline, isFalse);
      expect(TeachingMode.both.supportsOnline, isTrue);
      expect(TeachingMode.both.supportsInPerson, isTrue);
    });

    test('stored values are the expected snake-case strings', () {
      expect(TeachingMode.online.value, 'online');
      expect(TeachingMode.inPerson.value, 'in_person');
      expect(TeachingMode.both.value, 'both');
    });
  });
}
