import 'package:edu237/core/auth/phone_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalising a number', () {
    test('accepts the forms people actually type', () {
      for (final input in [
        '670000000',
        '670 00 00 00',
        '+237670000000',
        '237670000000',
        '00237670000000',
        '+237 670-00-00-00',
      ]) {
        expect(PhoneCredentials.normalisePhone(input), '670000000',
            reason: '$input should normalise to the local nine digits');
      }
    });

    test('rejects anything that is not a Cameroon mobile number', () {
      for (final input in ['', '12345', '770000000', '67000000', '6700000000']) {
        expect(PhoneCredentials.normalisePhone(input), isNull,
            reason: '$input should not be accepted');
      }
    });

    test('reads back the way a person would say it', () {
      expect(PhoneCredentials.format('670000000'), '670 00 00 00');
    });
  });

  group('PIN rules', () {
    test('four to six digits, nothing else', () {
      expect(PhoneCredentials.isValidPin('1234'), isTrue);
      expect(PhoneCredentials.isValidPin('123456'), isTrue);
      expect(PhoneCredentials.isValidPin('123'), isFalse);
      expect(PhoneCredentials.isValidPin('1234567'), isFalse);
      expect(PhoneCredentials.isValidPin('12a4'), isFalse);
      expect(PhoneCredentials.isValidPin(''), isFalse);
    });
  });

  group('derived credentials', () {
    test('the number is the identity', () {
      expect(PhoneCredentials.emailFor('670000000'), '670000000@camiva.app');
      expect(PhoneCredentials.phoneFromEmail('670000000@camiva.app'),
          '670000000');
      expect(PhoneCredentials.phoneFromEmail('someone@example.com'), isNull);
    });

    test('the raw PIN never becomes the stored secret', () {
      final secret = PhoneCredentials.secretFor('670000000', '1234');

      expect(secret, isNot(contains('1234')));
      // A sha-256 hex digest: long enough to satisfy any password length rule
      // a four-digit PIN would fail.
      expect(secret.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(secret), isTrue);
    });

    test('the same PIN on two numbers gives different secrets', () {
      final a = PhoneCredentials.secretFor('670000000', '1234');
      final b = PhoneCredentials.secretFor('670000001', '1234');
      expect(a, isNot(b));
    });

    test('a different PIN on the same number gives a different secret', () {
      final a = PhoneCredentials.secretFor('670000000', '1234');
      final b = PhoneCredentials.secretFor('670000000', '1235');
      expect(a, isNot(b));
    });

    test('the same credentials always derive the same secret', () {
      // Sign-in must reproduce exactly what sign-up stored.
      expect(
        PhoneCredentials.secretFor('670000000', '1234'),
        PhoneCredentials.secretFor('670000000', '1234'),
      );
    });

    test('every typed form of one number reaches the same account', () {
      final normalised = PhoneCredentials.normalisePhone('+237 670 00 00 00')!;
      expect(
        PhoneCredentials.secretFor(normalised, '1234'),
        PhoneCredentials.secretFor('670000000', '1234'),
      );
      expect(PhoneCredentials.emailFor(normalised),
          PhoneCredentials.emailFor('670000000'));
    });
  });
}
