/// Money formatting for Camiva.
///
/// Every amount in the system is a whole-unit integer (XAF has no minor unit),
/// so there is never a decimal to render. Parents and teachers see the local
/// name of the currency — "5,000 FCFA" — never an ISO code or accounting term.
library;

/// Formats [amount] with thousands separators and the local currency name.
///
///   formatMoney(5000)            → '5,000 FCFA'
///   formatMoney(1000, 'XAF')     → '1,000 FCFA'
///   formatMoney(1000, 'USD')     → '1,000 USD'
String formatMoney(int amount, [String currency = 'XAF']) {
  return '${formatAmount(amount)} ${currencyLabel(currency)}';
}

/// The digits only, grouped in threes: 25000 → '25,000'.
String formatAmount(int amount) {
  final isNegative = amount < 0;
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return isNegative ? '-$buffer' : buffer.toString();
}

/// The name people actually use for the currency locally.
String currencyLabel(String currency) =>
    currency.toUpperCase() == 'XAF' ? 'FCFA' : currency.toUpperCase();
