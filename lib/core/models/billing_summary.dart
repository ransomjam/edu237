import '../utils/money.dart';

/// The monthly picture for one tutoring arrangement.
///
/// Every figure is derived server-side from the ledger when it is read: the
/// balance is the teacher's monthly fee minus the successful payments inside
/// the current period. Nothing is stored, so a balance cannot drift from the
/// payments behind it.
///
/// Absent entirely when the teacher has not set a monthly fee — in that case
/// the app shows nothing about dues rather than inventing a figure.
class BillingSummary {
  const BillingSummary({
    required this.monthlyAmount,
    required this.currency,
    required this.startedOn,
    required this.periodStart,
    required this.periodEnd,
    required this.nextDueOn,
    required this.paidThisPeriod,
    required this.balance,
    this.lastPaidAt,
  });

  /// The teacher's own fee for the month. Not an Camiva price.
  final int monthlyAmount;
  final String currency;

  /// When tutoring started, for the parent's card.
  final DateTime startedOn;

  final DateTime periodStart;
  final DateTime periodEnd;

  /// The day the next month's fee falls due.
  final DateTime nextDueOn;

  final int paidThisPeriod;

  /// What is still owed for this month. Zero once fully paid.
  final int balance;

  final DateTime? lastPaidAt;

  bool get isSettled => balance <= 0;

  /// True once part — but not all — of the month has been paid.
  bool get isPartlyPaid => paidThisPeriod > 0 && balance > 0;

  String get formattedBalance => formatMoney(balance, currency);
  String get formattedMonthly => formatMoney(monthlyAmount, currency);
  String get formattedPaid => formatMoney(paidThisPeriod, currency);

  factory BillingSummary.fromMap(Map<String, dynamic> map) {
    final lastPaidAt = map['last_paid_at'] as String?;
    return BillingSummary(
      monthlyAmount: (map['monthly_amount'] as num?)?.toInt() ?? 0,
      currency: (map['currency'] as String?) ?? 'XAF',
      startedOn: DateTime.parse(map['started_on'] as String),
      periodStart: DateTime.parse(map['period_start'] as String),
      periodEnd: DateTime.parse(map['period_end'] as String),
      nextDueOn: DateTime.parse(map['next_due_on'] as String),
      paidThisPeriod: (map['paid_this_period'] as num?)?.toInt() ?? 0,
      balance: (map['balance'] as num?)?.toInt() ?? 0,
      lastPaidAt: lastPaidAt == null ? null : DateTime.parse(lastPaidAt),
    );
  }
}
