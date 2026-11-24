import 'package:edu237/core/models/parent_teacher_relationship.dart';
import 'package:edu237/core/models/payment_reminder.dart';
import 'package:edu237/core/models/payment_transaction.dart';
import 'package:edu237/core/models/student.dart';
import 'package:edu237/core/models/teacher_earnings.dart';
import 'package:edu237/core/models/teacher_profile.dart';
import 'package:edu237/core/services/parent_teacher_relationship_service.dart';
import 'package:edu237/core/services/payment_service.dart';
import 'package:edu237/core/services/student_service.dart';
import 'package:edu237/core/services/teacher_profile_service.dart';
import 'package:edu237/features/payments/payment_history_screen.dart';
import 'package:edu237/features/payments/payment_reminders_card.dart';
import 'package:edu237/features/payments/teacher_activity_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../children/fake_student_service.dart';
import '../teacher/fake_teacher_profile_service.dart';
import 'fake_payment_services.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Widget screen,
  required PaymentService paymentService,
  ParentTeacherRelationshipService? relationshipService,
  StudentService? studentService,
  TeacherProfileService? teacherProfileService,
}) async {
  await tester.pumpWidget(
    PaymentServiceScope(
      paymentService: paymentService,
      child: ParentTeacherRelationshipServiceScope(
        relationshipService:
            relationshipService ?? FakeParentRelationshipService(),
        child: StudentServiceScope(
          studentService: studentService ?? FakeStudentService(),
          child: TeacherProfileServiceScope(
            teacherProfileService: teacherProfileService ??
                FakeTeacherProfileService(userId: 'teacher-1'),
            child: MaterialApp(home: Scaffold(body: screen)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A parent with one accepted arrangement: Daniel with Jam Ransom.
({
  ParentTeacherRelationshipService relationships,
  StudentService students,
  TeacherProfileService teachers,
}) _connectedParent() {
  final students = FakeStudentService()
    ..seed(Student(
      id: 'student-1',
      parentId: 'parent-1',
      name: 'Daniel',
      schoolLevel: 'Form 4',
      subjects: const ['Mathematics'],
      createdAt: DateTime(2026, 8, 13),
      updatedAt: DateTime(2026, 8, 13),
    ));

  final store = FakeTeacherStore()
    ..seed(TeacherProfile(
      id: 'tp-1',
      userId: 'teacher-1',
      displayName: 'Jam Ransom',
      title: 'Mr',
      subjects: const ['Mathematics'],
      forms: const ['Form 4'],
      createdAt: DateTime(2026, 8, 13),
      updatedAt: DateTime(2026, 8, 13),
    ));

  return (
    relationships:
        FakeParentRelationshipService(relationships: [fakeRelationship()]),
    students: students,
    teachers: FakeTeacherProfileService(userId: 'parent-1', store: store),
  );
}

PaymentReminder _reminder({
  String id = 'r1',
  ReminderKind kind = ReminderKind.paymentReceived,
  String title = 'Tutoring payment received',
  String body = 'Daniel · Mathematics · 5,000 FCFA',
  DateTime? readAt,
}) =>
    PaymentReminder(
      id: id,
      userId: 'parent-1',
      kind: kind,
      title: title,
      body: body,
      deliveredChannel: 'in_app',
      createdAt: DateTime(2026, 8, 13),
      readAt: readAt,
    );

void main() {
  group('PaymentHistoryScreen', () {
    testWidgets('lists Camiva payments with amount, context and status',
        (tester) async {
      await _pump(
        tester,
        screen: const PaymentHistoryScreen(),
        paymentService: FakePaymentService(payments: [
          fakePayment(),
          fakePayment(
            id: 'pay-2',
            purpose: PaymentPurpose.tutoringPayment,
            status: PaymentStatus.failed,
            amount: 3000,
          ),
        ]),
      );

      expect(find.text('Payments'), findsOneWidget);
      expect(find.text('5,000 FCFA'), findsOneWidget);
      expect(find.text('3,000 FCFA'), findsOneWidget);
      expect(find.text('Daniel · Jam Ransom'), findsNWidgets(2));
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
    });

    testWidgets('opens the receipt for a payment', (tester) async {
      await _pump(
        tester,
        screen: const PaymentHistoryScreen(),
        paymentService: FakePaymentService(payments: [fakePayment()]),
      );

      await tester.tap(find.text('5,000 FCFA'));
      await tester.pumpAndSettle();

      expect(find.text('Payment successful'), findsOneWidget);
      expect(find.text('FAPSHI-123'), findsOneWidget);
    });

    testWidgets(
        'with no teacher and no payments, explains what unlocks the screen — '
        'without shaming payments made outside Camiva', (tester) async {
      await _pump(
        tester,
        screen: const PaymentHistoryScreen(),
        paymentService: FakePaymentService(payments: const []),
      );

      expect(find.byKey(const Key('payments_empty')), findsOneWidget);
      expect(find.textContaining('a teacher accepts your request'),
          findsOneWidget);
      expect(find.textContaining('forbidden'), findsNothing);
      expect(find.textContaining('not allowed'), findsNothing);
      expect(find.textContaining('illegal'), findsNothing);
    });

    testWidgets(
        'a connected parent with no payments yet can still pay from here',
        (tester) async {
      final parent = _connectedParent();
      await _pump(
        tester,
        screen: const PaymentHistoryScreen(),
        paymentService: FakePaymentService(payments: const []),
        relationshipService: parent.relationships,
        studentService: parent.students,
        teacherProfileService: parent.teachers,
      );

      // Not a dead end: the arrangement is offered, and the empty history is
      // explained rather than being the whole screen.
      expect(find.byKey(const Key('payments_empty')), findsNothing);
      expect(find.byKey(const Key('payable_arrangements')), findsOneWidget);
      // SectionHeader renders its title in caps.
      expect(find.text('PAY FOR TUTORING'), findsOneWidget);
      expect(find.text('Daniel'), findsOneWidget);
      expect(find.text('Mathematics · Mr. Jam Ransom'), findsOneWidget);
      expect(find.byKey(const Key('payments_history_empty')), findsOneWidget);
    });

    testWidgets('tapping an arrangement opens the payment for it',
        (tester) async {
      final parent = _connectedParent();
      final payments = FakePaymentService(payments: const [], quote: 5000);
      await _pump(
        tester,
        screen: const PaymentHistoryScreen(),
        paymentService: payments,
        relationshipService: parent.relationships,
        studentService: parent.students,
        teacherProfileService: parent.teachers,
      );

      await tester.tap(find.byKey(const Key('pay_rel-1')));
      await tester.pumpAndSettle();

      expect(find.text("Daniel's tutoring"), findsOneWidget);
      expect(find.text('5,000 FCFA'), findsOneWidget);
      expect(find.text('Pay with Mobile Money'), findsOneWidget);
    });

    testWidgets('offers only accepted arrangements', (tester) async {
      await _pump(
        tester,
        screen: const PaymentHistoryScreen(),
        paymentService: FakePaymentService(payments: const []),
        relationshipService: FakeParentRelationshipService(relationships: [
          fakeRelationship(status: RelationshipStatus.requested),
          fakeRelationship(id: 'rel-2', status: RelationshipStatus.rejected),
        ]),
      );

      expect(find.byKey(const Key('payable_arrangements')), findsNothing);
      expect(find.byKey(const Key('payments_empty')), findsOneWidget);
    });

    testWidgets('shows both the arrangements and the history together',
        (tester) async {
      final parent = _connectedParent();
      await _pump(
        tester,
        screen: const PaymentHistoryScreen(),
        paymentService: FakePaymentService(payments: [fakePayment()]),
        relationshipService: parent.relationships,
        studentService: parent.students,
        teacherProfileService: parent.teachers,
      );

      expect(find.byKey(const Key('payable_arrangements')), findsOneWidget);
      expect(find.text('PAYMENT HISTORY'), findsOneWidget);
      expect(find.text('5,000 FCFA'), findsOneWidget);
      expect(find.byKey(const Key('payments_history_empty')), findsNothing);
    });
  });

  group('PaymentRemindersCard', () {
    testWidgets('shows unread reminders concisely', (tester) async {
      await _pump(
        tester,
        screen: const PaymentRemindersCard(),
        paymentService: FakePaymentService(reminders: [_reminder()]),
      );

      expect(find.byKey(const Key('payment_reminders')), findsOneWidget);
      expect(find.text('Tutoring payment received'), findsOneWidget);
      expect(find.text('Daniel · Mathematics · 5,000 FCFA'), findsOneWidget);
    });

    testWidgets('renders nothing when there is nothing to say — no spam',
        (tester) async {
      await _pump(
        tester,
        screen: const PaymentRemindersCard(),
        paymentService: FakePaymentService(reminders: const []),
      );

      expect(find.byKey(const Key('payment_reminders')), findsNothing);
    });

    testWidgets('does not repeat reminders already read', (tester) async {
      await _pump(
        tester,
        screen: const PaymentRemindersCard(),
        paymentService: FakePaymentService(
          reminders: [_reminder(readAt: DateTime(2026, 8, 13))],
        ),
      );

      expect(find.byKey(const Key('payment_reminders')), findsNothing);
    });

    testWidgets('dismissing marks the reminder read', (tester) async {
      final service = FakePaymentService(reminders: [_reminder()]);
      await _pump(tester,
          screen: const PaymentRemindersCard(), paymentService: service);

      await tester.tap(find.byKey(const Key('dismiss_reminder_r1')));
      await tester.pumpAndSettle();

      expect(service.readReminderIds, ['r1']);
      expect(find.text('Tutoring payment received'), findsNothing);
    });

    testWidgets('caps how many are shown at once', (tester) async {
      await _pump(
        tester,
        screen: const PaymentRemindersCard(maxItems: 2),
        paymentService: FakePaymentService(reminders: [
          _reminder(id: 'r1'),
          _reminder(id: 'r2'),
          _reminder(id: 'r3'),
        ]),
      );

      expect(find.text('Tutoring payment received'), findsNWidgets(2));
    });
  });

  group('TeacherActivityCard', () {
    testWidgets('states transaction history, never quality', (tester) async {
      await _pump(
        tester,
        screen: const TeacherActivityCard(teacherId: 'teacher-1'),
        paymentService: FakePaymentService(
          activity: const TeacherActivity(
            completedPayments: 8,
            activeRelationships: 4,
          ),
        ),
      );

      expect(find.text('Camiva activity'), findsOneWidget);
      expect(find.text('8 completed Camiva tutoring payments'), findsOneWidget);
      expect(find.text('4 active relationships'), findsOneWidget);
      // No claim about how good the teaching is.
      expect(find.textContaining('verified teacher'), findsNothing);
      expect(find.textContaining('rating'), findsNothing);
      expect(find.textContaining('certified'), findsNothing);
    });

    testWidgets('says nothing for a teacher with no Camiva activity yet',
        (tester) async {
      await _pump(
        tester,
        screen: const TeacherActivityCard(teacherId: 'teacher-1'),
        paymentService: FakePaymentService(activity: TeacherActivity.none),
      );

      expect(find.byKey(const Key('teacher_activity_card')), findsNothing);
    });
  });
}
