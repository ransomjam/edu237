import 'package:edu237/app.dart';
import 'package:edu237/core/models/student.dart';
import 'package:edu237/core/models/teacher_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/stub_auth_service.dart';
import '../children/fake_student_service.dart';
import '../onboarding/stub_profile_service.dart';
import 'fake_teacher_profile_service.dart';

import '../requests/fake_teacher_request_service.dart';

Student _daniel() => Student(
      id: 'daniel-1',
      parentId: testUser.id,
      name: 'Daniel',
      schoolLevel: 'Form 4',
      subjects: const ['Mathematics', 'Physics'],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

TeacherProfile _t(String name,
        {required List<String> forms, required List<String> subjects}) =>
    TeacherProfile(
      id: name,
      userId: 'u-$name',
      displayName: name,
      subjects: subjects,
      forms: forms,
      bio: '$name bio',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Future<void> pumpParent(WidgetTester tester) async {
  // Use a taller viewport (same width as the default 800×600) so the richer
  // discovery cards all render — a ListView lazily skips building off-screen
  // children. Keeping the width avoids exercising unrelated screens at a narrow
  // width they weren't designed for.
  tester.view.physicalSize = const Size(800, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final students = FakeStudentService(parentId: testUser.id)..seed(_daniel());
  final store = FakeTeacherStore()
    ..seed(_t('Teacher A', forms: ['Form 4'], subjects: ['Mathematics', 'Physics']))
    ..seed(_t('Teacher B', forms: ['Form 1'], subjects: ['Biology']))
    ..seed(_t('Teacher C', forms: ['Form 4'], subjects: ['History']))
    ..seed(_t('Teacher D', forms: ['Form 4'], subjects: ['Mathematics']));
  
  final requests = FakeTeacherRequestService(userId: testUser.id);

  await tester.pumpWidget(
    CamivaApp(
      authService: StubAuthService(currentUserResult: testUser),
      profileService: StubProfileService(),
      studentService: students,
      teacherProfileService:
          FakeTeacherProfileService(userId: testUser.id, store: store),
      teacherRequestService: requests,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Home Screen child card shows Find a Teacher and opens discovery',
      (tester) async {
    await pumpParent(tester);

    // Home screen card has a prominent Find a teacher action.
    expect(find.byKey(const Key('find_teacher_button')), findsOneWidget);

    await _tap(tester, find.byKey(const Key('find_teacher_button')));

    // Discovery renders, scoped to Daniel.
    expect(find.text('Find a teacher for Daniel'), findsOneWidget);
  });

  testWidgets('discovery ranks relevant teachers and excludes irrelevant ones',
      (tester) async {
    await pumpParent(tester);
    await _tap(tester, find.text('Find a teacher').first);

    // A, D, C are shown; B (Form 1, Biology) is excluded.
    expect(find.text('Teacher A'), findsOneWidget);
    expect(find.text('Teacher D'), findsOneWidget);
    expect(find.text('Teacher C'), findsOneWidget);
    expect(find.text('Teacher B'), findsNothing);
  });

  testWidgets(
      'tapping a teacher opens their profile with a request button',
      (tester) async {
    await pumpParent(tester);
    await _tap(tester, find.text('Find a teacher').first);

    await _tap(tester, find.text('Teacher A'));

    // Teacher profile shows details + the request button for this child.
    expect(find.text('Teacher A'), findsWidgets); // app bar + body
    expect(find.text('Mathematics'), findsWidgets);
    expect(find.text('Request to teach Daniel'), findsOneWidget);
  });

  testWidgets('request button creates a request and changes to pending',
      (tester) async {
    await pumpParent(tester);
    await _tap(tester, find.text('Find a teacher').first);
    await _tap(tester, find.text('Teacher A'));

    await _tap(
        tester, find.widgetWithText(ElevatedButton, 'Request to teach Daniel'));

    // Request is sent, snackbar appears.
    expect(find.text('Request sent'), findsOneWidget);
    
    // Button changes to pending and is disabled (ElevatedButton without onPressed).
    expect(find.text('Request pending'), findsOneWidget);
    
    // A cancel button is also shown.
    expect(find.text('Cancel request'), findsOneWidget);
  });
}
