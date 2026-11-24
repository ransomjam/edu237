import 'package:edu237/core/models/fee_config.dart';
import 'package:edu237/core/models/teacher_verification.dart';
import 'package:edu237/core/models/tutoring_agreement.dart';
import 'package:edu237/core/services/payment_service.dart';
import 'package:edu237/core/services/tutoring_service.dart';
import 'package:edu237/features/payments/activate_relationship_screen.dart';
import 'package:edu237/features/tutoring/review_agreement_screen.dart';
import 'package:edu237/features/tutoring/setup_tutoring_screen.dart';
import 'package:edu237/features/tutoring/teacher_verification_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../payments/fake_payment_services.dart';
import 'fake_tutoring_service.dart';

/// These screens are single-column forms taller than the default 800px test
/// window. A lazily-built ListView only creates the children it can lay out, so
/// the surface is made tall enough for the whole form to exist in the tree.
Future<void> _pump(
  WidgetTester tester, {
  required Widget screen,
  TutoringService? tutoring,
  PaymentService? payments,
}) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    TutoringServiceScope(
      tutoringService: tutoring ?? FakeTutoringService(),
      child: PaymentServiceScope(
        paymentService: payments ?? FakePaymentService(),
        child: MaterialApp(home: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _verified = TeacherVerification(
  teacherId: 'teacher-1',
  status: VerificationStatus.verified,
);

const _setupArgs = SetupTutoringArgs(
  relationshipId: 'rel-1',
  childName: 'Daniel',
  subject: 'Mathematics',
);

void main() {
  // ---------------------------------------------------------------------
  // Verification: a trust gate before anything commercial happens
  // ---------------------------------------------------------------------
  group('Verification', () {
    testWidgets('asks for both documents before it can be sent',
        (tester) async {
      await _pump(tester, screen: const TeacherVerificationScreen());

      expect(find.text('Verification required'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.descendant(
          of: find.byKey(const Key('submit_verification_button')),
          matching: find.byType(ElevatedButton),
        ),
      );
      // Nothing uploaded yet, so there is nothing to send.
      expect(button.onPressed, isNull);
    });

    testWidgets('submitting never calls the teacher verified', (tester) async {
      final service = FakeTutoringService();
      await _pump(
        tester,
        screen: const TeacherVerificationScreen(),
        tutoring: service,
      );

      // Whatever the client does, only Camiva can approve.
      await service.submitVerification(
        identityDocPath: 'p/id.jpg',
        identityDocType: IdentityDocType.nationalId,
        qualificationDocPath: 'p/cert.jpg',
      );
      expect(service.verification.status, VerificationStatus.pending);
      expect(service.verification.status.isVerified, isFalse);
    });

    testWidgets('a pending teacher is told to wait, not that they are verified',
        (tester) async {
      await _pump(
        tester,
        screen: const TeacherVerificationScreen(),
        tutoring: FakeTutoringService(
          verification: const TeacherVerification(
            teacherId: 'teacher-1',
            status: VerificationStatus.pending,
          ),
        ),
      );

      expect(find.byKey(const Key('verification_pending')), findsOneWidget);
      expect(find.text('Verification pending'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);
    });

    testWidgets('a rejection shows what needs correcting', (tester) async {
      await _pump(
        tester,
        screen: const TeacherVerificationScreen(),
        tutoring: FakeTutoringService(
          verification: const TeacherVerification(
            teacherId: 'teacher-1',
            status: VerificationStatus.rejected,
            rejectionReason: 'The ID photo is blurred.',
          ),
        ),
      );

      expect(find.text('Needs correction'), findsOneWidget);
      expect(find.text('The ID photo is blurred.'), findsOneWidget);
    });

    testWidgets('a verified teacher can continue', (tester) async {
      await _pump(
        tester,
        screen: const TeacherVerificationScreen(),
        tutoring: FakeTutoringService(verification: _verified),
      );

      expect(find.byKey(const Key('verification_verified')), findsOneWidget);
      expect(find.byKey(const Key('verification_continue_button')),
          findsOneWidget);
    });

    test('an unverified teacher cannot propose tutoring', () async {
      final service = FakeTutoringService();
      final result = await service.proposeAgreement(
        relationshipId: 'rel-1',
        subject: 'Mathematics',
        startDate: DateTime(2026, 8, 18),
        frequency: LessonFrequency.twiceWeekly,
        lessonsPerWeek: 2,
        lessonMinutes: 60,
        price: 5000,
        priceUnit: PriceUnit.perLesson,
        teachingMode: TeachingModeChoice.inPerson,
      );

      expect(result, isA<TutoringFailure>());
      expect(service.proposals, isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  // Proposal
  // ---------------------------------------------------------------------
  group('SetupTutoringScreen', () {
    testWidgets('the child comes from the relationship and is not selectable',
        (tester) async {
      await _pump(
        tester,
        screen: const SetupTutoringScreen(args: _setupArgs),
        tutoring: FakeTutoringService(verification: _verified),
      );

      expect(find.text('Daniel'), findsOneWidget);
      // No student picker exists: a teacher cannot propose for another child.
      expect(find.byType(DropdownButton<String>), findsNothing);
    });

    testWidgets('cannot send without a price', (tester) async {
      await _pump(
        tester,
        screen: const SetupTutoringScreen(args: _setupArgs),
        tutoring: FakeTutoringService(verification: _verified),
      );

      final button = tester.widget<ElevatedButton>(
        find.descendant(
          of: find.byKey(const Key('send_proposal_button')),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('sends exactly the terms chosen', (tester) async {
      final service = FakeTutoringService(verification: _verified);
      await _pump(
        tester,
        screen: const SetupTutoringScreen(args: _setupArgs),
        tutoring: service,
      );

      await tester.enterText(find.byKey(const Key('price_field')), '5000');
      await tester.tap(find.byKey(const Key('duration_60')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('price_unit_per_lesson')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('send_proposal_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send_proposal_button')));
      await tester.pumpAndSettle();

      expect(service.proposals, hasLength(1));
      final proposal = service.proposals.single;
      expect(proposal['price'], 5000);
      expect(proposal['priceUnit'], PriceUnit.perLesson);
      expect(proposal['lessonMinutes'], 60);
      expect(proposal['lessonsPerWeek'], 2);
      expect(proposal['relationshipId'], 'rel-1');
    });

    testWidgets('payment is Camiva-managed, and there is nothing to choose',
        (tester) async {
      final service = FakeTutoringService(verification: _verified);
      await _pump(
        tester,
        screen: const SetupTutoringScreen(args: _setupArgs),
        tutoring: service,
      );

      // The teacher agreed to Camiva-managed payments when they accepted the
      // request, so offering an alternative here would contradict that.
      expect(find.byKey(const Key('edu237_payment_note')), findsOneWidget);
      expect(find.byKey(const Key('payment_method_direct')), findsNothing);
      expect(find.text('Direct to you'), findsNothing);

      await tester.enterText(find.byKey(const Key('price_field')), '5000');
      await tester.ensureVisible(find.byKey(const Key('send_proposal_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send_proposal_button')));
      await tester.pumpAndSettle();

      expect(service.proposals.single['paymentMethod'],
          AgreementPaymentMethod.edu237);
    });

    testWidgets('says what Camiva-managed payment does for the teacher',
        (tester) async {
      await _pump(
        tester,
        screen: const SetupTutoringScreen(args: _setupArgs),
        tutoring: FakeTutoringService(verification: _verified),
      );

      // The practical benefit, not a policy statement.
      expect(find.textContaining('Camiva follows up on payment so you do not'),
          findsOneWidget);
      expect(find.textContaining('commission'), findsNothing);
    });

    testWidgets('an in-person arrangement asks for an area, not an address',
        (tester) async {
      await _pump(
        tester,
        screen: const SetupTutoringScreen(args: _setupArgs),
        tutoring: FakeTutoringService(verification: _verified),
      );

      expect(find.text('Area'), findsOneWidget);
      expect(find.textContaining('never a full home address'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------
  // Parent review and confirmation
  // ---------------------------------------------------------------------
  group('ReviewAgreementScreen', () {
    testWidgets('shows the whole arrangement in the terms a parent reads',
        (tester) async {
      await _pump(
        tester,
        screen: ReviewAgreementScreen(
          agreement: fakeAgreement(),
          childName: 'Daniel',
          teacherName: 'Jam Ransom',
        ),
        tutoring: FakeTutoringService(expected: fakeExpected()),
      );

      // The name appears as the headline and again in the contract card.
      expect(find.text('Daniel'), findsWidgets);
      expect(find.text('Mathematics with Jam Ransom'), findsOneWidget);
      expect(find.text('18 Aug 2026'), findsWidgets);
      expect(find.text('2 lessons/week'), findsOneWidget);
      expect(find.text('1 hour'), findsOneWidget);
      expect(find.text('5,000 FCFA / lesson'), findsOneWidget);
      expect(find.text('In person · Bastos'), findsOneWidget);
      expect(find.text('Camiva-managed'), findsWidgets);
      expect(find.text('10,000 FCFA'), findsOneWidget);
    });

    testWidgets('says payment happens through the app', (tester) async {
      await _pump(
        tester,
        screen: ReviewAgreementScreen(
          agreement: fakeAgreement(),
          childName: 'Daniel',
          teacherName: 'Jam Ransom',
        ),
        tutoring: FakeTutoringService(expected: fakeExpected()),
      );

      expect(find.textContaining('Pay through the Camiva app'), findsOneWidget);
    });

    testWidgets('confirming records it and hands over to the teacher',
        (tester) async {
      final service = FakeTutoringService(expected: fakeExpected());
      await _pump(
        tester,
        screen: ReviewAgreementScreen(
          agreement: fakeAgreement(),
          childName: 'Daniel',
          teacherName: 'Jam Ransom',
        ),
        tutoring: service,
      );

      await tester.ensureVisible(
          find.byKey(const Key('confirm_agreement_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_agreement_button')));
      await tester.pumpAndSettle();

      expect(service.confirmed, ['agr-1']);
      // The parent is not asked to do anything else.
      expect(find.byKey(const Key('awaiting_activation')), findsOneWidget);
      expect(find.text('Waiting for teacher activation'), findsOneWidget);
      expect(find.text('Camiva is finalising your tutoring connection.'),
          findsOneWidget);
    });

    testWidgets('declining is recorded and does not confirm', (tester) async {
      final service = FakeTutoringService(expected: fakeExpected());
      await _pump(
        tester,
        screen: ReviewAgreementScreen(
          agreement: fakeAgreement(),
          childName: 'Daniel',
          teacherName: 'Jam Ransom',
        ),
        tutoring: service,
      );

      await tester.ensureVisible(
          find.byKey(const Key('decline_agreement_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('decline_agreement_button')));
      await tester.pumpAndSettle();

      expect(service.declined, hasLength(1));
      expect(service.confirmed, isEmpty);
    });

    testWidgets('a direct arrangement says what it does not include',
        (tester) async {
      await _pump(
        tester,
        screen: ReviewAgreementScreen(
          agreement:
              fakeAgreement(paymentMethod: AgreementPaymentMethod.direct),
          childName: 'Daniel',
          teacherName: 'Jam Ransom',
        ),
        tutoring: FakeTutoringService(
          expected: fakeExpected(isCamivaManaged: false),
        ),
      );

      expect(find.text('Direct to teacher'), findsWidgets);
      expect(find.textContaining('not recorded in your Camiva payment history'),
          findsOneWidget);
      // No Camiva due date is promised for money Camiva does not handle.
      expect(find.text('Next payment'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------
  // There is no charge to start a relationship
  // ---------------------------------------------------------------------
  group('No relationship charge', () {
    testWidgets('a teacher is never asked to pay to start tutoring',
        (tester) async {
      final payments = FakePaymentService(
        activationState: ActivationState.notRequired,
      );
      await _pump(
        tester,
        screen: const ActivateRelationshipScreen(
          args: ActivateRelationshipArgs(
            relationshipId: 'rel-1',
            childName: 'Daniel',
            subject: 'Mathematics',
          ),
        ),
        payments: payments,
      );

      // Nothing to pay, and nothing started.
      expect(find.byKey(const Key('pay_button')), findsNothing);
      expect(payments.startCalls, isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  // Activation state
  // ---------------------------------------------------------------------
  group('ActivationState', () {
    test('no charge means every relationship is operational once accepted', () {
      expect(ActivationState.notRequired.isOperational, isTrue);
      expect(ActivationState.notRequired.needsPayment, isFalse);
    });
  });

  // ---------------------------------------------------------------------
  // Agreement terms
  // ---------------------------------------------------------------------
  group('TutoringAgreement', () {
    test('reads the way a parent would say it', () {
      final a = fakeAgreement();
      expect(a.frequencyLabel, '2 lessons/week');
      expect(a.durationLabel, '1 hour');
      expect(a.formattedPrice, '5,000 FCFA / lesson');
      expect(a.modeLabel, 'In person · Bastos');
    });

    test('an online arrangement carries no location', () {
      final a = fakeAgreement(
        teachingMode: TeachingModeChoice.online,
        locationArea: null,
      );
      expect(a.modeLabel, 'Online');
    });

    test('confirmed is not live: activation still has to happen', () {
      expect(fakeAgreement(status: AgreementStatus.confirmed)
          .status
          .awaitingActivation, isTrue);
      expect(fakeAgreement(status: AgreementStatus.confirmed).status.isLive,
          isFalse);
      expect(fakeAgreement(status: AgreementStatus.active).status.isLive,
          isTrue);
    });
  });
}
