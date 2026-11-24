import 'package:edu237/core/services/payment_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('friendlyPaymentError', () {
    test('a missing table says the backend is not set up, not "try again"', () {
      final message = friendlyPaymentError(
        const PostgrestException(
          message: 'relation "public.payment_transactions" does not exist',
          code: '42P01',
        ),
      );
      expect(message, contains('not set up'));
      expect(message, isNot(startsWith('Something went wrong')));
    });

    test('a missing function is treated the same way', () {
      final message = friendlyPaymentError(
        const PostgrestException(
          message: 'Could not find the function public.teacher_earnings_summary',
          code: 'PGRST202',
        ),
      );
      expect(message, contains('not set up'));
    });

    test('a stale schema cache is treated the same way', () {
      final message = friendlyPaymentError(
        const PostgrestException(
          message: "Could not find the table 'public.payment_history' in the "
              'schema cache',
          code: 'PGRST205',
        ),
      );
      expect(message, contains('not set up'));
    });

    test('a database gap points at the migrations, not at the deploy', () {
      final message = friendlyPaymentError(
        const PostgrestException(
          message: 'relation "public.payment_transactions" does not exist',
          code: '42P01',
        ),
      );
      expect(message, contains('database'));
      expect(message, contains('migrations'));
      expect(message, isNot(contains('deploy')));
    });

    test('an undeployed function points at the deploy, not at the migrations',
        () {
      final message = friendlyPaymentError(
        FunctionException(status: 404, reasonPhrase: 'Not Found'),
      );
      expect(message, contains('not deployed'));
      expect(message, isNot(contains('migrations')));
    });

    test('a missing grant reads as permission, not as a broken app', () {
      final message = friendlyPaymentError(
        const PostgrestException(
          message: 'permission denied for table payment_transactions',
          code: '42501',
        ),
      );
      expect(message, contains('Permission denied'));
    });

    test('a connection problem is reported as a connection problem', () {
      final message =
          friendlyPaymentError(Exception('SocketException: Failed host lookup'));
      expect(message, 'No connection. Please check your internet.');
    });

    test('our own refusals are shown to the user unchanged', () {
      expect(
        friendlyPaymentError(const PostgrestException(
            message: 'Amount is more than your available earnings')),
        contains('available earnings'),
      );
      expect(
        friendlyPaymentError(const PostgrestException(
            message: 'You already have a withdrawal in progress')),
        contains('withdrawal in progress'),
      );
    });

    test('anything else stays generic — no database detail leaks', () {
      final message = friendlyPaymentError(
        const PostgrestException(
          message: 'duplicate key value violates unique constraint "pk_x"',
          code: '23505',
        ),
      );
      expect(message, genericPaymentError);
      expect(message, isNot(contains('constraint')));
    });
  });
}
