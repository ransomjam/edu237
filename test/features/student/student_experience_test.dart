import 'package:edu237/app.dart';
import 'package:edu237/core/models/student.dart';
import 'package:edu237/core/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/stub_auth_service.dart';
import '../children/fake_student_service.dart';
import '../onboarding/stub_profile_service.dart';

/// The learner record a student account is linked to. Note it is an ordinary
/// `students` row — the same table a parent-managed child lives in.
Student _linkedRecord({
  String levelCode = 'en.sec.ol.form4',
  String? seriesCode,
  List<String> subjects = const ['Mathematics', 'Physics'],
}) =>
    Student(
      id: 'stu-linked',
      // No parent: this learner signed up themselves.
      parentId: '',
      userId: testStudent.id,
      name: testStudent.name,
      levelCode: levelCode,
      seriesCode: seriesCode,
      schoolLevel: 'Form 4',
      subjects: subjects,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
    );

Future<FakeStudentService> pumpStudentApp(
  WidgetTester tester, {
  Student? record,
  ProfileService? profileService,
}) async {
  final service = FakeStudentService(studentUserId: testStudent.id);
  if (record != null) service.seed(record);

  await tester.pumpWidget(
    CamivaApp(
      authService: StubAuthService(currentUserResult: testStudent),
      profileService: profileService ?? StubProfileService(),
      studentService: service,
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

void main() {
  group('Student role routing', () {
    testWidgets('a student lands on the student Home, not a parent dashboard',
        (tester) async {
      await pumpStudentApp(tester, record: _linkedRecord());

      // Their own identity and class.
      expect(find.text('Ngwa Divine'), findsWidgets);
      expect(find.text('English · Form 4'), findsWidgets);

      // Never the parent experience.
      expect(find.text('Add your child'), findsNothing);
      expect(find.text('Welcome'), findsNothing);
    });

    testWidgets('navigation is Home | Learning | Profile — nothing else',
        (tester) async {
      await pumpStudentApp(tester, record: _linkedRecord());

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations.length, 3);

      expect(find.text('Home'), findsWidgets);
      expect(find.text('Learning'), findsWidgets);
      expect(find.text('Profile'), findsWidgets);

      // No money, no requests, no family management.
      expect(find.text('Payments'), findsNothing);
      expect(find.text('Earnings'), findsNothing);
      expect(find.text('Updates'), findsNothing);
    });

    testWidgets('Home shows subjects, teachers, lessons and recent learning',
        (tester) async {
      await pumpStudentApp(tester, record: _linkedRecord());

      expect(find.text('MY SUBJECTS'), findsOneWidget);
      expect(find.text('Mathematics'), findsWidgets);
      expect(find.text('Physics'), findsWidgets);
      expect(find.text('NEXT LESSON'), findsOneWidget);
      expect(find.text('MY TEACHERS'), findsOneWidget);
      expect(find.text('RECENT LEARNING'), findsOneWidget);
    });

    testWidgets('the Learning tab opens the student learning screen',
        (tester) async {
      await pumpStudentApp(tester, record: _linkedRecord());

      await tester.tap(find.text('Learning'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Learning'), findsOneWidget);
    });

    testWidgets('the Profile tab shows the structured academic profile',
        (tester) async {
      await pumpStudentApp(
        tester,
        record: _linkedRecord(
          levelCode: 'en.sec.al.upper6',
          seriesCode: 'en.al.s2',
        ),
      );

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Education system'), findsOneWidget);
      expect(find.text('English Subsystem'), findsOneWidget);
      expect(find.text('Advanced Level'), findsOneWidget);
      expect(find.text('Upper Sixth'), findsOneWidget);
      expect(find.text('Science S2'), findsOneWidget);

      // Still no family management anywhere in the student experience.
      expect(find.text('Add child'), findsNothing);
      expect(find.text('Add your child'), findsNothing);
      expect(find.textContaining('request'), findsNothing);
    });

    testWidgets('a student with no learner record yet is told what to do',
        (tester) async {
      await pumpStudentApp(tester);

      expect(
        find.text('Your student profile is not set up yet'),
        findsOneWidget,
      );
    });
  });

  group('Student profile edits the same record', () {
    testWidgets('updating school details never creates a second learner',
        (tester) async {
      // A tall surface so the whole sheet is laid out at once: dragging a
      // DraggableScrollableSheet to reach a control dismisses it instead.
      tester.view.physicalSize = const Size(1000, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final service =
          await pumpStudentApp(tester, record: _linkedRecord());

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('student_edit_school_details')));
      await tester.pumpAndSettle();

      // The same hierarchy the parent and teacher flows use.
      expect(find.text('Which education system?'), findsOneWidget);

      await tester.tap(find.text('Form 5'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(service.students.length, 1);
      final saved = service.students.single;
      expect(saved.id, 'stu-linked');
      expect(saved.userId, testStudent.id);
      expect(saved.levelCode, 'en.sec.ol.form5');
    });
  });
}
