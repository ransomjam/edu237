import 'package:edu237/core/models/billing_summary.dart';
import 'package:edu237/core/services/payment_service.dart';
import 'package:edu237/features/payments/parent_payment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_payment_services.dart';

BillingSummary _summary({
  int monthly = 20000,
  int paid = 0,
  int? balance,
}) =>
    BillingSummary(
      monthlyAmount: monthly,
      currency: 'XAF',
      startedOn: DateTime(2026, 8, 1),
      periodStart: DateTime(2026, 8, 1),
      periodEnd: DateTime(2026, 8, 31),
      nextDueOn: DateTime(2026, 9, 1),
      paidThisPeriod: paid,
      balance: balance ?? (monthly - paid),
    );

Future<void> _pumpPayment(
  WidgetTester tester,
  FakePaymentService service,
) async {
  await tester.pumpWidget(
    PaymentServiceScope(
      paymentService: service,
      child: const MaterialApp(
        home: ParentPaymentScreen(
          args: ParentPaymentArgs(
            relationshipId: 'rel-1',
            childName: 'Favour',
            teacherName: 'Jam Ransom',
            subject: 'Mathematics',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('BillingSummary', () {
    test('balance is what is left, and settles at zero', () {
      final partly = _summary(monthly: 20000, paid: 5000);
      expect(partly.balance, 15000);
      expect(partly.isPartlyPaid, isTrue);
      expect(partly.isSettled, isFalse);

      final done = _summary(monthly: 20000, paid: 20000);
      expect(done.balance, 0);
      expect(done.isSettled, isTrue);
      expect(done.isPartlyPaid, isFalse);
    });

    test('an untouched month is not "partly paid"', () {
      expect(_summary().isPartlyPaid, isFalse);
    });

    test('parses the derived figures the server sends', () {
      final row = BillingSummary.fromMap({
        'monthly_amount': 20000,
        'currency': 'XAF',
        'started_on': '2026-08-01',
        'period_start': '2026-08-01',
        'period_end': '2026-08-31',
        'next_due_on': '2026-09-01',
        'paid_this_period': 5000,
        'balance': 15000,
        'last_paid_at': '2026-08-13T10:00:00Z',
      });

      expect(row.monthlyAmount, 20000);
      expect(row.balance, 15000);
      expect(row.nextDueOn, DateTime(2026, 9, 1));
      expect(row.formattedBalance, '15,000 FCFA');
    });
  });

  group('ParentPaymentScreen instalments', () {
    testWidgets('offers to pay all of the balance or part of it',
        (tester) async {
      await _pumpPayment(
        tester,
        FakePaymentService(quote: 20000, billing: _summary()),
      );

      expect(find.byKey(const Key('installment_chooser')), findsOneWidget);
      expect(find.text('All 20,000 FCFA'), findsOneWidget);
      expect(find.text('10,000 FCFA'), findsOneWidget);
      expect(find.text('5,000 FCFA'), findsOneWidget);
    });

    testWidgets('choosing part of it says what will still be left',
        (tester) async {
      await _pumpPayment(
        tester,
        FakePaymentService(quote: 20000, billing: _summary()),
      );

      await tester.tap(find.byKey(const Key('installment_5000')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('installment_remainder')), findsOneWidget);
      expect(find.text('15,000 FCFA will still be left for this month.'),
          findsOneWidget);
      // The headline amount follows the choice.
      final headline =
          tester.widget<Text>(find.byKey(const Key('payment_amount')));
      expect(headline.data, '5,000 FCFA');
    });

    testWidgets('the chosen instalment is what gets sent', (tester) async {
      final service = FakePaymentService(quote: 20000, billing: _summary());
      await _pumpPayment(tester, service);

      await tester.tap(find.byKey(const Key('installment_5000')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('momo_number_field')), '670000000');
      await tester.pump();
      // The chooser makes the form taller than the viewport in a test window.
      await tester.ensureVisible(find.byKey(const Key('pay_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pay_button')));
      await tester.pump();

      expect(service.startedAmounts, [5000]);
    });

    testWidgets('with no monthly fee set, no amount is proposed at all',
        (tester) async {
      final service = FakePaymentService(quote: 5000);
      await _pumpPayment(tester, service);

      // Nothing to instal against: the server decides the price outright.
      expect(find.byKey(const Key('installment_chooser')), findsNothing);

      await tester.enterText(
          find.byKey(const Key('momo_number_field')), '670000000');
      await tester.pump();
      await tester.tap(find.byKey(const Key('pay_button')));
      await tester.pump();

      expect(service.startedAmounts, [null]);
    });

    testWidgets('shows what is already paid this month', (tester) async {
      await _pumpPayment(
        tester,
        FakePaymentService(
          quote: 15000,
          billing: _summary(monthly: 20000, paid: 5000),
        ),
      );

      expect(find.text('This month'), findsOneWidget);
      expect(find.text('20,000 FCFA'), findsOneWidget);
      expect(find.text('Already paid'), findsOneWidget);
    });

    testWidgets('a balance too small to split offers no chooser',
        (tester) async {
      await _pumpPayment(
        tester,
        FakePaymentService(
          quote: 100,
          billing: _summary(monthly: 20000, balance: 100),
        ),
      );

      expect(find.byKey(const Key('installment_chooser')), findsNothing);
    });
  });
}
