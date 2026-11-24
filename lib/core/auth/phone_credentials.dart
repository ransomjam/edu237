import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Turns a phone number and PIN into the credentials Supabase authenticates
/// with.
///
/// WHY THIS EXISTS
/// ---------------------------------------------------------------------------
/// People here sign in with a phone number and a short PIN, not an email and a
/// password. Supabase's phone provider needs an SMS provider and an OTP round
/// trip, which this flow deliberately avoids — so the existing email/password
/// provider is kept, and the phone becomes the identity:
///
///   phone 670000000  ->  670000000@camiva.app
///   PIN   1234       ->  sha256("camiva:237670000000:1234")
///
/// Two things follow from hashing the PIN rather than sending it:
///
///   * The raw PIN never leaves the device, so it is never in a request body,
///     a log, or Supabase's auth records.
///   * The stored secret is 64 characters, which satisfies password length
///     rules that a 4-digit PIN would fail.
///
/// A PIN is not a strong secret — four digits is ten thousand combinations —
/// and this class does not pretend otherwise. What protects an account is the
/// provider's rate limiting on failed sign-ins, plus the fact that an attacker
/// needs the phone number too.
abstract final class PhoneCredentials {
  /// The domain the synthetic addresses live under. Nothing is ever sent to it.
  static const String domain = 'camiva.app';

  /// Cameroon's country code. Numbers are stored locally as 9 digits and only
  /// carry the code inside the hash, so a person who later signs in with the
  /// international form still matches.
  static const String countryCode = '237';

  static const int minPinLength = 4;
  static const int maxPinLength = 6;

  /// Strips spaces, dashes and any country code down to the local 9 digits.
  ///
  /// Accepts the forms people actually type: `670 00 00 00`, `+237670000000`,
  /// `00237670000000`, `670000000`.
  static String? normalisePhone(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');

    if (digits.startsWith('00$countryCode')) {
      digits = digits.substring(2 + countryCode.length);
    } else if (digits.startsWith(countryCode) && digits.length > 9) {
      digits = digits.substring(countryCode.length);
    }

    return isValidPhone(digits) ? digits : null;
  }

  /// A Cameroon mobile number: nine digits starting with 6.
  static bool isValidPhone(String digits) =>
      RegExp(r'^6\d{8}$').hasMatch(digits);

  static bool isValidPin(String pin) =>
      RegExp('^\\d{$minPinLength,$maxPinLength}\$').hasMatch(pin);

  /// The address this phone number authenticates as.
  static String emailFor(String normalisedPhone) =>
      '$normalisedPhone@$domain';

  /// The secret derived from the phone and PIN together.
  ///
  /// The phone is part of the input so the same PIN on two accounts produces
  /// different secrets.
  static String secretFor(String normalisedPhone, String pin) {
    final input = 'camiva:$countryCode$normalisedPhone:$pin';
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// The number as a person reads it back: `670 00 00 00`.
  static String format(String normalisedPhone) {
    if (!isValidPhone(normalisedPhone)) return normalisedPhone;
    final p = normalisedPhone;
    return '${p.substring(0, 3)} ${p.substring(3, 5)} '
        '${p.substring(5, 7)} ${p.substring(7)}';
  }

  /// The phone number behind a synthetic address, for showing someone which
  /// account they are signed in as.
  static String? phoneFromEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 0) return null;
    final local = email.substring(0, at);
    return isValidPhone(local) ? local : null;
  }
}
