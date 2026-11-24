import 'package:edu237/core/models/parent_teacher_relationship.dart';
import 'package:edu237/core/services/parent_teacher_relationship_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnconfiguredParentTeacherRelationshipService', () {
    late ParentTeacherRelationshipService sut;

    setUp(() =>
        sut = const UnconfiguredParentTeacherRelationshipService());

    test('requestRelationship returns RelationshipFailure', () async {
      final result = await sut.requestRelationship(
        studentId: 'stu-1',
        teacherId: 'teacher-1',
        subject: 'Maths',
        level: 'Form 4',
      );
      expect(result, isA<RelationshipFailure>());
    });

    test('fetchMyRelationshipsAsParent returns RelationshipFailure', () async {
      expect(await sut.fetchMyRelationshipsAsParent(),
          isA<RelationshipFailure>());
    });

    test('fetchMyRelationshipsAsTeacher returns RelationshipFailure', () async {
      expect(await sut.fetchMyRelationshipsAsTeacher(),
          isA<RelationshipFailure>());
    });

    test('updateStatus returns RelationshipFailure', () async {
      final result = await sut.updateStatus(
        relationshipId: 'rel-1',
        status: RelationshipStatus.accepted,
      );
      expect(result, isA<RelationshipFailure>());
    });
  });
}
