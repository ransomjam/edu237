import '../utils/money.dart';

/// A teacher's money position, derived entirely from the transaction ledger.
///
/// There is no stored balance anywhere in Camiva: the server recomputes these
/// figures from successful tutoring payments minus withdrawals every time they
/// are read, so the numbers can never drift from what actually happened.
class TeacherEarnings {
  const TeacherEarnings({
    required this.available,
    required this.pending,
    required this.lifetime,
    required this.withdrawn,
    required this.currency,
  });

  /// Withdrawable right now: settled earnings minus anything already withdrawn
  /// or reserved by a withdrawal in progress.
  final int available;

  /// Successful payments that have not finished settling yet.
  final int pending;

  /// Everything ever earned through Camiva payments.
  final int lifetime;

  /// Everything already paid out.
  final int withdrawn;

  final String currency;

  String get formattedAvailable => formatMoney(available, currency);
  String get formattedPending => formatMoney(pending, currency);
  String get formattedLifetime => formatMoney(lifetime, currency);

  bool get hasAnything => lifetime > 0;

  factory TeacherEarnings.fromMap(Map<String, dynamic> map) {
    return TeacherEarnings(
      available: (map['available'] as int?) ?? 0,
      pending: (map['pending'] as int?) ?? 0,
      lifetime: (map['lifetime'] as int?) ?? 0,
      withdrawn: (map['withdrawn'] as int?) ?? 0,
      currency: (map['currency'] as String?) ?? 'XAF',
    );
  }

  static const TeacherEarnings empty = TeacherEarnings(
    available: 0,
    pending: 0,
    lifetime: 0,
    withdrawn: 0,
    currency: 'XAF',
  );
}

/// A teacher's Camiva transaction history, shown on their profile.
///
/// This states what has happened on the platform and nothing more: it is not a
/// quality rating, a certification, or a promise about results.
class TeacherActivity {
  const TeacherActivity({
    required this.completedPayments,
    required this.activeRelationships,
  });

  final int completedPayments;
  final int activeRelationships;

  bool get hasActivity => completedPayments > 0 || activeRelationships > 0;

  factory TeacherActivity.fromMap(Map<String, dynamic> map) {
    return TeacherActivity(
      completedPayments: (map['completed_payments'] as int?) ?? 0,
      activeRelationships: (map['active_relationships'] as int?) ?? 0,
    );
  }

  static const TeacherActivity none =
      TeacherActivity(completedPayments: 0, activeRelationships: 0);
}
