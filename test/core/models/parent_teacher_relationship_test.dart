import 'package:flutter_test/flutter_test.dart';
import 'package:edu237/core/models/parent_teacher_relationship.dart';

void main() {
  Map<String, dynamic> validRow() => {
        'id': 'rel-1',
        'parent_id': 'parent-1',
        'student_id': 'stu-1',
        'teacher_id': 'teacher-1',
        'subject': 'Mathematics',
        'level': 'Form 4',
        'status': 'requested',
        'created_at': '2023-01-01T00:00:00.000Z',
        'updated_at': '2023-01-01T00:00:00.000Z',
      };

  group('ParentTeacherRelationship', () {
    test('references parent, student, and teacher', () {
      final model = ParentTeacherRelationship.fromMap(validRow());
      expect(model.parentId, 'parent-1');
      expect(model.studentId, 'stu-1');
      expect(model.teacherId, 'teacher-1');
      expect(model.subject, 'Mathematics');
      expect(model.level, 'Form 4');
      expect(model.status, RelationshipStatus.requested);
    });

    test('throws FormatException when a required field is missing', () {
      final row = validRow()..remove('teacher_id');
      expect(
        () => ParentTeacherRelationship.fromMap(row),
        throwsFormatException,
      );
    });

    test('throws FormatException for an unknown status', () {
      final row = validRow()..['status'] = 'archived';
      expect(
        () => ParentTeacherRelationship.fromMap(row),
        throwsFormatException,
      );
    });

    test('a new request always inserts with status = requested', () {
      final model = ParentTeacherRelationship.fromMap(
        validRow()..['status'] = 'accepted',
      );
      final insert = model.toInsertMap(parentId: 'parent-1');
      expect(insert['status'], 'requested');
      expect(insert['parent_id'], 'parent-1');
      expect(insert['student_id'], 'stu-1');
      expect(insert['teacher_id'], 'teacher-1');
    });
  });

  group('RelationshipStatus', () {
    test('parses all lifecycle values', () {
      expect(RelationshipStatus.fromString('requested'),
          RelationshipStatus.requested);
      expect(RelationshipStatus.fromString('accepted'),
          RelationshipStatus.accepted);
      expect(RelationshipStatus.fromString('rejected'),
          RelationshipStatus.rejected);
      expect(RelationshipStatus.fromString('cancelled'),
          RelationshipStatus.cancelled);
      expect(RelationshipStatus.fromString('suspended'),
          RelationshipStatus.suspended);
    });

    test('rejects unknown and null values', () {
      expect(() => RelationshipStatus.fromString('nope'), throwsFormatException);
      expect(() => RelationshipStatus.fromString(null), throwsFormatException);
    });
  });
}
