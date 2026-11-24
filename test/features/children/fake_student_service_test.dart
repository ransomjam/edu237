import 'package:flutter_test/flutter_test.dart';

import 'fake_student_service.dart';
import 'package:edu237/core/services/student_service.dart';

/// These tests document the parent-scoping contract the real
/// SupabaseStudentService + RLS must uphold. The Supabase implementation
/// enforces the same rules server-side (see docs/database/supabase_setup.sql).
void main() {
  test('a created student is associated with the authenticated parent',
      () async {
    final service = FakeStudentService(parentId: 'parent-A');
    final result = await service.createStudent(name: 'Grace', schoolLevel: 'Form 3');

    expect(result, isA<StudentSuccess>());
    expect((result as StudentSuccess).student.parentId, 'parent-A');
  });

  test('a parent retrieves only their own students', () async {
    final service = FakeStudentService(parentId: 'parent-A');
    await service.createStudent(name: 'Grace');

    final result = await service.fetchMyStudents();
    expect(result, isA<StudentListSuccess>());
    final students = (result as StudentListSuccess).students;
    expect(students.length, 1);
    expect(students.single.parentId, 'parent-A');
  });

  test('another parent cannot retrieve a different parent\'s student',
      () async {
    // Parent A creates a child.
    final serviceA = FakeStudentService(parentId: 'parent-A');
    final created =
        (await serviceA.createStudent(name: 'Grace')) as StudentSuccess;

    // Parent B (a separate scope) cannot see or fetch it.
    final serviceB = FakeStudentService(parentId: 'parent-B');
    expect(
      (await serviceB.fetchMyStudents()) as StudentListSuccess,
      isA<StudentListSuccess>().having((r) => r.students, 'students', isEmpty),
    );
    expect(
      await serviceB.fetchStudent(created.student.id),
      isA<StudentFailure>(),
    );
  });

  test('creating a child persists the chosen subjects', () async {
    final service = FakeStudentService(parentId: 'parent-A');
    final result = await service.createStudent(
      name: 'Grace',
      schoolLevel: 'Form 3',
      subjects: const ['Mathematics', 'Biology'],
    );
    final student = (result as StudentSuccess).student;
    expect(student.schoolLevel, 'Form 3');
    expect(student.subjects.toSet(), {'Mathematics', 'Biology'});
  });

  test('creating a child with no subjects yields an empty list', () async {
    final service = FakeStudentService(parentId: 'parent-A');
    final result = await service.createStudent(name: 'Sam', schoolLevel: 'Form 2');
    expect((result as StudentSuccess).student.subjects, isEmpty);
  });

  test('editing a child updates its subjects', () async {
    final service = FakeStudentService(parentId: 'parent-A');
    final created = (await service.createStudent(
      name: 'Grace',
      schoolLevel: 'Form 3',
      subjects: const ['Mathematics'],
    )) as StudentSuccess;

    final updated = (await service.updateStudent(
      studentId: created.student.id,
      name: 'Grace',
      schoolLevel: 'Form 4',
      subjects: const ['Mathematics', 'Physics', 'Chemistry'],
    )) as StudentSuccess;

    expect(updated.student.id, created.student.id);
    expect(updated.student.schoolLevel, 'Form 4');
    expect(updated.student.subjects.toSet(),
        {'Mathematics', 'Physics', 'Chemistry'});

    // Persisted (a re-fetch returns the updated subjects).
    final refetched =
        (await service.fetchStudent(created.student.id)) as StudentSuccess;
    expect(refetched.student.subjects.length, 3);
  });

  test('a parent cannot edit another parent\'s student', () async {
    final serviceA = FakeStudentService(parentId: 'parent-A');
    final created =
        (await serviceA.createStudent(name: 'Grace')) as StudentSuccess;

    final serviceB = FakeStudentService(parentId: 'parent-B');
    final result = await serviceB.updateStudent(
      studentId: created.student.id,
      name: 'Hacked',
      subjects: const ['Mathematics'],
    );
    expect(result, isA<StudentFailure>());
  });
}
