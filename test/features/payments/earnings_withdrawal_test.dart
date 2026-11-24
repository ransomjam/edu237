import 'package:edu237/core/models/payment_reminder.dart';
import 'package:edu237/core/models/teacher_earnings.dart';
import 'package:edu237/core/models/withdrawal.dart';
import 'package:edu237/core/services/earnings_service.dart';
import 'package:edu237/core/services/payment_service.dart';
import 'package:edu237/features/payments/payout_account_screen.dart';
import 'package:edu237/features/payments/teacher_earnings_screen.dart';
import 'package:edu237/features/payments/withdraw_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_payment_services.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Widget screen,
  required EarningsService earningsService,
  PaymentService? paymentService,
}) async {
  await tester.pumpWidget(
    PaymentServiceScope(
      paymentService: paymentService ?? FakePaymentService(),
      child: EarningsServiceScope(
        earningsService: earningsService,
        child: MaterialApp(home: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _earnings = TeacherEarnings(
  available: 25000,
  pending: 5000,
  lifetime: 30000,
  withdrawn: 0,
  currency: 'XAF',
);

const _account = PayoutAccount(
  teacherId: 'teacher-1',
  medium: 'mobile money',
  phone: '670123456',
);

void main() {
  group('TeacherEarningsScreen', () {
    testWidgets('shows the server-derived available, pending and lifetime',
        (tester) async {
      await _pump(
        tester,
        screen: const TeacherEarningsScreen(),
        earningsService: FakeEarningsService(
          earnings: _earnings,
          history: [fakePayment()],
        ),
      );

      expect(find.text('25,000 FCFA'), findsWidgets);
      expect(find.text('5,000 FCFA'), findsWidgets);
      expect(find.text('30,000 FCFA'), findsOneWidget);
      expect(find.text('Withdraw'), findsOneWidget);
    });

    testWidgets('earnings history lists the tutoring payments behind them',
        (tester) async {
      await _pump(
        tester,
        screen: const TeacherEarningsScreen(),
        earningsService: FakeEarningsService(
          earnings: _earnings,
          history: [fakePayment(), fakePayment(id: 'pay-2', amount: 10000)],
        ),
      );

      expect(find.text('Tutoring payment'), findsNWidgets(2));
      expect(find.text('Paid'), findsNWidgets(2));
    });

    testWidgets('cannot withdraw with nothing available', (tester) async {
      await _pump(
        tester,
        screen: const TeacherEarningsScreen(),
        earningsService: FakeEarningsService(
          earnings: const TeacherEarnings(
            available: 0,
            pending: 5000,
            lifetime: 5000,
            withdrawn: 0,
            currency: 'XAF',
          ),
        ),
      );

      final button = tester.widget<ElevatedButton>(
        find.descendant(
          of: find.byKey(const Key('withdraw_button')),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
        're-checks an in-flight withdrawal with the provider on open',
        (tester) async {
      final service = FakeEarningsService(
        earnings: _earnings,
        withdrawals: [
          Withdrawal(
            id: 'w1',
            teacherId: 'teacher-1',
            amount: 10000,
            currency: 'XAF',
            status: WithdrawalStatus.processing,
            payoutMedium: 'mobile money',
            payoutPhone: '670123456',
            createdAt: DateTime(2026, 8, 13),
            updatedAt: DateTime(2026, 8, 13),
          ),
        ],
      );

      await _pump(tester,
          screen: const TeacherEarningsScreen(), earningsService: service);

      expect(service.verifiedWithdrawalIds, contains('w1'));
      expect(find.text('Processing'), findsOneWidget);
    });

    testWidgets('records the service-plan reminder only when it is shown',
        (tester) async {
      final period = ServiceFeePeriod(
        id: 'sf1',
        teacherId: 'teacher-1',
        periodStart: DateTime(2026, 8, 1),
        periodEnd: DateTime(2026, 8, 30),
        amount: 1000,
        currency: 'XAF',
        status: ServiceFeeStatus.due,
      );
      final service =
          FakeEarningsService(earnings: _earnings, serviceFee: period);

      await _pump(tester,
          screen: const TeacherEarningsScreen(), earningsService: service);

      expect(find.text('Camiva Teacher Service'), findsOneWidget);
      expect(find.text('1,000 FCFA · 1 Aug 2026 – 30 Aug 2026'), findsOneWidget);
      expect(service.remindedPeriodIds, contains('sf1'));
    });

    testWidgets('says nothing about a service plan when none is configured',
        (tester) async {
      final service = FakeEarningsService(earnings: _earnings);
      await _pump(tester,
          screen: const TeacherEarningsScreen(), earningsService: service);

      expect(find.text('Camiva Teacher Service'), findsNothing);
      expect(service.remindedPeriodIds, isEmpty);
    });
  });

  group('WithdrawScreen', () {
    testWidgets('refuses an amount above the available earnings',
        (tester) async {
      final service = FakeEarningsService(earnings: _earnings);
      await _pump(
        tester,
        screen: const WithdrawScreen(earnings: _earnings, account: _account),
        earningsService: service,
      );

      await tester.enterText(
          find.byKey(const Key('withdraw_amount_field')), '30000');
      await tester.pump();

      expect(find.text('That is more than your available earnings.'),
          findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.descendant(
          of: find.byKey(const Key('request_withdrawal_button')),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(service.requestedAmounts, isEmpty);
    });

    testWidgets('cannot request a withdrawal without a payout number',
        (tester) async {
      await _pump(
        tester,
        screen: const WithdrawScreen(earnings: _earnings, account: null),
        earningsService: FakeEarningsService(earnings: _earnings),
      );

      expect(find.text('No number yet'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.descendant(
          of: find.byKey(const Key('request_withdrawal_button')),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('a request ends as processing — never as money sent',
        (tester) async {
      final service = FakeEarningsService(
        earnings: _earnings,
        requestResult: WithdrawalStatus.processing,
      );
      await _pump(
        tester,
        screen: const WithdrawScreen(earnings: _earnings, account: _account),
        earningsService: service,
      );

      await tester.enterText(
          find.byKey(const Key('withdraw_amount_field')), '25000');
      await tester.pump();
      await tester.tap(find.byKey(const Key('request_withdrawal_button')));
      await tester.pumpAndSettle();

      expect(service.requestedAmounts, [25000]);
      expect(find.byKey(const Key('withdrawal_result_processing')),
          findsOneWidget);
      expect(find.text('Sending your money…'), findsOneWidget);
      expect(find.text('Money sent to your number.'), findsNothing);
    });

    testWidgets('surfaces a server refusal without changing earnings',
        (tester) async {
      final service = FakeEarningsService(
        earnings: _earnings,
        requestFailure: 'You already have a withdrawal in progress',
      );
      await _pump(
        tester,
        screen: const WithdrawScreen(earnings: _earnings, account: _account),
        earningsService: service,
      );

      await tester.enterText(
          find.byKey(const Key('withdraw_amount_field')), '1000');
      await tester.pump();
      await tester.tap(find.byKey(const Key('request_withdrawal_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('withdraw_error')), findsOneWidget);
      expect(find.text('You already have a withdrawal in progress'),
          findsOneWidget);
    });

    testWidgets('shows only the masked payout destination', (tester) async {
      await _pump(
        tester,
        screen: const WithdrawScreen(earnings: _earnings, account: _account),
        earningsService: FakeEarningsService(earnings: _earnings),
      );

      expect(find.textContaining('•••• 56'), findsOneWidget);
      expect(find.textContaining('670123456'), findsNothing);
    });
  });

  group('PayoutAccountScreen', () {
    testWidgets('will not save an invalid number', (tester) async {
      final service = FakeEarningsService();
      await _pump(tester,
          screen: const PayoutAccountScreen(), earningsService: service);

      await tester.enterText(
          find.byKey(const Key('payout_number_field')), '12345');
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.descendant(
          of: find.byKey(const Key('save_payout_button')),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(service.savedAccounts, isEmpty);
    });

    testWidgets('saves a valid number for the signed-in teacher only',
        (tester) async {
      final service = FakeEarningsService();
      await _pump(tester,
          screen: const PayoutAccountScreen(), earningsService: service);

      await tester.enterText(
          find.byKey(const Key('payout_number_field')), '670123456');
      await tester.pump();
      await tester.tap(find.byKey(const Key('save_payout_button')));
      await tester.pumpAndSettle();

      expect(service.savedAccounts, hasLength(1));
      expect(service.savedAccounts.single['phone'], '670123456');
      expect(service.account?.teacherId, 'teacher-1');
    });
  });
}
