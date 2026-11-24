import 'package:edu237/core/models/payment_transaction.dart';
import 'package:edu237/core/models/service_plan.dart';
import 'package:edu237/core/services/payment_service.dart';
import 'package:edu237/core/services/tutoring_service.dart';
import 'package:edu237/features/tutoring/service_plan_screen.dart';
import 'package:edu237/features/tutoring/teacher_terms_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../payments/fake_payment_services.dart';
import 'fake_tutoring_service.dart';

TeacherServicePlan _plan(
  ServicePlanState state, {
  int? amount = 3000,
  DateTime? dueOn,
  DateTime? firstEarnedAt,
}) =>
    TeacherServicePlan(
      state: state,
      amount: amount,
      currency: 'XAF',
      dueOn: dueOn,
      firstEarnedAt: firstEarnedAt,
    );

Future<void> _pumpPlan(WidgetTester tester, TeacherServicePlan plan,
    {FakePaymentService? payments}) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    TutoringServiceScope(
      tutoringService: FakeTutoringService(plan: plan),
      child: PaymentServiceScope(
        paymentService: payments ?? FakePaymentService(quote: 3000),
        child: const MaterialApp(home: ServicePlanScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Teacher terms', () {
    testWidgets('are shown before accepting, and acceptance requires the tick',
        (tester) async {
      // The sheet is taller than the default test window.
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  await showTeacherTermsSheet(
                    context,
                    childName: 'Daniel',
                    planAmount: '3,000 FCFA',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('teacher_terms_sheet')), findsOneWidget);
      expect(find.text('Camiva Teacher Terms'), findsOneWidget);

      // The commitment is stated plainly, with the amount.
      expect(
        find.textContaining(
            'Teacher Service Plan of 3,000 FCFA/month is required'),
        findsOneWidget,
      );
      // And so is the thing teachers most need to know.
      expect(find.textContaining('You pay nothing to accept'), findsOneWidget);

      // Cannot accept without agreeing.
      final button = tester.widget<ElevatedButton>(
        find.descendant(
          of: find.byKey(const Key('accept_with_terms_button')),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.byKey(const Key('agree_terms_checkbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accept_with_terms_button')));
      await tester.pumpAndSettle();

      // Agreeing closes the sheet and lets acceptance proceed.
      expect(find.byKey(const Key('teacher_terms_sheet')), findsNothing);
    });

    testWidgets('declining the terms does not accept', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  await showTeacherTermsSheet(
                    context,
                    childName: 'Daniel',
                    planAmount: '3,000 FCFA',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('terms_cancel_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('teacher_terms_sheet')), findsNothing);
    });

    test('the terms never call the first month free', () {
      final text = TeacherTerms.text('3,000 FCFA');
      // The parent pays in full and the teacher earns in full; Camiva simply
      // does not charge the plan yet.
      expect(text.toLowerCase(), isNot(contains('free')));
      expect(text, contains('no Teacher Service Plan charge'));
      expect(text, contains('managed through Camiva'));
    });

    test('the terms are not a lead, activation or commission charge', () {
      final text = TeacherTerms.text('3,000 FCFA').toLowerCase();
      for (final forbidden in [
        'lead fee',
        'activation fee',
        'match fee',
        'contact fee',
        'commission',
        'unlock',
      ]) {
        expect(text, isNot(contains(forbidden)));
      }
    });
  });

  group('Service plan states', () {
    testWidgets('a teacher who has not earned owes nothing', (tester) async {
      final payments = FakePaymentService(quote: 3000);
      await _pumpPlan(tester, _plan(ServicePlanState.notStarted),
          payments: payments);

      expect(find.byKey(const Key('service_plan_not_started')), findsOneWidget);
      expect(
        find.textContaining('starts after your first month of tutoring'),
        findsOneWidget,
      );
      // Nothing payable, and nothing started.
      expect(find.byKey(const Key('pay_button')), findsNothing);
      expect(payments.startCalls, isEmpty);
    });

    testWidgets('during the first month nothing is charged', (tester) async {
      final payments = FakePaymentService(quote: 3000);
      await _pumpPlan(
        tester,
        _plan(ServicePlanState.firstMonth,
            firstEarnedAt: DateTime(2026, 8, 1),
            dueOn: DateTime(2026, 8, 31)),
        payments: payments,
      );

      expect(find.byKey(const Key('service_plan_first_month')), findsOneWidget);
      expect(find.byKey(const Key('pay_button')), findsNothing);
      expect(payments.startCalls, isEmpty);
    });

    testWidgets('once due, the plan is payable at the configured amount',
        (tester) async {
      await _pumpPlan(tester, _plan(ServicePlanState.due));

      expect(find.text('Camiva Teacher Service'), findsWidgets);
      expect(find.text('3,000 FCFA'), findsOneWidget);
      expect(find.text('Pay 3,000 FCFA'), findsOneWidget);
      expect(
        find.textContaining('Your first month of tutoring is complete'),
        findsOneWidget,
      );
    });

    testWidgets('a successful payment reports the account as active',
        (tester) async {
      await _pumpPlan(
        tester,
        _plan(ServicePlanState.due),
        payments: FakePaymentService(
          quote: 3000,
          verifyStatuses: const [PaymentStatus.successful],
        ),
      );

      await tester.enterText(
          find.byKey(const Key('momo_number_field')), '670000000');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('pay_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pay_button')));
      await tester.pumpAndSettle();

      expect(find.text("You're active"), findsOneWidget);
      expect(find.textContaining('Camiva takes no commission'), findsOneWidget);
    });

    testWidgets('a failed payment does not report the plan as active',
        (tester) async {
      await _pumpPlan(
        tester,
        _plan(ServicePlanState.due),
        payments: FakePaymentService(
          quote: 3000,
          verifyStatuses: const [PaymentStatus.failed],
        ),
      );

      await tester.enterText(
          find.byKey(const Key('momo_number_field')), '670000000');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('pay_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pay_button')));
      await tester.pumpAndSettle();

      expect(find.text('Payment failed. Try again.'), findsOneWidget);
      expect(find.text("You're active"), findsNothing);
    });

    testWidgets('an active plan says so without offering to charge again',
        (tester) async {
      final payments = FakePaymentService(quote: 3000);
      await _pumpPlan(
        tester,
        _plan(ServicePlanState.active, dueOn: DateTime(2026, 9, 30)),
        payments: payments,
      );

      expect(find.byKey(const Key('service_plan_active')), findsOneWidget);
      expect(find.byKey(const Key('pay_button')), findsNothing);
      expect(payments.startCalls, isEmpty);
    });

    test('a suspended teacher keeps their current students', () {
      // Suspension stops NEW work; teaching already underway is never ended by
      // a billing state.
      final plan = _plan(ServicePlanState.suspended);
      expect(plan.message, contains('current students are not affected'));
      expect(plan.state.canAcceptNewWork, isFalse);
    });
  });

  group('ServicePlanState', () {
    test('nothing is payable before the first month is complete', () {
      expect(ServicePlanState.notStarted.isPayable, isFalse);
      expect(ServicePlanState.firstMonth.isPayable, isFalse);
      expect(ServicePlanState.due.isPayable, isTrue);
      expect(ServicePlanState.overdue.isPayable, isTrue);
      expect(ServicePlanState.suspended.isPayable, isTrue);
    });

    test('only suspension stops new relationships', () {
      expect(ServicePlanState.overdue.canAcceptNewWork, isTrue);
      expect(ServicePlanState.due.canAcceptNewWork, isTrue);
      expect(ServicePlanState.suspended.canAcceptNewWork, isFalse);
    });

    test('no state ever describes the first month as free', () {
      for (final state in ServicePlanState.values) {
        final plan = _plan(state);
        expect(plan.message.toLowerCase(), isNot(contains('free')));
      }
    });
  });
}
