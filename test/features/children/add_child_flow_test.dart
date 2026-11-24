import 'package:edu237/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/stub_auth_service.dart';
import '../onboarding/stub_profile_service.dart';
import 'fake_student_service.dart';

/// Pumps the app as an authenticated, onboarded parent (lands on Home).
Future<FakeStudentService> pumpParentApp(WidgetTester tester) async {
  final studentService = FakeStudentService(parentId: testUser.id);
  await tester.pumpWidget(
    CamivaApp(
      authService: StubAuthService(currentUserResult: testUser),
      profileService: StubProfileService(),
      studentService: studentService,
    ),
  );
  await tester.pumpAndSettle();
  return studentService;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _continue(WidgetTester tester) =>
    _tap(tester, find.widgetWithText(ElevatedButton, 'Continue'));

void main() {
  testWidgets('parent with no children sees welcome + add-child action',
      (tester) async {
    await pumpParentApp(tester);

    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Add your child to get started.'), findsOneWidget);
    expect(find.text('Add your child'), findsWidgets);
  });

  testWidgets(
      'English secondary flow: name -> system -> stage -> cycle -> class -> '
      'subjects -> review -> save', (tester) async {
    final service = await pumpParentApp(tester);

    await _tap(tester, find.text('Add your child').first);

    // Step 1 — name. Seven steps for an Ordinary Level child (no series).
    expect(find.text('Step 1 of 7'), findsOneWidget);
    expect(find.text("What is your child's name?"), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, "Child's name"), 'Grace');
    await _continue(tester);

    // Step 2 — education system. Never one giant list of levels.
    expect(find.text('Which education system?'), findsOneWidget);
    expect(find.text('English Subsystem'), findsOneWidget);
    expect(find.text('French Subsystem'), findsOneWidget);
    await _tap(tester, find.text('English Subsystem'));
    await _continue(tester);

    // Step 3 — school stage, in English-subsystem wording.
    expect(find.text('Primary or secondary?'), findsOneWidget);
    expect(find.text('Primary School'), findsOneWidget);
    await _tap(tester, find.text('Secondary School'));
    await _continue(tester);

    // Step 4 — cycle.
    expect(find.text('Which cycle?'), findsOneWidget);
    expect(find.text('Ordinary Level'), findsOneWidget);
    expect(find.text('Advanced Level'), findsOneWidget);
    await _tap(tester, find.text('Ordinary Level'));
    await _continue(tester);

    // Step 5 — class. Only this cycle's classes are offered.
    expect(find.text('Which class?'), findsOneWidget);
    expect(find.text('Form 1'), findsOneWidget);
    expect(find.text('Form 5'), findsOneWidget);
    expect(find.text('Lower Sixth'), findsNothing);
    await _tap(tester, find.text('Form 3'));
    await _continue(tester);

    // Step 6 — subjects, scoped to Ordinary Level.
    expect(find.text('Which subjects?'), findsOneWidget);
    await _tap(tester, find.text('Biology'));
    await _tap(tester, find.text('Chemistry'));
    await _continue(tester);

    // Step 7 — review shows the whole hierarchy before saving.
    expect(find.text('Step 7 of 7'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('English Subsystem'), findsOneWidget);
    expect(find.text('Secondary School · Ordinary Level'), findsOneWidget);
    await _tap(tester, find.widgetWithText(ElevatedButton, 'Save Child'));

    // Back on Home.
    expect(find.text('Grace'), findsOneWidget);

    // Persisted with the structured profile, not just a label.
    expect(service.students.length, 1);
    final saved = service.students.single;
    expect(saved.name, 'Grace');
    expect(saved.parentId, testUser.id);
    expect(saved.levelCode, 'en.sec.ol.form3');
    expect(saved.level?.label, 'Form 3');
    expect(saved.effectiveSubsystem?.code, 'english');
    expect(saved.subjects.toSet(), {'Biology', 'Chemistry'});
  });

  testWidgets('French secondary flow stores a French level, not Form 4',
      (tester) async {
    final service = await pumpParentApp(tester);
    await _tap(tester, find.text('Add your child').first);

    await tester.enterText(
        find.widgetWithText(TextFormField, "Child's name"), 'Ngwa');
    await _continue(tester);

    await _tap(tester, find.text('French Subsystem'));
    await _continue(tester);

    // Stage wording follows the subsystem.
    expect(find.text('Enseignement Secondaire'), findsOneWidget);
    await _tap(tester, find.text('Enseignement Secondaire'));
    await _continue(tester);

    expect(find.text('Premier Cycle'), findsOneWidget);
    expect(find.text('Second Cycle'), findsOneWidget);
    await _tap(tester, find.text('Premier Cycle'));
    await _continue(tester);

    // French classes only — no English forms anywhere.
    expect(find.text('4ème'), findsOneWidget);
    expect(find.text('Form 4'), findsNothing);
    await _tap(tester, find.text('4ème'));
    await _continue(tester);

    // Subjects are in French subsystem wording.
    expect(find.text('Mathématiques'), findsOneWidget);
    expect(find.text('Mathematics'), findsNothing);
    await _tap(tester, find.text('Mathématiques'));
    await _continue(tester);

    await _tap(tester, find.widgetWithText(ElevatedButton, 'Save Child'));

    final saved = service.students.single;
    expect(saved.levelCode, 'fr.sec.c1.4e');
    expect(saved.effectiveSubsystem?.code, 'french');
    expect(saved.subjects, ['Mathématiques']);
  });

  testWidgets('primary skips the cycle question — it has only one cycle',
      (tester) async {
    final service = await pumpParentApp(tester);
    await _tap(tester, find.text('Add your child').first);

    await tester.enterText(
        find.widgetWithText(TextFormField, "Child's name"), 'Ama');
    await _continue(tester);

    await _tap(tester, find.text('English Subsystem'));
    await _continue(tester);

    await _tap(tester, find.text('Primary School'));
    await _continue(tester);

    // Straight to the class question: six steps, not seven.
    expect(find.text('Which cycle?'), findsNothing);
    expect(find.text('Which class?'), findsOneWidget);
    expect(find.text('Step 4 of 6'), findsOneWidget);
    expect(find.text('Class 1'), findsOneWidget);
    expect(find.text('Class 6'), findsOneWidget);

    await _tap(tester, find.text('Class 4'));
    await _continue(tester);
    await _continue(tester); // no subjects
    await _tap(tester, find.widgetWithText(ElevatedButton, 'Save Child'));

    expect(service.students.single.levelCode, 'en.pri.class4');
  });

  testWidgets('Advanced Level asks for a series before subjects',
      (tester) async {
    final service = await pumpParentApp(tester);
    await _tap(tester, find.text('Add your child').first);

    await tester.enterText(
        find.widgetWithText(TextFormField, "Child's name"), 'Daniel');
    await _continue(tester);
    await _tap(tester, find.text('English Subsystem'));
    await _continue(tester);
    await _tap(tester, find.text('Secondary School'));
    await _continue(tester);
    await _tap(tester, find.text('Advanced Level'));
    await _continue(tester);

    expect(find.text('Lower Sixth'), findsOneWidget);
    await _tap(tester, find.text('Upper Sixth'));
    await _continue(tester);

    // Series comes before subjects, grouped Arts / Science.
    expect(find.text('Which series?'), findsOneWidget);
    expect(find.text('Arts'), findsOneWidget);
    expect(find.text('Science'), findsOneWidget);
    expect(find.text('S2'), findsOneWidget);
    await _tap(tester, find.text('S2'));
    await _continue(tester);

    // Subjects are the series suggestion, clearly labelled as a suggestion.
    expect(find.text('Which subjects?'), findsOneWidget);
    expect(
      find.textContaining('Suggested subjects for this series'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Further Mathematics'));
    await _continue(tester);

    await _tap(tester, find.widgetWithText(ElevatedButton, 'Save Child'));

    final saved = service.students.single;
    expect(saved.levelCode, 'en.sec.al.upper6');
    expect(saved.seriesCode, 'en.al.s2');
    expect(saved.subjects, ['Further Mathematics']);
  });

  testWidgets('a child can be saved with no subjects', (tester) async {
    final service = await pumpParentApp(tester);
    await _tap(tester, find.text('Add your child').first);

    await tester.enterText(
        find.widgetWithText(TextFormField, "Child's name"), 'Sam');
    await _continue(tester);
    await _tap(tester, find.text('English Subsystem'));
    await _continue(tester);
    await _tap(tester, find.text('Secondary School'));
    await _continue(tester);
    await _tap(tester, find.text('Ordinary Level'));
    await _continue(tester);
    await _tap(tester, find.text('Form 2'));
    await _continue(tester);
    // Skip picking subjects entirely.
    await _continue(tester);
    await _tap(tester, find.widgetWithText(ElevatedButton, 'Save Child'));

    expect(find.text('Sam'), findsOneWidget);
    expect(service.students.single.subjects, isEmpty);
  });

  testWidgets('name is required before continuing', (tester) async {
    await pumpParentApp(tester);
    await _tap(tester, find.text('Add your child').first);

    await _continue(tester);
    expect(find.text('This field is required.'), findsOneWidget);
    // Still on step 1.
    expect(find.text('Step 1 of 7'), findsOneWidget);
  });

  testWidgets('each education question must be answered before continuing',
      (tester) async {
    await pumpParentApp(tester);
    await _tap(tester, find.text('Add your child').first);

    await tester.enterText(
        find.widgetWithText(TextFormField, "Child's name"), 'Grace');
    await _continue(tester);

    await _continue(tester);
    expect(find.text('Please choose an education system.'), findsOneWidget);

    await _tap(tester, find.text('English Subsystem'));
    await _continue(tester);
    await _continue(tester);
    expect(find.text('Please choose primary or secondary.'), findsOneWidget);

    await _tap(tester, find.text('Secondary School'));
    await _continue(tester);
    await _continue(tester);
    expect(find.text('Please choose a cycle.'), findsOneWidget);

    await _tap(tester, find.text('Ordinary Level'));
    await _continue(tester);
    await _continue(tester);
    expect(find.text('Please choose a class to continue.'), findsOneWidget);
  });

  testWidgets('Back moves to the previous step', (tester) async {
    await pumpParentApp(tester);
    await _tap(tester, find.text('Add your child').first);

    await tester.enterText(
        find.widgetWithText(TextFormField, "Child's name"), 'Grace');
    await _continue(tester);
    expect(find.text('Which education system?'), findsOneWidget);

    await _tap(tester, find.widgetWithText(OutlinedButton, 'Back'));
    expect(find.text('Step 1 of 7'), findsOneWidget);
    expect(find.text("What is your child's name?"), findsOneWidget);
  });
}
