import 'package:edu237/core/models/payment_transaction.dart';
import 'package:edu237/core/services/payment_service.dart';
import 'package:edu237/features/payments/payment_flow_screen.dart';
import 'package:edu237/features/payments/payment_receipt_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_payment_services.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Widget screen,
  required PaymentService paymentService,
}) async {
  await tester.pumpWidget(
    PaymentServiceScope(
      paymentService: paymentService,
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _flow({
  PaymentPurpose purpose = PaymentPurpose.tutoringPayment,
  int amount = 5000,
}) =>
    PaymentFlowScreen(
      title: 'Pay for tutoring',
      headline: "Daniel's tutoring",
      explanation: 'Paying here gives you a receipt and a payment history.',
      details: const [
        PaymentDetail('Child', 'Daniel'),
        PaymentDetail('Subject', 'Mathematics'),
        PaymentDetail('Teacher', 'Jam Ransom'),
      ],
      amount: amount,
      currency: 'XAF',
      payLabel: 'Pay with Mobile Money',
      successTitle: 'Payment successful',
      successBody: 'Your receipt is saved in Payments.',
      request: PaymentRequest(purpose: purpose, relationshipId: 'rel-1'),
    );

void main() {
  group('PaymentFlowScreen', () {
    testWidgets('shows what is being paid for and the exact amount',
        (tester) async {
      await _pump(tester,
          screen: _flow(), paymentService: FakePaymentService());

      expect(find.text("Daniel's tutoring"), findsOneWidget);
      expect(find.text('Daniel'), findsOneWidget);
      expect(find.text('Jam Ransom'), findsOneWidget);
      expect(find.text('5,000 FCFA'), findsOneWidget);
      expect(find.text('Pay with Mobile Money'), findsOneWidget);
    });

    testWidgets('never names the payment provider to the user', (tester) async {
      await _pump(tester,
          screen: _flow(), paymentService: FakePaymentService());

      expect(find.textContaining('Fapshi'), findsNothing);
      expect(find.textContaining('fapshi'), findsNothing);
    });

    testWidgets('will not pay until a valid mobile money number is entered',
        (tester) async {
      final service = FakePaymentService();
      await _pump(tester, screen: _flow(), paymentService: service);

      final button =
          tester.widget<ElevatedButton>(find.byType(ElevatedButton).first);
      expect(button.onPressed, isNull);

      await tester.enterText(find.byKey(const Key('momo_number_field')), '6701');
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton).first)
            .onPressed,
        isNull,
      );

      await tester.enterText(
          find.byKey(const Key('momo_number_field')), '670123456');
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton).first)
            .onPressed,
        isNotNull,
      );
      expect(service.startCalls, isEmpty);
    });

    testWidgets('sends what is being paid for — never an amount',
        (tester) async {
      final service = FakePaymentService();
      await _pump(tester, screen: _flow(), paymentService: service);

      await tester.enterText(
          find.byKey(const Key('momo_number_field')), '670123456');
      await tester.pump();
      await tester.tap(find.byKey(const Key('pay_button')));
      await tester.pump();

      expect(service.startCalls, hasLength(1));
      final call = service.startCalls.single;
      expect(call['purpose'], PaymentPurpose.tutoringPayment);
      expect(call['relationshipId'], 'rel-1');
      expect(call['payerPhone'], '670123456');
      expect(call.containsKey('amount'), isFalse);
    });

    testWidgets(
        'a started payment shows processing, not success — the client cannot '
        'declare a payment paid', (tester) async {
      // The "server" accepts the request and answers pending, and the first
      // verification is still pending too.
      final service = FakePaymentService(
        verifyStatuses: const [PaymentStatus.pending],
      );
      await _pump(tester, screen: _flow(), paymentService: service);

      await tester.enterText(
          find.byKey(const Key('momo_number_field')), '670123456');
      await tester.pump();
      await tester.tap(find.byKey(const Key('pay_button')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('payment_processing')), findsOneWidget);
      expect(find.text('Payment processing…'), findsOneWidget);
      expect(find.text('Payment successful'), findsNothing);
    });

    testWidgets('shows success only once the server confirms it',
        (tester) async {
      final service = FakePaymentService(
        verifyStatuses: const [PaymentStatus.successful],
      );
      await _pump(tester, screen: _flow(), paymentService: service);

      await tester.enterText(
          find.byKey(const Key('momo_number_field')), '670123456');
      await tester.pump();
      await tester.tap(find.byKey(const Key('pay_button')));
      await tester.pump();

      // The screen waits for the server; nothing is claimed before then.
      expect(find.text('Payment successful'), findsNothing);

      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payment_result_successful')), findsOneWidget);
      expect(find.text('Payment successful'), findsOneWidget);
      expect(service.verifiedPaymentIds, contains('pay-1'));
    });

    testWidgets('shows the failure wording when the server reports failed',
        (tester) async {
      final service =
          FakePaymentService(verifyStatuses: const [PaymentStatus.failed]);
      await _pump(tester, screen: _flow(), paymentService: service);

      await tester.enterText(
          find.byKey(const Key('momo_number_field')), '670123456');
      await tester.pump();
      await tester.tap(find.byKey(const Key('pay_button')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payment_result_failed')), findsOneWidget);
      expect(find.text('Payment failed. Try again.'), findsOneWidget);
      expect(find.byKey(const Key('payment_retry_button')), findsOneWidget);
    });

    testWidgets('shows the cancelled wording when the server reports cancelled',
        (tester) async {
      final service =
          FakePaymentService(verifyStatuses: const [PaymentStatus.cancelled]);
      await _pump(tester, screen: _flow(), paymentService: service);

      await tester.enterText(
          find.byKey(const Key('momo_number_field')), '670123456');
      await tester.pump();
      await tester.tap(find.byKey(const Key('pay_button')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();

      expect(find.text('Payment cancelled.'), findsOneWidget);
    });

    testWidgets('surfaces a refusal from the backend without charging',
        (tester) async {
      final service =
          FakePaymentService(failStartWith: 'This relationship is not active yet');
      await _pump(tester, screen: _flow(), paymentService: service);

      await tester.enterText(
          find.byKey(const Key('momo_number_field')), '670123456');
      await tester.pump();
      await tester.tap(find.byKey(const Key('pay_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payment_error')), findsOneWidget);
      expect(find.text('This relationship is not active yet'), findsOneWidget);
      expect(find.byKey(const Key('payment_processing')), findsNothing);
    });

    testWidgets('stops polling when the screen is disposed', (tester) async {
      final service = FakePaymentService(
        verifyStatuses: const [PaymentStatus.pending],
      );
      await _pump(tester, screen: _flow(), paymentService: service);

      await tester.enterText(
          find.byKey(const Key('momo_number_field')), '670123456');
      await tester.pump();
      await tester.tap(find.byKey(const Key('pay_button')));
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 30));
      // No timer survived the dispose, so the test does not fail on a pending
      // timer and no further verification was attempted.
      expect(service.verifiedPaymentIds.length, lessThanOrEqualTo(1));
    });
  });

  group('PaymentReceiptScreen', () {
    testWidgets('shows amount, date, purpose, child, teacher and reference',
        (tester) async {
      await _pump(
        tester,
        screen: PaymentReceiptScreen(payment: fakePayment()),
        paymentService: FakePaymentService(),
      );

      expect(find.text('Payment successful'), findsOneWidget);
      expect(find.text('5,000 FCFA'), findsOneWidget);
      expect(find.text('13 Aug 2026'), findsOneWidget);
      expect(find.text('Tutoring payment'), findsOneWidget);
      expect(find.text('Daniel'), findsOneWidget);
      expect(find.text('Jam Ransom'), findsOneWidget);
      expect(find.text('FAPSHI-123'), findsOneWidget);
    });

    testWidgets('offers a support path that keeps the payment reference',
        (tester) async {
      final service = FakePaymentService();
      await _pump(
        tester,
        screen: PaymentReceiptScreen(payment: fakePayment()),
        paymentService: service,
      );

      await tester.tap(find.byKey(const Key('receipt_support_button')));
      await tester.pumpAndSettle();

      expect(find.text('Contact Camiva'), findsOneWidget);
      expect(find.text('Reference: FAPSHI-123'), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('support_message_field')), 'I paid twice');
      await tester.pump();
      await tester.tap(find.byKey(const Key('support_send_button')));
      await tester.pumpAndSettle();

      expect(service.supportRequests, hasLength(1));
      expect(service.supportRequests.single['paymentId'], 'pay-1');
      expect(service.supportRequests.single['relationshipId'], 'rel-1');
      // No promise of a refund or an outcome is made.
      expect(find.textContaining('refund'), findsNothing);
    });
  });
}
