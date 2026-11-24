import 'package:edu237/l10n/app_localizations.dart';
import 'package:edu237/core/models/parent_teacher_relationship.dart';
import 'package:edu237/core/models/student.dart';
import 'package:edu237/core/services/parent_teacher_relationship_service.dart';
import 'package:edu237/core/services/student_service.dart';
import 'package:edu237/features/requests/my_students_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../children/fake_student_service.dart';

/// A minimal fake relationship service for the teacher side.
class _FakeRelationshipService implements ParentTeacherRelationshipService {
  _FakeRelationshipService(this._asTeacher);
  final List<ParentTeacherRelationship> _asTeacher;

  @override
  Future<RelationshipResult> fetchMyRelationshipsAsTeacher() async =>
      RelationshipListSuccess(_asTeacher);

  @override
  Future<RelationshipResult> fetchMyRelationshipsAsParent() async =>
      const RelationshipListSuccess([]);

  @override
  Future<RelationshipResult> fetchRelationshipsForStudent(
          String studentId) async =>
      const RelationshipListSuccess([]);

  @override
  Future<RelationshipResult> requestRelationship({
    required String studentId,
    required String teacherId,
    required String subject,
    required String level,
  }) async =>
      const RelationshipFailure('unused');

  @override
  Future<RelationshipResult> updateStatus({
    required String relationshipId,
    required RelationshipStatus status,
  }) async =>
      const RelationshipFailure('unused');
}

ParentTeacherRelationship _rel(String studentId,
        {RelationshipStatus status = RelationshipStatus.accepted}) =>
    ParentTeacherRelationship(
      id: 'rel-$studentId',
      parentId: 'p1',
      teacherId: 'teacher-1',
      studentId: studentId,
      subject: 'Mathematics',
      level: 'Form 4',
      status: status,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Student _student(String id, String name, String form) => Student(
      id: id,
      parentId: 'p1',
      name: name,
      schoolLevel: form,
      subjects: const ['Mathematics'],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Future<void> _pump(
  WidgetTester tester, {
  required ParentTeacherRelationshipService relService,
  required StudentService studentService,
}) async {
  await tester.pumpWidget(
    ParentTeacherRelationshipServiceScope(
      relationshipService: relService,
      child: StudentServiceScope(
        studentService: studentService,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: const MyStudentsScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'renders the connected student after an accepted relationship '
      '(teacher does not own the student)', (tester) async {
    // The teacher is NOT the parent — fetchStudentsByIds (RLS-scoped) must still
    // surface the connected student. The fake returns seeded students by id.
    final students = FakeStudentService(parentId: 'p1')
      ..seed(_student('s1', 'Daniel', 'Form 4'))
      ..seed(_student('s2', 'Unrelated', 'Form 1'));
    final rel = _FakeRelationshipService([_rel('s1')]);

    await _pump(tester, relService: rel, studentService: students);

    // Connected student card is shown with identity + Connected badge.
    expect(find.text('Daniel'), findsOneWidget);
    // The class is qualified by subsystem, both as a filter chip and on the
    // card, so a teacher never confuses English Form 4 with French 4ème.
    expect(find.text('English · Form 4'), findsWidgets);
    expect(find.text('Connected'), findsOneWidget);
    // The unrelated student (no relationship) must NOT appear.
    expect(find.text('Unrelated'), findsNothing);
  });

  testWidgets('excludes students whose relationship is not accepted',
      (tester) async {
    final students = FakeStudentService(parentId: 'p1')
      ..seed(_student('s1', 'Daniel', 'Form 4'));
    final rel = _FakeRelationshipService(
        [_rel('s1', status: RelationshipStatus.rejected)]);

    await _pump(tester, relService: rel, studentService: students);

    expect(find.text('Daniel'), findsNothing);
    expect(find.text('No students yet'), findsOneWidget);
  });

  testWidgets('empty state appears only when there are no connected students',
      (tester) async {
    final rel = _FakeRelationshipService(const []);
    await _pump(tester,
        relService: rel, studentService: FakeStudentService(parentId: 'p1'));

    expect(find.text('No students yet'), findsOneWidget);
  });

  test('fetchStudentsByIds returns only the requested ids (RLS-scoped read)',
      () async {
    final students = FakeStudentService(parentId: 'p1')
      ..seed(_student('s1', 'Daniel', 'Form 4'))
      ..seed(_student('s2', 'Grace', 'Form 5'));

    final result = await students.fetchStudentsByIds(['s1']);
    expect(result, isA<StudentListSuccess>());
    final list = (result as StudentListSuccess).students;
    expect(list.map((s) => s.name), ['Daniel']);

    final empty = await students.fetchStudentsByIds(const []);
    expect((empty as StudentListSuccess).students, isEmpty);
  });
}
