import 'package:edu237/core/models/teacher_verification.dart';
import 'package:edu237/core/services/admin_service.dart';
import 'package:edu237/features/admin/admin_verifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_admin_service.dart';

Future<void> _pump(WidgetTester tester, AdminService service) async {
  await tester.pumpWidget(
    AdminServiceScope(
      adminService: service,
      child: const MaterialApp(home: AdminVerificationsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fillReason(WidgetTester tester, String value) async {
  await tester.enterText(
      find.byKey(const Key('verification_reason_field')), value);
  await tester.tap(find.byKey(const Key('verification_reason_confirm')));
  await tester.pumpAndSettle();
}

void main() {
  group('AdminVerificationsScreen', () {
    testWidgets('lists teachers waiting with both documents', (tester) async {
      await _pump(
        tester,
        FakeAdminService(verifications: [fakePendingVerification()]),
      );

      expect(find.text('Jam Ransom'), findsOneWidget);
      expect(find.text('National ID'), findsOneWidget);
      expect(find.text('BSc Mathematics'), findsOneWidget);
      expect(find.byKey(const Key('approve_teacher-1')), findsOneWidget);
    });

    testWidgets('opening a document asks for a fresh signed link',
        (tester) async {
      final service =
          FakeAdminService(verifications: [fakePendingVerification()]);
      await _pump(tester, service);

      await tester.tap(find.byKey(const Key('view_id_teacher-1')));
      await tester.pumpAndSettle();

      // The path, never a stored URL — the link is created at the moment an
      // admin looks.
      expect(service.openedDocs, ['teacher-1/id.jpg']);
    });

    testWidgets('a document that cannot be opened says so', (tester) async {
      final service =
          FakeAdminService(verifications: [fakePendingVerification()])
            ..canSignDocs = false;
      await _pump(tester, service);

      await tester.tap(find.byKey(const Key('view_qualification_teacher-1')));
      await tester.pumpAndSettle();

      expect(find.text('Could not open that document.'), findsOneWidget);
    });

    testWidgets('verifying records the decision', (tester) async {
      final service =
          FakeAdminService(verifications: [fakePendingVerification()]);
      await _pump(tester, service);

      await tester.tap(find.byKey(const Key('approve_teacher-1')));
      await tester.pumpAndSettle();

      expect(service.reviewed, hasLength(1));
      expect(service.reviewed.single.approved, isTrue);
      expect(find.text('Jam Ransom is verified.'), findsOneWidget);
    });

    testWidgets('sending documents back requires a reason', (tester) async {
      final service =
          FakeAdminService(verifications: [fakePendingVerification()]);
      await _pump(tester, service);

      await tester.tap(find.byKey(const Key('reject_verification_teacher-1')));
      await tester.pumpAndSettle();
      await _fillReason(tester, '   ');

      // No reason, no decision: the teacher would have nothing to act on.
      expect(service.reviewed, isEmpty);
      expect(find.byKey(const Key('verification_teacher-1')), findsOneWidget);
    });

    testWidgets('a reason is what the teacher will read', (tester) async {
      final service =
          FakeAdminService(verifications: [fakePendingVerification()]);
      await _pump(tester, service);

      await tester.tap(find.byKey(const Key('reject_verification_teacher-1')));
      await tester.pumpAndSettle();
      await _fillReason(tester, 'The ID photo is blurred.');

      expect(service.reviewed.single.approved, isFalse);
      expect(service.reviewed.single.reason, 'The ID photo is blurred.');
    });

    testWidgets('an empty queue says so', (tester) async {
      await _pump(tester, FakeAdminService());
      expect(find.byKey(const Key('admin_no_verifications')), findsOneWidget);
    });

    testWidgets('a non-admin sees no documents or names', (tester) async {
      await _pump(
        tester,
        FakeAdminService(
          isAdmin: false,
          verifications: [fakePendingVerification()],
          failure: 'Not authorised',
        ),
      );

      expect(find.text('Jam Ransom'), findsNothing);
      expect(find.byKey(const Key('view_id_teacher-1')), findsNothing);
      expect(find.text('Could not load verifications'), findsOneWidget);
    });
  });

  group('UnconfiguredAdminService', () {
    test('cannot verify anyone without a backend', () async {
      const sut = UnconfiguredAdminService();
      expect(await sut.fetchPendingVerifications(), isA<AdminFailure>());
      expect(
        await sut.reviewVerification(teacherId: 't1', approve: true),
        isA<AdminFailure>(),
      );
      expect(await sut.verificationDocUrl('t1/id.jpg'), isNull);
    });
  });

  group('PendingVerification', () {
    test('carries document paths, never URLs', () {
      final row = PendingVerification.fromMap({
        'teacher_id': 'teacher-1',
        'teacher_name': 'Jam Ransom',
        'identity_doc_path': 'teacher-1/id.jpg',
        'identity_doc_type': 'passport',
        'qualification_doc_path': 'teacher-1/cert.jpg',
        'qualification_title': 'BSc',
        'submitted_at': '2026-08-19T10:00:00Z',
      });

      expect(row.identityDocType, IdentityDocType.passport);
      expect(row.identityDocPath, isNot(startsWith('http')));
      expect(row.qualificationDocPath, isNot(startsWith('http')));
    });
  });
}
