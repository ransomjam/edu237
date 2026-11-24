import 'package:edu237/core/models/tutoring_agreement.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shapes a composite-returning Postgres function actually produces, and
/// what the app must make of them.
///
/// These are here because the failure mode is silent and confusing: a function
/// that matched nothing returns a row of nulls, not null, and casting that
/// row's id to String throws a bare type error the UI can only report as
/// "something went wrong".
void main() {
  group('composite row shapes', () {
    test('a matched row parses', () {
      final row = TutoringAgreement.fromMap({
        'id': 'agr-1',
        'relationship_id': 'rel-1',
        'parent_id': 'parent-1',
        'teacher_id': 'teacher-1',
        'student_id': 'student-1',
        'subject': 'Mathematics',
        'start_date': '2026-08-18',
        'frequency': 'twice_weekly',
        'lessons_per_week': 2,
        'lesson_minutes': 60,
        'price': 5000,
        'price_unit': 'per_lesson',
        'currency': 'XAF',
        'teaching_mode': 'in_person',
        'location_area': 'Bastos',
        'payment_method': 'edu237',
        'payment_frequency': 'per_month',
        'status': 'proposed',
        'proposed_at': '2026-08-17T10:00:00Z',
      });

      expect(row.id, 'agr-1');
      expect(row.price, 5000);
    });

    test('a row of nulls is not a row', () {
      // What Postgres returns when a composite-returning function matched
      // nothing. Parsing it must never be attempted.
      final allNull = <String, dynamic>{
        'id': null,
        'relationship_id': null,
        'parent_id': null,
        'status': null,
      };

      expect(allNull.values.every((v) => v == null), isTrue);
      // Proof of the failure this guards against.
      expect(() => TutoringAgreement.fromMap(allNull), throwsA(anything));
    });
  });
}
