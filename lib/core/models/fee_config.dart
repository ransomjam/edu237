/// The platform's current, operator-managed pricing.
///
/// Nothing here is a business rule baked into the app: every amount is read
/// from the `platform_fee_config` row, and a null amount means "not configured,
/// therefore not charged". Final pricing can change without touching code.
class FeeConfig {
  const FeeConfig({
    required this.currency,
    required this.teacherServiceFeeAmount,
    required this.teacherServiceFeeIntervalDays,
    required this.matchActivationFeeAmount,
    required this.matchActivationRequired,
    required this.settlementDelayHours,
    required this.minWithdrawalAmount,
  });

  final String currency;

  /// Recurring Camiva service fee for a teacher. Null when not configured.
  final int? teacherServiceFeeAmount;
  final int teacherServiceFeeIntervalDays;

  /// One-time relationship activation charge. Null when not configured.
  final int? matchActivationFeeAmount;
  final bool matchActivationRequired;

  /// How long a successful tutoring payment stays "Pending" before it becomes
  /// withdrawable.
  final int settlementDelayHours;

  final int minWithdrawalAmount;

  /// True when a new relationship actually costs the teacher something. Both
  /// conditions matter: the switch AND a real amount.
  bool get chargesForActivation =>
      matchActivationRequired && (matchActivationFeeAmount ?? 0) > 0;

  /// True when the recurring service fee is switched on.
  bool get chargesServiceFee => (teacherServiceFeeAmount ?? 0) > 0;

  factory FeeConfig.fromMap(Map<String, dynamic> map) {
    return FeeConfig(
      currency: (map['currency'] as String?) ?? 'XAF',
      teacherServiceFeeAmount: map['teacher_service_fee_amount'] as int?,
      teacherServiceFeeIntervalDays:
          (map['teacher_service_fee_interval_days'] as int?) ?? 30,
      matchActivationFeeAmount: map['match_activation_fee_amount'] as int?,
      matchActivationRequired:
          (map['match_activation_required'] as bool?) ?? false,
      settlementDelayHours: (map['settlement_delay_hours'] as int?) ?? 24,
      minWithdrawalAmount: (map['min_withdrawal_amount'] as int?) ?? 100,
    );
  }

  /// A safe default used only when pricing cannot be read: nothing is charged.
  /// The app must never invent a price when it does not know one.
  static const FeeConfig unknown = FeeConfig(
    currency: 'XAF',
    teacherServiceFeeAmount: null,
    teacherServiceFeeIntervalDays: 30,
    matchActivationFeeAmount: null,
    matchActivationRequired: false,
    settlementDelayHours: 24,
    minWithdrawalAmount: 100,
  );
}

/// Whether a relationship still needs its activation payment.
///
/// Derived server-side from the ledger, so it can never claim "active" without
/// a successful payment behind it.
enum ActivationState {
  /// No Platform Charge applies (switched off, or no amount configured).
  notRequired,

  /// A charge applies, but the parent has not confirmed the tutoring
  /// arrangement yet — so nothing is owed. This is the rule that stops a
  /// teacher paying for a request that never becomes real tutoring.
  blocked,

  /// The parent confirmed; the charge is now owed and has not been paid.
  required,

  /// An activation payment exists and is still in flight.
  pending,

  /// Paid and confirmed — the relationship is fully operational.
  active;

  static ActivationState fromString(String? value) {
    return switch (value) {
      'not_required' => ActivationState.notRequired,
      'blocked' => ActivationState.blocked,
      'required' => ActivationState.required,
      'pending' => ActivationState.pending,
      'active' => ActivationState.active,
      _ => throw FormatException('Unsupported activation state: $value'),
    };
  }

  /// Whether the relationship is operational — the condition that also gates
  /// the reveal of the parent's contact details.
  bool get isOperational =>
      this == ActivationState.notRequired || this == ActivationState.active;

  bool get needsPayment => this == ActivationState.required;

  /// Waiting on the parent, not on money.
  bool get awaitingParent => this == ActivationState.blocked;
}
