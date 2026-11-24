import '../utils/money.dart';

/// Where a withdrawal stands.
///
/// A withdrawal only becomes [successful] when the money has actually been
/// sent: either Fapshi confirms the payout, or an Camiva admin settles it by
/// hand and records their reference. Never because the app made a request that
/// returned 200.
enum WithdrawalStatus {
  requested,
  processing,
  successful,
  failed,
  cancelled;

  static WithdrawalStatus fromString(String? value) {
    return switch (value) {
      'requested' => WithdrawalStatus.requested,
      'processing' => WithdrawalStatus.processing,
      'successful' => WithdrawalStatus.successful,
      'failed' => WithdrawalStatus.failed,
      'cancelled' => WithdrawalStatus.cancelled,
      _ => throw FormatException('Unsupported withdrawal status: $value'),
    };
  }

  String get value => name;

  bool get isInFlight =>
      this == WithdrawalStatus.requested || this == WithdrawalStatus.processing;

  String get label => switch (this) {
        WithdrawalStatus.requested => 'Requested',
        WithdrawalStatus.processing => 'Processing',
        WithdrawalStatus.successful => 'Sent',
        WithdrawalStatus.failed => 'Failed',
        WithdrawalStatus.cancelled => 'Cancelled',
      };

  String get message => switch (this) {
        WithdrawalStatus.requested => 'Camiva is sending your money.',
        WithdrawalStatus.processing => 'Sending your money…',
        WithdrawalStatus.successful => 'Money sent to your number.',
        WithdrawalStatus.failed =>
          'Withdrawal failed. Your earnings are unchanged.',
        WithdrawalStatus.cancelled =>
          'Withdrawal not sent. Your earnings are unchanged.',
      };
}

/// How a withdrawal is settled.
///
/// Manual settlement is a real mode, not a workaround: Fapshi disburses only
/// through a separate, provider-activated payout service, so until Camiva has
/// one, an admin sends the money and records that they did. The record always
/// says which route was taken - a manual settlement is never presented as a
/// provider payout.
enum SettlementMode {
  manual,
  provider;

  static SettlementMode? fromString(String? value) => switch (value) {
        'manual' => SettlementMode.manual,
        'provider' => SettlementMode.provider,
        _ => null,
      };

  String get value => name;
}

/// A teacher's request to move earnings out of Camiva.
class Withdrawal {
  const Withdrawal({
    required this.id,
    required this.teacherId,
    required this.amount,
    required this.currency,
    required this.status,
    required this.payoutMedium,
    required this.payoutPhone,
    required this.createdAt,
    required this.updatedAt,
    this.providerTransId,
    this.failureReason,
    this.completedAt,
    this.settlementMode,
    this.manualReference,
  });

  final String id;
  final String teacherId;
  final int amount;
  final String currency;
  final WithdrawalStatus status;

  /// Snapshot of the destination at request time, so history stays truthful
  /// even after the teacher changes their payout number.
  final String payoutMedium;
  final String payoutPhone;

  final String? providerTransId;
  final String? failureReason;

  /// Which route settled this withdrawal, once it has been settled.
  final SettlementMode? settlementMode;

  /// The reference an admin recorded when they sent the money by hand. Shown to
  /// the teacher so they can match it against their mobile money statement.
  final String? manualReference;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  String get formattedAmount => formatMoney(amount, currency);

  /// Only the last two digits are ever shown back to the teacher.
  String get maskedPhone => payoutPhone.length < 4
      ? '••••'
      : '•••• ${payoutPhone.substring(payoutPhone.length - 2)}';

  factory Withdrawal.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String?;
    final teacherId = map['teacher_id'] as String?;
    final amount = map['amount'] as int?;
    final status = map['status'] as String?;
    final createdAt = map['created_at'] as String?;
    final updatedAt = map['updated_at'] as String?;

    if (id == null ||
        teacherId == null ||
        amount == null ||
        status == null ||
        createdAt == null ||
        updatedAt == null) {
      throw const FormatException('Withdrawal row is missing required data.');
    }

    final completedAt = map['completed_at'] as String?;

    return Withdrawal(
      id: id,
      teacherId: teacherId,
      amount: amount,
      currency: (map['currency'] as String?) ?? 'XAF',
      status: WithdrawalStatus.fromString(status),
      payoutMedium: (map['payout_medium'] as String?) ?? 'mobile money',
      payoutPhone: (map['payout_phone'] as String?) ?? '',
      providerTransId: map['provider_trans_id'] as String?,
      failureReason: map['failure_reason'] as String?,
      settlementMode:
          SettlementMode.fromString(map['settlement_mode'] as String?),
      manualReference: map['manual_reference'] as String?,
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
      completedAt: completedAt == null ? null : DateTime.parse(completedAt),
    );
  }
}

/// Where a teacher's withdrawals are sent.
///
/// Only the owning teacher can read or change this, and the payout itself
/// always uses the stored destination — a client can never redirect money by
/// sending a different number with a withdrawal request.
class PayoutAccount {
  const PayoutAccount({
    required this.teacherId,
    required this.medium,
    required this.phone,
    this.accountName,
  });

  final String teacherId;

  /// 'mobile money' or 'orange money' — the mediums Fapshi pays out to.
  final String medium;

  /// Local 9-digit Cameroon number, e.g. 6XXXXXXXX.
  final String phone;

  final String? accountName;

  String get maskedPhone =>
      phone.length < 4 ? '••••' : '•••• ${phone.substring(phone.length - 2)}';

  /// The format Fapshi expects for a payout destination.
  static bool isValidPhone(String value) =>
      RegExp(r'^6\d{8}$').hasMatch(value.trim());

  factory PayoutAccount.fromMap(Map<String, dynamic> map) {
    return PayoutAccount(
      teacherId: map['teacher_id'] as String,
      medium: (map['medium'] as String?) ?? 'mobile money',
      phone: (map['phone'] as String?) ?? '',
      accountName: map['account_name'] as String?,
    );
  }

  Map<String, dynamic> toUpsertMap() => {
        'teacher_id': teacherId,
        'medium': medium,
        'phone': phone.trim(),
        if ((accountName ?? '').trim().isNotEmpty)
          'account_name': accountName!.trim(),
      };
}
