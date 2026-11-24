import 'package:edu237/core/models/student.dart';
import 'package:edu237/core/services/student_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../children/fake_student_service.dart';

/// The rule this file exists to protect: a real child is ONE `students` row.
/// A parent-created child who later gets their own login must attach to that
/// row, never spawn a second one.
Student _grace() => Student(
      id: 'grace-1',
      parentId: 'parent-1',
      name: 'Grace',
      levelCode: 'en.sec.ol.form4',
      schoolLevel: 'Form 4',
      subjects: const ['Mathematics'],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('Issuing a link code', () {
    test('a parent can issue a code for a child with no login', () async {
      final service = FakeStudentService(parentId: 'parent-1')..seed(_grace());

      final result = await service.createLinkCode('grace-1');

      expect(result, isA<StudentSuccess>());
      final student = (result as StudentSuccess).student;
      expect(student.linkCode, isNotNull);
      expect(student.hasPendingLinkCode, isTrue);
      expect(student.hasAccount, isFalse);
      // Still exactly one learner record.
      expect(service.students.length, 1);
    });

    test('a child who already has a login is not given a code', () async {
      final service = FakeStudentService(parentId: 'parent-1')
        ..seed(_grace().copyWith(userId: 'already-linked'));

      final result = await service.createLinkCode('grace-1');

      expect(result, isA<StudentFailure>());
      expect((result as StudentFailure).message,
          contains('already has their own login'));
    });

    test('a parent cannot issue a code for a child they do not own', () async {
      final service = FakeStudentService(parentId: 'other-parent')
        ..seed(_grace());

      expect(await service.createLinkCode('grace-1'), isA<StudentFailure>());
    });
  });

  group('Claiming a link code', () {
    test('claiming attaches the account to the EXISTING record', () async {
      final parentSide = FakeStudentService(parentId: 'parent-1')
        ..seed(_grace());
      final issued =
          (await parentSide.createLinkCode('grace-1') as StudentSuccess)
              .student;

      // The student side sees the same table.
      final studentSide = FakeStudentService(
        parentId: 'parent-1',
        studentUserId: 'grace-account',
      );
      for (final s in parentSide.students) {
        studentSide.seed(s);
      }

      final result =
          await studentSide.linkMyAccountWithCode(issued.linkCode!);

      expect(result, isA<StudentSuccess>());
      final linked = (result as StudentSuccess).student;

      // Same row, now owned by both the parent and the student.
      expect(linked.id, 'grace-1');
      expect(linked.parentId, 'parent-1');
      expect(linked.userId, 'grace-account');
      expect(linked.levelCode, 'en.sec.ol.form4');
      expect(linked.subjects, ['Mathematics']);

      // Critically: no duplicate.
      expect(studentSide.students.length, 1);
    });

    test('the code is consumed and cannot be replayed', () async {
      final service = FakeStudentService(
        parentId: 'parent-1',
        studentUserId: 'grace-account',
      )..seed(_grace());
      final code =
          (await service.createLinkCode('grace-1') as StudentSuccess)
              .student
              .linkCode!;

      expect(await service.linkMyAccountWithCode(code), isA<StudentSuccess>());

      final replay = await service.linkMyAccountWithCode(code);
      expect(replay, isA<StudentFailure>());
      expect(service.students.length, 1);
    });

    test('an unknown code fails rather than creating a record', () async {
      final service = FakeStudentService(
        parentId: 'parent-1',
        studentUserId: 'grace-account',
      )..seed(_grace());

      final result = await service.linkMyAccountWithCode('NOPE99');

      expect(result, isA<StudentFailure>());
      expect(service.students.length, 1);
      expect(service.students.single.hasAccount, isFalse);
    });

    test('an account already linked cannot claim a second child', () async {
      final service = FakeStudentService(
        parentId: 'parent-1',
        studentUserId: 'grace-account',
      )
        ..seed(_grace().copyWith(userId: 'grace-account'))
        ..seed(Student(
          id: 'sam-1',
          parentId: 'parent-1',
          name: 'Sam',
          levelCode: 'en.sec.ol.form2',
          linkCode: 'SAM123',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ));

      final result = await service.linkMyAccountWithCode('SAM123');

      expect(result, isA<StudentFailure>());
      expect((result as StudentFailure).message, contains('already linked'));
      // Sam is untouched.
      expect(
        service.students.firstWhere((s) => s.id == 'sam-1').hasAccount,
        isFalse,
      );
    });
  });

  group('Self-signup without a code', () {
    test('creates one record and never a second for the same account',
        () async {
      final service = FakeStudentService(studentUserId: 'ngwa-account');

      final first = await service.createMyStudentRecord(
        name: 'Ngwa',
        levelCode: 'fr.sec.c1.4e',
      );
      expect(first, isA<StudentSuccess>());

      // Signing up again (retry, double tap, re-entry) returns the same row.
      final second = await service.createMyStudentRecord(
        name: 'Ngwa',
        levelCode: 'fr.sec.c1.4e',
      );
      expect(second, isA<StudentSuccess>());
      expect((second as StudentSuccess).student.id,
          (first as StudentSuccess).student.id);
      expect(service.students.length, 1);
    });

    test('a self-registered learner has no parent until one links them',
        () async {
      final service = FakeStudentService(studentUserId: 'ngwa-account');
      await service.createMyStudentRecord(
          name: 'Ngwa', levelCode: 'fr.sec.c1.4e');

      final student = service.students.single;
      expect(student.hasParent, isFalse);
      expect(student.hasAccount, isTrue);
      expect(student.effectiveSubsystem?.code, 'french');
    });
  });
}
