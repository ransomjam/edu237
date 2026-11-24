import 'package:edu237/core/models/fee_config.dart';
import 'package:edu237/core/models/payment_transaction.dart';
import 'package:edu237/core/models/teacher_earnings.dart';
import 'package:edu237/core/models/withdrawal.dart';
import 'package:edu237/core/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('money formatting', () {
    test('groups thousands and uses the local currency name', () {
      expect(formatMoney(5000), '5,000 FCFA');
      expect(formatMoney(1000), '1,000 FCFA');
      expect(formatMoney(25000), '25,000 FCFA');
      expect(formatMoney(100), '100 FCFA');
      expect(formatMoney(1234567), '1,234,567 FCFA');
    });

    test('keeps a non-XAF currency as its code', () {
      expect(formatMoney(1000, 'USD'), '1,000 USD');
    });
  });

  group('PaymentTransaction', () {
    Map<String, dynamic> row({
      String status = 'successful',
      String purpose = 'tutoring_payment',
    }) =>
        {
          'id': 'e3b0c442-0000-0000-0000-000000000001',
          'purpose': purpose,
          'payer_id': 'parent-1',
          'parent_id': 'parent-1',
          'teacher_id': 'teacher-1',
          'student_id': 'student-1',
          'relationship_id': 'rel-1',
          'amount': 5000,
          'currency': 'XAF',
          'status': status,
          'provider_trans_id': 'FAPSHI-123',
          'created_at': '2026-08-13T10:00:00Z',
          'updated_at': '2026-08-13T10:05:00Z',
          'paid_at': '2026-08-13T10:05:00Z',
          'student_name': 'Daniel',
          'teacher_name': 'Jam Ransom',
        };

    test('parses a ledger row including its display context', () {
      final payment = PaymentTransaction.fromMap(row());

      expect(payment.purpose, PaymentPurpose.tutoringPayment);
      expect(payment.status, PaymentStatus.successful);
      expect(payment.amount, 5000);
      expect(payment.formattedAmount, '5,000 FCFA');
      expect(payment.studentName, 'Daniel');
      expect(payment.teacherName, 'Jam Ransom');
      expect(payment.paidAt, isNotNull);
    });

    test('the reference is the provider transaction id', () {
      expect(PaymentTransaction.fromMap(row()).reference, 'FAPSHI-123');
    });

    test('falls back to a short internal reference before the provider replies',
        () {
      final map = row()..['provider_trans_id'] = null;
      expect(PaymentTransaction.fromMap(map).reference, 'E3B0C442');
    });

    test('rejects a row missing money-defining data', () {
      final map = row()..remove('amount');
      expect(() => PaymentTransaction.fromMap(map), throwsFormatException);
    });

    test('rejects an unknown status rather than guessing', () {
      expect(() => PaymentStatus.fromString('paid'), throwsFormatException);
      expect(() => PaymentStatus.fromString(null), throwsFormatException);
    });
  });

  group('PaymentStatus', () {
    test('only pending is non-terminal', () {
      expect(PaymentStatus.pending.isTerminal, isFalse);
      for (final status in [
        PaymentStatus.successful,
        PaymentStatus.failed,
        PaymentStatus.cancelled,
        PaymentStatus.refunded,
      ]) {
        expect(status.isTerminal, isTrue, reason: '$status');
      }
    });

    test('a failed or cancelled payment can simply be tried again', () {
      expect(PaymentStatus.failed.canRetry, isTrue);
      expect(PaymentStatus.cancelled.canRetry, isTrue);
      expect(PaymentStatus.successful.canRetry, isFalse);
      expect(PaymentStatus.pending.canRetry, isFalse);
    });

    test('uses the agreed wording for each state', () {
      expect(PaymentStatus.pending.message, 'Payment processing…');
      expect(PaymentStatus.successful.message, 'Payment successful');
      expect(PaymentStatus.failed.message, 'Payment failed. Try again.');
      expect(PaymentStatus.cancelled.message, 'Payment cancelled.');
    });
  });

  group('FeeConfig', () {
    test('charges for activation only when switched on AND priced', () {
      const both = FeeConfig(
        currency: 'XAF',
        teacherServiceFeeAmount: null,
        teacherServiceFeeIntervalDays: 30,
        matchActivationFeeAmount: 1000,
        matchActivationRequired: true,
        settlementDelayHours: 24,
        minWithdrawalAmount: 100,
      );
      expect(both.chargesForActivation, isTrue);

      const switchedOff = FeeConfig(
        currency: 'XAF',
        teacherServiceFeeAmount: null,
        teacherServiceFeeIntervalDays: 30,
        matchActivationFeeAmount: 1000,
        matchActivationRequired: false,
        settlementDelayHours: 24,
        minWithdrawalAmount: 100,
      );
      expect(switchedOff.chargesForActivation, isFalse);

      const noAmount = FeeConfig(
        currency: 'XAF',
        teacherServiceFeeAmount: null,
        teacherServiceFeeIntervalDays: 30,
        matchActivationFeeAmount: null,
        matchActivationRequired: true,
        settlementDelayHours: 24,
        minWithdrawalAmount: 100,
      );
      expect(noAmount.chargesForActivation, isFalse);
    });

    test('the unknown config charges nothing — no invented price', () {
      expect(FeeConfig.unknown.chargesForActivation, isFalse);
      expect(FeeConfig.unknown.chargesServiceFee, isFalse);
      expect(FeeConfig.unknown.matchActivationFeeAmount, isNull);
      expect(FeeConfig.unknown.teacherServiceFeeAmount, isNull);
    });
  });

  group('ActivationState', () {
    test('only not_required and active are operational', () {
      expect(ActivationState.notRequired.isOperational, isTrue);
      expect(ActivationState.active.isOperational, isTrue);
      expect(ActivationState.required.isOperational, isFalse);
      expect(ActivationState.pending.isOperational, isFalse);
    });

    test('a pending activation payment does not yet count as paid', () {
      expect(ActivationState.pending.needsPayment, isFalse);
      expect(ActivationState.required.needsPayment, isTrue);
    });

    test('parses the server values', () {
      expect(ActivationState.fromString('not_required'),
          ActivationState.notRequired);
      expect(ActivationState.fromString('active'), ActivationState.active);
      expect(() => ActivationState.fromString('paid'), throwsFormatException);
    });
  });

  group('TeacherEarnings', () {
    test('reads the server-derived figures', () {
      final earnings = TeacherEarnings.fromMap({
        'available': 25000,
        'pending': 5000,
        'lifetime': 30000,
        'withdrawn': 0,
        'currency': 'XAF',
      });
      expect(earnings.formattedAvailable, '25,000 FCFA');
      expect(earnings.formattedPending, '5,000 FCFA');
      expect(earnings.formattedLifetime, '30,000 FCFA');
      expect(earnings.hasAnything, isTrue);
    });

    test('empty earnings show nothing rather than a made-up balance', () {
      expect(TeacherEarnings.empty.available, 0);
      expect(TeacherEarnings.empty.hasAnything, isFalse);
    });
  });

  group('withdrawals', () {
    test('requested and processing are the in-flight states', () {
      expect(WithdrawalStatus.requested.isInFlight, isTrue);
      expect(WithdrawalStatus.processing.isInFlight, isTrue);
      expect(WithdrawalStatus.successful.isInFlight, isFalse);
      expect(WithdrawalStatus.failed.isInFlight, isFalse);
    });

    test('a failed withdrawal says earnings are unchanged', () {
      expect(WithdrawalStatus.failed.message,
          'Withdrawal failed. Your earnings are unchanged.');
    });

    test('only the last two digits of a payout number are ever shown', () {
      const account =
          PayoutAccount(teacherId: 't1', medium: 'mobile money', phone: '670123456');
      expect(account.maskedPhone, '•••• 56');
      expect(account.maskedPhone, isNot(contains('670123')));
    });

    test('validates the payout number format Fapshi expects', () {
      expect(PayoutAccount.isValidPhone('670123456'), isTrue);
      expect(PayoutAccount.isValidPhone('70123456'), isFalse);
      expect(PayoutAccount.isValidPhone('6701234567'), isFalse);
      expect(PayoutAccount.isValidPhone('+237670123456'), isFalse);
      expect(PayoutAccount.isValidPhone('abcdefghi'), isFalse);
    });

    test('parses a withdrawal row', () {
      final withdrawal = Withdrawal.fromMap({
        'id': 'w1',
        'teacher_id': 'teacher-1',
        'amount': 25000,
        'currency': 'XAF',
        'status': 'processing',
        'payout_medium': 'mobile money',
        'payout_phone': '670123456',
        'created_at': '2026-08-13T10:00:00Z',
        'updated_at': '2026-08-13T10:00:00Z',
      });
      expect(withdrawal.status, WithdrawalStatus.processing);
      expect(withdrawal.formattedAmount, '25,000 FCFA');
      expect(withdrawal.maskedPhone, '•••• 56');
    });
  });
}
