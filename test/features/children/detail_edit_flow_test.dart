import 'package:edu237/app.dart';
import 'package:edu237/core/models/student.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/stub_auth_service.dart';
import '../onboarding/stub_profile_service.dart';
import 'fake_student_service.dart';

Student _grace() => Student(
      id: 'grace-1',
      parentId: testUser.id,
      name: 'Grace',
      schoolLevel: 'Form 3',
      subjects: const ['Mathematics'],
      notes: null,
      createdAt: DateTime(2026, 8, 11),
      updatedAt: DateTime(2026, 8, 11),
    );

Future<FakeStudentService> pumpWithChild(WidgetTester tester) async {
  final service = FakeStudentService(parentId: testUser.id)..seed(_grace());
  await tester.pumpWidget(
    CamivaApp(
      authService: StubAuthService(currentUserResult: testUser),
      profileService: StubProfileService(),
      studentService: service,
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tapping a child card opens the edit child screen', (tester) async {
    await pumpWithChild(tester);

    // Card is visible on Home.
    expect(find.text('Grace'), findsOneWidget);
    await _tap(tester, find.text('Grace'));

    // Edit screen shows title, prefilled name, selected class and subject
    expect(find.text('Edit child'), findsWidgets);
    expect(find.widgetWithText(TextFormField, 'Grace'), findsOneWidget);
    expect(find.text('Form 3'), findsWidgets);
    expect(find.text('Mathematics'), findsWidgets);
  });

  testWidgets('edit screen loads existing values', (tester) async {
    await pumpWithChild(tester);
    await _tap(tester, find.text('Grace'));

    // Name prefilled; existing subject shown as selected chip.
    expect(find.widgetWithText(TextFormField, 'Grace'), findsOneWidget);
    expect(find.text('Mathematics'), findsWidgets);
    expect(find.text('Save changes'), findsOneWidget);
  });

  testWidgets(
      'editing class, subjects and notes saves to the SAME student',
      (tester) async {
    final service = await pumpWithChild(tester);
    await _tap(tester, find.text('Grace'));

    // Change class Form 3 -> Form 4.
    await _tap(tester, find.text('Form 4'));
    // Add a subject.
    await _tap(tester, find.text('Biology'));
    // Add a note.
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Notes (optional)'), 'Needs help');

    await _tap(tester, find.widgetWithText(ElevatedButton, 'Save changes'));

    // Wait for the async reload to finish on Home Screen
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Back on Home with updated info.
    // The card qualifies the class by subsystem so a mixed family is clear.
    expect(find.text('English · Form 4'), findsWidgets);
    expect(find.text('Biology'), findsWidgets);

    // Same student updated, not a new one.
    expect(service.students.length, 1);
    final saved = service.students.single;
    expect(saved.id, 'grace-1');
    expect(saved.parentId, testUser.id);
    // Structured now, with the label kept in step for older screens.
    expect(saved.levelCode, 'en.sec.ol.form4');
    expect(saved.schoolLevel, 'Form 4');
    expect(saved.effectiveSubsystem?.code, 'english');
    expect(saved.subjects.toSet(), {'Mathematics', 'Biology'});
    expect(saved.notes, 'Needs help');
  });

  testWidgets('a subject can be removed during edit', (tester) async {
    final service = await pumpWithChild(tester);
    await _tap(tester, find.text('Grace'));

    // Deselect the pre-selected Mathematics chip.
    await _tap(tester, find.text('Mathematics'));
    await _tap(tester, find.widgetWithText(ElevatedButton, 'Save changes'));

    // Wait for the async reload to finish on Home Screen
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(service.students.single.subjects, isEmpty);
  });
}
