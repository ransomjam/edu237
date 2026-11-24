import 'package:edu237/core/services/payment_service.dart';
import 'package:edu237/core/state/app_state.dart';
import 'package:edu237/l10n/app_localizations.dart';
import 'package:edu237/core/models/teacher_profile.dart';
import 'package:edu237/core/models/teacher_request.dart';
import 'package:edu237/core/services/teacher_profile_service.dart';
import 'package:edu237/core/services/teacher_request_service.dart';
import 'package:edu237/features/requests/parent_requests_screen.dart';
import 'package:edu237/features/requests/teacher_requests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../teacher/fake_teacher_profile_service.dart';
import 'fake_teacher_request_service.dart';

TeacherRequest _request({
  required String parentId,
  required String teacherId,
  String status = 'pending',
  String name = 'Daniel',
  String form = 'Form 4',
  List<String> subjects = const ['Mathematics', 'Physics'],
}) =>
    TeacherRequest(
      id: 'req-1',
      parentId: parentId,
      studentId: 's1',
      teacherId: teacherId,
      status: TeacherRequestStatus.fromString(status),
      studentName: name,
      studentForm: form,
      studentSubjects: subjects,
      createdAt: DateTime(2026, 8, 12),
      updatedAt: DateTime(2026, 8, 12),
    );

Future<void> _pump(
  WidgetTester tester, {
  required Widget screen,
  required TeacherRequestService requestService,
  required TeacherProfileService profileService,
}) async {
  await tester.pumpWidget(
    AppStateScope(
      state: AppState(),
      child: PaymentServiceScope(
        paymentService: const UnconfiguredPaymentService(),
        child: TeacherRequestServiceScope(
          requestService: requestService,
          child: TeacherProfileServiceScope(
            teacherProfileService: profileService,
            child: MaterialApp(
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en')],
              home: screen,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('TeacherRequestsScreen (incoming)', () {
    testWidgets('shows child identity, parent label, matched subjects, date',
        (tester) async {
      final store = FakeTeacherStore()
        ..seed(TeacherProfile(
          id: 'tp',
          userId: 'teacher-1',
          displayName: 'Me',
          subjects: const ['Mathematics'],
          forms: const ['Form 4'],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ));
      final requests = FakeTeacherRequestService(userId: 'teacher-1')
        ..seed(_request(parentId: 'p1', teacherId: 'teacher-1'));

      await _pump(
        tester,
        screen: const TeacherRequestsScreen(),
        requestService: requests,
        profileService:
            FakeTeacherProfileService(userId: 'teacher-1', store: store),
      );

      // Child identity from the safe snapshot.
      expect(find.text('Daniel'), findsOneWidget);
      expect(find.text('Parent of Daniel'), findsOneWidget);
      expect(find.text('Form 4'), findsOneWidget);
      expect(find.text('Mathematics'), findsOneWidget);
      expect(find.text('Physics'), findsOneWidget);
      // Matched subject hint (teacher teaches Mathematics).
      expect(find.text('Matches your subjects'), findsOneWidget);
      // Request date.
      expect(find.text('Requested 12 Aug 2026'), findsOneWidget);
      // Actions.
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('accepting a request moves it to accepted', (tester) async {
      final store = FakeTeacherStore()
        ..seed(TeacherProfile(
          id: 'tp',
          userId: 'teacher-1',
          displayName: 'Me',
          subjects: const ['Mathematics'],
          forms: const ['Form 4'],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ));
      final requests = FakeTeacherRequestService(userId: 'teacher-1')
        ..seed(_request(parentId: 'p1', teacherId: 'teacher-1'));

      await _pump(
        tester,
        screen: const TeacherRequestsScreen(),
        requestService: requests,
        profileService:
            FakeTeacherProfileService(userId: 'teacher-1', store: store),
      );

      await tester.tap(find.byKey(const Key('accept_request_req-1')));
      await tester.pumpAndSettle();

      expect(find.text('Accepted'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
    });
  });

  group('ParentRequestsScreen', () {
    testWidgets('shows teacher, child, form, subjects, date and status',
        (tester) async {
      final store = FakeTeacherStore()
        ..seed(TeacherProfile(
          id: 'tp',
          userId: 'u-A',
          displayName: 'Teacher A',
          subjects: const ['Mathematics', 'Physics'],
          forms: const ['Form 4'],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ));
      final requests = FakeTeacherRequestService(userId: 'p1')
        ..seed(_request(parentId: 'p1', teacherId: 'u-A'));

      await _pump(
        tester,
        screen: const ParentRequestsScreen(),
        requestService: requests,
        profileService: FakeTeacherProfileService(userId: 'p1', store: store),
      );

      expect(find.text('Teacher A'), findsOneWidget);
      expect(find.text('For Daniel'), findsOneWidget);
      expect(find.text('Form 4'), findsOneWidget);
      expect(find.text('Mathematics'), findsOneWidget);
      expect(find.text('Requested 12 Aug 2026'), findsOneWidget);
      expect(find.text('Cancel request'), findsOneWidget);
    });

    testWidgets('cancelling a pending request updates its status',
        (tester) async {
      final store = FakeTeacherStore()
        ..seed(TeacherProfile(
          id: 'tp',
          userId: 'u-A',
          displayName: 'Teacher A',
          subjects: const [],
          forms: const [],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ));
      final requests = FakeTeacherRequestService(userId: 'p1')
        ..seed(_request(parentId: 'p1', teacherId: 'u-A'));

      await _pump(
        tester,
        screen: const ParentRequestsScreen(),
        requestService: requests,
        profileService: FakeTeacherProfileService(userId: 'p1', store: store),
      );

      await tester.tap(find.byKey(const Key('cancel_request_req-1')));
      await tester.pumpAndSettle();

      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Cancel request'), findsNothing);
    });
  });
}
