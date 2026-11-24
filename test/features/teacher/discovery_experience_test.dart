import 'package:edu237/app.dart';
import 'package:edu237/core/models/student.dart';
import 'package:edu237/core/models/teacher_profile.dart';
import 'package:edu237/core/models/teaching_mode.dart';
import 'package:edu237/features/teacher/discovery_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/stub_auth_service.dart';
import '../children/fake_student_service.dart';
import '../onboarding/stub_profile_service.dart';
import '../requests/fake_teacher_request_service.dart';
import 'fake_location_service.dart';
import 'fake_teacher_profile_service.dart';

Student _daniel() => Student(
      id: 'daniel-1',
      parentId: testUser.id,
      name: 'Daniel',
      schoolLevel: 'Form 4',
      subjects: const ['Mathematics', 'Physics'],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

TeacherProfile _t(
  String name, {
  required List<String> forms,
  required List<String> subjects,
  String? city,
  TeachingMode mode = TeachingMode.inPerson,
}) =>
    TeacherProfile(
      id: name,
      userId: 'u-$name',
      displayName: name,
      subjects: subjects,
      forms: forms,
      city: city,
      teachingMode: mode,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Future<void> _pump(
  WidgetTester tester, {
  List<TeacherProfile>? teachers,
}) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final students = FakeStudentService(parentId: testUser.id)..seed(_daniel());
  final store = FakeTeacherStore();
  for (final t in teachers ??
      [
        _t('Alice',
            forms: ['Form 4'],
            subjects: ['Mathematics', 'Physics'],
            city: 'Yaoundé',
            mode: TeachingMode.both),
        _t('Bob',
            forms: ['Form 4'],
            subjects: ['Mathematics'],
            city: 'Bamenda',
            mode: TeachingMode.inPerson),
        _t('Carol',
            forms: ['Form 1'], subjects: ['Biology']), // irrelevant
      ]) {
    store.seed(t);
  }

  await tester.pumpWidget(
    CamivaApp(
      authService: StubAuthService(currentUserResult: testUser),
      profileService: StubProfileService(),
      studentService: students,
      teacherProfileService:
          FakeTeacherProfileService(userId: testUser.id, store: store),
      teacherRequestService: FakeTeacherRequestService(userId: testUser.id),
      locationService: FakeLocationService(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDiscovery(WidgetTester tester) async {
  await tester.tap(find.text('Find a teacher').first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('discovery opens in List view with a beautiful header',
      (tester) async {
    await _pump(tester);
    await _openDiscovery(tester);

    // Header scoped to the child + context line.
    expect(find.text('Find a teacher for Daniel'), findsOneWidget);
    // Map | List toggle present.
    expect(find.byKey(const Key('discovery_view_list')), findsOneWidget);
    expect(find.byKey(const Key('discovery_view_map')), findsOneWidget);

    // Relevant teachers shown; irrelevant one excluded.
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Carol'), findsNothing);

    // Location & role is communicated
    expect(find.textContaining('Home Tutor'), findsWidgets);
    // Matches info is shown
    expect(find.textContaining('Matches:'), findsWidgets);
    expect(find.text('25'), findsNothing);
  });

  testWidgets('can switch from List to Map and back', (tester) async {
    await _pump(tester);
    await _openDiscovery(tester);

    expect(find.byType(FlutterMap), findsNothing);

    await tester.tap(find.byKey(const Key('discovery_view_map')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FlutterMap), findsOneWidget);

    await tester.tap(find.byKey(const Key('discovery_view_list')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FlutterMap), findsNothing);
    expect(find.text('Alice'), findsWidgets);
  });

  testWidgets('empty state guides the parent and can be recovered',
      (tester) async {
    // Only an in-person teacher in Yaoundé exists.
    await _pump(tester, teachers: [
      _t('OnlyInPerson',
          forms: ['Form 4'], subjects: ['Mathematics'], city: 'Yaoundé'),
    ]);
    await _openDiscovery(tester);

    // Apply the Form filter (Form 1) → no results → helpful empty state.
    await tester.tap(find.text('All forms'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Form 1').last);
    await tester.pumpAndSettle();

    expect(find.text('No teachers found nearby'), findsOneWidget);
    expect(find.text('View all teachers'), findsOneWidget);

    // Recover.
    await tester.tap(find.text('View all teachers'));
    await tester.pumpAndSettle();
    expect(find.text('OnlyInPerson'), findsOneWidget);
  });

  testWidgets('teacher with no coordinates still appears in the list',
      (tester) async {
    await _pump(tester, teachers: [
      _t('NoCoords',
          forms: ['Form 4'], subjects: ['Mathematics']), // no city → no pin
    ]);
    await _openDiscovery(tester);

    expect(find.text('NoCoords'), findsOneWidget);
    // WhatsApp & Call buttons are present even when search results appear
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Call Us'), findsOneWidget);
    expect(find.text('Need a teacher for other subjects or specific needs?'), findsOneWidget);
  });

  testWidgets('empty state displays WhatsApp & Call contact and similar matches fallback list',
      (tester) async {
    // Populate database with Bob (Form 4 Math) and Charlie (Form 1 Math)
    await _pump(tester, teachers: [
      _t('Charlie', forms: ['Form 1'], subjects: ['Mathematics'], city: 'Yaoundé'),
    ]);
    await _openDiscovery(tester);

    // Apply Form filter (Form 5) → 0 matching results → Empty state
    await tester.tap(find.text('All forms'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Form 5').last);
    await tester.pumpAndSettle();

    // Verify WhatsApp & Call buttons are visible in Empty State
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Call Us'), findsOneWidget);
    expect(find.text('Contact us directly to allocate a teacher for your specific needs'), findsOneWidget);

    // Verify "Other Teachers in your Area" similar matches section is visible
    expect(find.text('Other Teachers in your Area'), findsOneWidget);
    expect(find.text('Charlie'), findsOneWidget);
  });
}
