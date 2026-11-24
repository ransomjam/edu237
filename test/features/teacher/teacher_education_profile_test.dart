import 'package:edu237/core/models/teacher_profile.dart';
import 'package:edu237/core/services/location_service.dart';
import 'package:edu237/core/services/teacher_availability_service.dart';
import 'package:edu237/core/services/teacher_profile_service.dart';
import 'package:edu237/features/teacher/edit_teacher_profile_screen.dart';
import 'package:edu237/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fake_teacher_profile_service.dart';

/// Teachers must describe what they teach with the SAME structured catalogue
/// parents and students use — never by typing "Form 4, Physics".
Future<FakeTeacherProfileService> pumpTeacherProfileEditor(
  WidgetTester tester, {
  TeacherProfile? existing,
}) async {
  final store = FakeTeacherStore();
  if (existing != null) store.seed(existing);
  final service = FakeTeacherProfileService(userId: 'teacher-1', store: store);

  await tester.pumpWidget(
    TeacherProfileServiceScope(
      teacherProfileService: service,
      child: TeacherAvailabilityServiceScope(
        service: const UnconfiguredTeacherAvailabilityService(),
        child: LocationServiceScope(
          locationService: const UnavailableLocationService(),
          child: MaterialApp.router(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en')],
            // A real router: saving pops the screen, which needs one.
            routerConfig: GoRouter(
              initialLocation: '/edit',
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, __) => const Scaffold(body: Text('done')),
                  // Nested, so the editor sits on a stack it can pop from.
                  routes: [
                    GoRoute(
                      path: 'edit',
                      builder: (_, __) =>
                          EditTeacherProfileScreen(existing: existing),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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
  group('Teacher onboarding uses the shared hierarchy', () {
    testWidgets('asks for system, then cycle, then classes and subjects',
        (tester) async {
      // Tall surface so the whole (deliberately long) profile form lays out.
      tester.view.physicalSize = const Size(1000, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final service = await pumpTeacherProfileEditor(tester);

      expect(find.text('What do you teach?'), findsOneWidget);
      expect(find.text('Education system'), findsOneWidget);

      // Nothing below the system question is offered until it is answered.
      expect(find.text('Choose a cycle first.'), findsOneWidget);

      await _tap(tester, find.text('English Subsystem'));
      expect(find.text('English · Secondary School'), findsOneWidget);

      await _tap(tester, find.text('Ordinary Level'));

      // Classes for the chosen cycle only.
      expect(find.text('Form 4'), findsOneWidget);
      expect(find.text('Lower Sixth'), findsNothing);
      await _tap(tester, find.text('Form 4'));
      await _tap(tester, find.text('Form 5'));

      // Subjects come from the same catalogue as the learner side.
      await _tap(tester, find.text('Mathematics'));
      await _tap(tester, find.text('Physics'));

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Your name'), 'Mrs Nkeng');
      await _tap(tester, find.widgetWithText(ElevatedButton, 'Save profile'));

      final saved = service.store.forUser('teacher-1')!;
      expect(saved.levelCodes.toSet(),
          {'en.sec.ol.form4', 'en.sec.ol.form5'});
      expect(saved.subjects.toSet(), {'Mathematics', 'Physics'});
      // The label mirror is derived, never typed.
      expect(saved.forms.toSet(), {'Form 4', 'Form 5'});
      expect(saved.subsystems.map((s) => s.code), ['english']);
    });

    testWidgets('a teacher can teach both subsystems at once', (tester) async {
      tester.view.physicalSize = const Size(1000, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final service = await pumpTeacherProfileEditor(tester);

      await _tap(tester, find.text('English Subsystem'));
      await _tap(tester, find.text('French Subsystem'));

      await _tap(tester, find.text('Ordinary Level'));
      await _tap(tester, find.text('Premier Cycle'));

      await _tap(tester, find.text('Form 4'));
      await _tap(tester, find.text('4ème'));

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Your name'), 'Mr Bilingual');
      await _tap(tester, find.widgetWithText(ElevatedButton, 'Save profile'));

      final saved = service.store.forUser('teacher-1')!;
      expect(saved.levelCodes.toSet(), {'en.sec.ol.form4', 'fr.sec.c1.4e'});
      expect(saved.subsystems.map((s) => s.code).toSet(),
          {'english', 'french'});
    });

    testWidgets('dropping a subsystem drops everything chosen under it',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final service = await pumpTeacherProfileEditor(tester);

      await _tap(tester, find.text('French Subsystem'));
      await _tap(tester, find.text('Premier Cycle'));
      await _tap(tester, find.text('4ème'));
      await _tap(tester, find.text('Mathématiques'));

      // Untick French again.
      await _tap(tester, find.text('French Subsystem'));
      expect(find.text('4ème'), findsNothing);
      expect(find.text('Mathématiques'), findsNothing);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Your name'), 'Mr Reset');
      await _tap(tester, find.widgetWithText(ElevatedButton, 'Save profile'));

      final saved = service.store.forUser('teacher-1')!;
      expect(saved.levelCodes, isEmpty);
      expect(saved.subjects, isEmpty);
      expect(saved.forms, isEmpty);
    });

    testWidgets('an existing legacy profile opens fully structured',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Saved before the catalogue existed: labels only, no codes.
      final legacy = TeacherProfile(
        id: 'tp-legacy',
        userId: 'teacher-1',
        displayName: 'Mr Legacy',
        subjects: const ['Mathematics'],
        forms: const ['Form 4'],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      final service = await pumpTeacherProfileEditor(tester, existing: legacy);

      // The English cycle and class are pre-ticked from the old labels.
      expect(find.text('Form 5'), findsOneWidget); // cycle is open
      await _tap(tester, find.widgetWithText(ElevatedButton, 'Save profile'));

      final saved = service.store.forUser('teacher-1')!;
      expect(saved.levelCodes, ['en.sec.ol.form4']);
      expect(saved.forms, ['Form 4']);
    });
  });

  group('TeacherProfile education model', () {
    TeacherProfile profile({
      List<String> levelCodes = const [],
      List<String> forms = const [],
      List<String> seriesCodes = const [],
    }) =>
        TeacherProfile(
          id: 'tp',
          userId: 'u',
          displayName: 'T',
          forms: forms,
          levelCodes: levelCodes,
          seriesCodes: seriesCodes,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('codes win over labels when both are present', () {
      final p = profile(
        levelCodes: ['fr.sec.c1.4e'],
        forms: ['Form 4'], // stale
      );
      expect(p.levels.single.code, 'fr.sec.c1.4e');
      expect(p.toWriteFields()['forms'], ['4ème']);
    });

    test('labels are interpreted when no codes exist', () {
      final p = profile(forms: ['Form 4', 'Form 5']);
      expect(p.levels.map((l) => l.code),
          ['en.sec.ol.form4', 'en.sec.ol.form5']);
    });

    test('an unrecognised label is simply not resolved, never guessed', () {
      final p = profile(forms: ['Form 4', 'Whatever']);
      expect(p.levels.map((l) => l.code), ['en.sec.ol.form4']);
      // A profile with no codes keeps its stored labels verbatim on write —
      // nothing is dropped just because we could not interpret it.
      expect(p.toWriteFields()['forms'], ['Form 4', 'Whatever']);
    });

    test('classes are displayed qualified by subsystem', () {
      final p = profile(levelCodes: ['en.sec.ol.form4', 'fr.sec.c1.4e']);
      expect(p.qualifiedLevelLabels,
          ['English · Form 4', 'French · 4ème']);
    });

    test('teachesLevel is code-based, so labels cannot collide', () {
      final p = profile(levelCodes: ['fr.sec.c1.4e']);
      expect(p.teachesLevel('fr.sec.c1.4e'), isTrue);
      expect(p.teachesLevel('en.sec.ol.form4'), isFalse);
      expect(p.teachesLevel(null), isFalse);
    });
  });
}
