import 'package:edu237/core/models/payment_transaction.dart';
import 'package:edu237/core/services/earnings_service.dart';
import 'package:edu237/core/services/payment_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnconfiguredPaymentService', () {
    const sut = UnconfiguredPaymentService();

    test('cannot start a payment', () async {
      final result = await sut.startPayment(
        purpose: PaymentPurpose.tutoringPayment,
        relationshipId: 'rel-1',
      );
      expect(result, isA<PaymentFailure>());
    });

    test('cannot verify a payment', () async {
      expect(await sut.verifyPayment('pay-1'), isA<PaymentFailure>());
    });

    test('never reveals contact details when there is no backend', () async {
      final result = await sut.fetchRelationshipContact('rel-1');
      expect(result, isA<ContactSuccess>());
      final contact = result as ContactSuccess;
      expect(contact.revealed, isFalse);
      expect(contact.phone, isNull);
      expect(contact.name, isNull);
    });

    test('reports no pricing rather than inventing one', () async {
      final result = await sut.fetchFeeConfig();
      expect(result, isA<FeeConfigSuccess>());
      final config = (result as FeeConfigSuccess).config;
      expect(config.chargesForActivation, isFalse);
      expect(config.matchActivationFeeAmount, isNull);
    });

    test('reports no Camiva activity rather than fabricating a history',
        () async {
      final result = await sut.fetchTeacherActivity('teacher-1');
      expect(result, isA<TeacherActivitySuccess>());
      expect((result as TeacherActivitySuccess).activity.hasActivity, isFalse);
    });
  });

  group('UnconfiguredEarningsService', () {
    const sut = UnconfiguredEarningsService();

    test('shows a zero position rather than a guessed balance', () async {
      final result = await sut.fetchEarnings();
      expect(result, isA<EarningsSuccess>());
      final earnings = (result as EarningsSuccess).earnings;
      expect(earnings.available, 0);
      expect(earnings.pending, 0);
      expect(earnings.lifetime, 0);
    });

    test('cannot request a withdrawal', () async {
      expect(await sut.requestWithdrawal(1000), isA<EarningsFailure>());
    });

    test('cannot mark a withdrawal successful', () async {
      expect(await sut.verifyWithdrawal('w1'), isA<EarningsFailure>());
    });

    test('has no payout destination', () async {
      final result = await sut.fetchPayoutAccount();
      expect(result, isA<PayoutAccountSuccess>());
      expect((result as PayoutAccountSuccess).account, isNull);
    });
  });
}
