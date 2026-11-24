import 'package:edu237/core/services/auth_service.dart';
import 'package:edu237/features/auth/forgot_pin_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stub_auth_service.dart';

Future<void> _pump(WidgetTester tester, StubAuthService service) async {
  await tester.pumpWidget(
    AuthServiceScope(
      authService: service,
      child: const MaterialApp(home: ForgotPinScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _requestCode(WidgetTester tester, String phone) async {
  await tester.enterText(find.byKey(const Key('forgot_phone_field')), phone);
  await tester.tap(find.byKey(const Key('send_code_button')));
  await tester.pumpAndSettle();
}

void main() {
  group('ForgotPinScreen', () {
    testWidgets('asks for the number first', (tester) async {
      await _pump(tester, StubAuthService());

      expect(find.byKey(const Key('forgot_pin_phone_step')), findsOneWidget);
      expect(find.text('Reset your PIN'), findsOneWidget);
      // No code is asked for before one has been sent.
      expect(find.byKey(const Key('reset_code_field')), findsNothing);
    });

    testWidgets('refuses a malformed number without calling the server',
        (tester) async {
      final service = StubAuthService();
      await _pump(tester, service);

      await _requestCode(tester, '12345');

      expect(service.resetRequests, isEmpty);
      expect(find.byKey(const Key('forgot_pin_error')), findsOneWidget);
      expect(find.byKey(const Key('forgot_pin_phone_step')), findsOneWidget);
    });

    testWidgets('normalises the number before asking for a code',
        (tester) async {
      final service = StubAuthService();
      await _pump(tester, service);

      await _requestCode(tester, '+237 670 00 00 00');

      expect(service.resetRequests, ['670000000']);
    });

    testWidgets('moves on without saying whether the number is registered',
        (tester) async {
      await _pump(tester, StubAuthService());
      await _requestCode(tester, '670000000');

      expect(find.byKey(const Key('forgot_pin_code_step')), findsOneWidget);
      // The wording is conditional on purpose: it must not confirm an account.
      expect(find.textContaining('If that number has an account'),
          findsOneWidget);
    });

    testWidgets('will not set a new PIN when the two do not match',
        (tester) async {
      final service = StubAuthService();
      await _pump(tester, service);
      await _requestCode(tester, '670000000');

      await tester.enterText(
          find.byKey(const Key('reset_code_field')), '123456');
      await tester.enterText(find.byKey(const Key('new_pin_field')), '1234');
      await tester.enterText(
          find.byKey(const Key('confirm_new_pin_field')), '5678');
      await tester.tap(find.byKey(const Key('confirm_reset_button')));
      await tester.pumpAndSettle();

      expect(service.resetConfirms, isEmpty);
      expect(find.text('The two PINs do not match.'), findsOneWidget);
    });

    testWidgets('sends the code and the new PIN together', (tester) async {
      final service = StubAuthService();
      await _pump(tester, service);
      await _requestCode(tester, '670000000');

      await tester.enterText(
          find.byKey(const Key('reset_code_field')), '123456');
      await tester.enterText(find.byKey(const Key('new_pin_field')), '4321');
      await tester.enterText(
          find.byKey(const Key('confirm_new_pin_field')), '4321');
      await tester.tap(find.byKey(const Key('confirm_reset_button')));
      await tester.pumpAndSettle();

      expect(service.resetConfirms, hasLength(1));
      final call = service.resetConfirms.single;
      expect(call.code, '123456');
      expect(call.pin, '4321');
      expect(find.byKey(const Key('forgot_pin_done_step')), findsOneWidget);
      expect(find.text('PIN changed'), findsOneWidget);
    });

    testWidgets('a rejected code keeps the person on the code step',
        (tester) async {
      final service = StubAuthService()
        ..confirmResult = const AuthFailure('That code is not valid.');
      await _pump(tester, service);
      await _requestCode(tester, '670000000');

      await tester.enterText(
          find.byKey(const Key('reset_code_field')), '000000');
      await tester.enterText(find.byKey(const Key('new_pin_field')), '4321');
      await tester.enterText(
          find.byKey(const Key('confirm_new_pin_field')), '4321');
      await tester.tap(find.byKey(const Key('confirm_reset_button')));
      await tester.pumpAndSettle();

      expect(find.text('That code is not valid.'), findsOneWidget);
      expect(find.byKey(const Key('forgot_pin_done_step')), findsNothing);
    });

    testWidgets('another code can be requested', (tester) async {
      final service = StubAuthService();
      await _pump(tester, service);
      await _requestCode(tester, '670000000');

      await tester.tap(find.byKey(const Key('resend_code_button')));
      await tester.pumpAndSettle();

      expect(service.resetRequests, ['670000000', '670000000']);
    });
  });

  group('UnconfiguredAuthService', () {
    test('cannot recover a PIN without a backend', () async {
      const sut = UnconfiguredAuthService();
      expect(await sut.requestPinReset('670000000'), isA<AuthFailure>());
      expect(
        await sut.confirmPinReset(
            phone: '670000000', code: '123456', newPin: '1234'),
        isA<AuthFailure>(),
      );
    });
  });
}
