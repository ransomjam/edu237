import 'package:edu237/core/models/fee_config.dart';
import 'package:edu237/core/models/payment_transaction.dart';
import 'package:edu237/core/services/payment_service.dart';
import 'package:edu237/features/payments/activate_relationship_screen.dart';
import 'package:edu237/features/payments/relationship_contact_card.dart';
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
      child: MaterialApp(home: Scaffold(body: screen)),
    ),
  );
  await tester.pumpAndSettle();
}

const _args = ActivateRelationshipArgs(
  relationshipId: 'rel-1',
  childName: 'Daniel',
  subject: 'Mathematics',
);

void main() {
  group('ActivateRelationshipScreen', () {
    testWidgets('asks for the configured fee in activation language',
        (tester) async {
      final service = FakePaymentService(
        config: fakeConfig(activationFee: 1000),
        activationState: ActivationState.required,
      );
      await _pump(tester,
          screen: const ActivateRelationshipScreen(args: _args),
          paymentService: service);

      expect(find.text('Activate your Camiva tutoring relationship'),
          findsOneWidget);
      // The charge follows the parent's confirmation, and the copy says so.
      expect(
        find.text(
          "Camiva has received the parent's confirmation. A small platform "
          'charge activates this tutoring relationship and enables Camiva '
          'coordination: reminders, payment records and support.',
        ),
        findsOneWidget,
      );
      expect(find.text('1,000 FCFA'), findsOneWidget);
      expect(find.text('Pay & activate'), findsOneWidget);
    });

    testWidgets('never calls the charge an unlock fee', (tester) async {
      await _pump(
        tester,
        screen: const ActivateRelationshipScreen(args: _args),
        paymentService: FakePaymentService(
          config: fakeConfig(activationFee: 1000),
          activationState: ActivationState.required,
        ),
      );

      expect(find.textContaining('Unlock'), findsNothing);
      expect(find.textContaining('unlock'), findsNothing);
    });

    testWidgets('charges nothing when activation is not configured',
        (tester) async {
      await _pump(
        tester,
        screen: const ActivateRelationshipScreen(args: _args),
        paymentService: FakePaymentService(
          config: FeeConfig.unknown,
          activationState: ActivationState.notRequired,
        ),
      );

      expect(find.text("You're connected to this family"), findsOneWidget);
      expect(find.text('Pay & activate'), findsNothing);
    });

    testWidgets(
        'shows processing — not connected — while an activation payment is '
        'still in flight', (tester) async {
      await _pump(
        tester,
        screen: const ActivateRelationshipScreen(args: _args),
        paymentService: FakePaymentService(
          config: fakeConfig(activationFee: 1000),
          activationState: ActivationState.pending,
        ),
      );

      expect(find.text('Payment processing…'), findsOneWidget);
      expect(find.text("You're connected to this family"), findsNothing);
    });

    testWidgets('a confirmed activation payment reports the connection',
        (tester) async {
      final service = FakePaymentService(
        config: fakeConfig(activationFee: 1000),
        activationState: ActivationState.required,
        verifyStatuses: const [PaymentStatus.successful],
      );
      await _pump(tester,
          screen: const ActivateRelationshipScreen(args: _args),
          paymentService: service);

      await tester.enterText(
          find.byKey(const Key('momo_number_field')), '670123456');
      await tester.pump();
      // The charge explanation makes the form taller than the test window.
      await tester.ensureVisible(find.byKey(const Key('pay_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pay_button')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();

      // The completion moment is the connection, not the transaction.
      expect(find.text("You're connected"), findsOneWidget);
      expect(
        find.text("You're connected to this family. You can start scheduling "
            'lessons.'),
        findsOneWidget,
      );
      expect(service.startCalls.single['purpose'],
          PaymentPurpose.matchActivation);
    });
  });

  group('RelationshipContactCard', () {
    testWidgets('stays locked and holds no contact data before activation',
        (tester) async {
      // This mirrors the server: nothing is returned at all until the
      // activation condition is satisfied.
      await _pump(
        tester,
        screen: const RelationshipContactCard(relationshipId: 'rel-1'),
        paymentService: FakePaymentService(
          contactRevealed: false,
          contactName: 'Marie Ngu',
          contactPhone: '670123456',
        ),
      );

      expect(find.byKey(const Key('contact_locked')), findsOneWidget);
      expect(find.byKey(const Key('contact_revealed')), findsNothing);
      expect(find.textContaining('670123456'), findsNothing);
      expect(find.textContaining('Marie Ngu'), findsNothing);
    });

    testWidgets('a failed payment leaves the contact locked', (tester) async {
      // A failure means the server still reports the relationship as not
      // activated, so the card is exactly as locked as before the attempt.
      final service = FakePaymentService(
        contactRevealed: false,
        activationState: ActivationState.required,
        verifyStatuses: const [PaymentStatus.failed],
      );
      await _pump(
        tester,
        screen: const RelationshipContactCard(relationshipId: 'rel-1'),
        paymentService: service,
      );

      expect(find.byKey(const Key('contact_locked')), findsOneWidget);
      expect(find.textContaining('670'), findsNothing);
    });

    testWidgets('shows the details once the server reveals them',
        (tester) async {
      await _pump(
        tester,
        screen: const RelationshipContactCard(relationshipId: 'rel-1'),
        paymentService: FakePaymentService(
          contactRevealed: true,
          contactName: 'Marie Ngu',
          contactPhone: '670123456',
        ),
      );

      expect(find.byKey(const Key('contact_revealed')), findsOneWidget);
      expect(find.text('Marie Ngu'), findsOneWidget);
      expect(find.text('670123456'), findsOneWidget);
    });

    testWidgets('offers activation when one is still needed', (tester) async {
      var tapped = false;
      await _pump(
        tester,
        screen: RelationshipContactCard(
          relationshipId: 'rel-1',
          onActivate: () => tapped = true,
        ),
        paymentService: FakePaymentService(contactRevealed: false),
      );

      await tester.tap(find.byKey(const Key('activate_relationship_button')));
      expect(tapped, isTrue);
    });
  });
}
