import '../utils/money.dart';

/// What a payment is for.
///
/// These are the only three commercial events Camiva collects money for. The
/// amount for each is decided server-side from the platform fee configuration
/// (fees) or the teacher's rate (tutoring) — never by the app.
enum PaymentPurpose {
  /// The recurring Camiva service fee, paid by a teacher.
  teacherServiceFee('teacher_service_fee'),

  /// The one-time charge that activates a new parent–teacher relationship.
  matchActivation('match_activation'),

  /// A parent paying for tutoring.
  tutoringPayment('tutoring_payment');

  const PaymentPurpose(this.value);

  final String value;

  static PaymentPurpose fromString(String? value) {
    return switch (value) {
      'teacher_service_fee' => PaymentPurpose.teacherServiceFee,
      'match_activation' => PaymentPurpose.matchActivation,
      'tutoring_payment' => PaymentPurpose.tutoringPayment,
      _ => throw FormatException('Unsupported payment purpose: $value'),
    };
  }

  /// Plain-language label for receipts and history. No accounting terms.
  String get label => switch (this) {
        PaymentPurpose.teacherServiceFee => 'Camiva service fee',
        PaymentPurpose.matchActivation => 'Relationship activation',
        PaymentPurpose.tutoringPayment => 'Tutoring payment',
      };
}

/// Where a payment stands.
///
/// The app never decides this. A transaction is [pending] until Fapshi confirms
/// an outcome through the webhook (or an explicit server-side verification),
/// which is what moves it to a terminal state.
enum PaymentStatus {
  pending,
  successful,
  failed,
  cancelled,
  refunded;

  static PaymentStatus fromString(String? value) {
    return switch (value) {
      'pending' => PaymentStatus.pending,
      'successful' => PaymentStatus.successful,
      'failed' => PaymentStatus.failed,
      'cancelled' => PaymentStatus.cancelled,
      'refunded' => PaymentStatus.refunded,
      _ => throw FormatException('Unsupported payment status: $value'),
    };
  }

  String get value => name;

  bool get isPending => this == PaymentStatus.pending;
  bool get isSuccessful => this == PaymentStatus.successful;
  bool get isTerminal => this != PaymentStatus.pending;

  /// A failed or cancelled payment can simply be started again.
  bool get canRetry =>
      this == PaymentStatus.failed || this == PaymentStatus.cancelled;

  /// The exact wording the payment screens use for each state.
  String get message => switch (this) {
        PaymentStatus.pending => 'Payment processing…',
        PaymentStatus.successful => 'Payment successful',
        PaymentStatus.failed => 'Payment failed. Try again.',
        PaymentStatus.cancelled => 'Payment cancelled.',
        PaymentStatus.refunded => 'Payment refunded.',
      };
}

/// One row of the Camiva payment ledger.
///
/// Records are written server-side and are effectively immutable: only the
/// status and the provider references ever change, and only through a confirmed
/// provider outcome. This is what makes the parent's payment history and the
/// teacher's earnings history auditable rather than merely displayed.
class PaymentTransaction {
  const PaymentTransaction({
    required this.id,
    required this.purpose,
    required this.payerId,
    required this.amount,
    required this.currency,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.teacherId,
    this.studentId,
    this.relationshipId,
    this.sessionId,
    this.providerTransId,
    this.checkoutUrl,
    this.description,
    this.failureReason,
    this.paidAt,
    this.studentName,
    this.teacherName,
  });

  final String id;
  final PaymentPurpose purpose;
  final String payerId;

  final String? parentId;
  final String? teacherId;
  final String? studentId;
  final String? relationshipId;
  final String? sessionId;

  final int amount;
  final String currency;
  final PaymentStatus status;

  /// The Fapshi transaction id — the reference shown on a receipt and used by
  /// support to trace a payment with the provider.
  final String? providerTransId;

  /// Fapshi-hosted checkout link, when the hosted flow is used.
  final String? checkoutUrl;

  final String? description;
  final String? failureReason;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? paidAt;

  /// Display context, present when the row is read through the
  /// `payment_history` view: the child the payment was for and the teacher it
  /// relates to. Null when reading the bare table.
  final String? studentName;
  final String? teacherName;

  /// The reference a person can quote to support.
  String get reference => providerTransId ?? id.split('-').first.toUpperCase();

  String get formattedAmount => formatMoney(amount, currency);

  factory PaymentTransaction.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String?;
    final purpose = map['purpose'] as String?;
    final payerId = map['payer_id'] as String?;
    final amount = map['amount'] as int?;
    final status = map['status'] as String?;
    final createdAt = map['created_at'] as String?;
    final updatedAt = map['updated_at'] as String?;

    if (id == null ||
        purpose == null ||
        payerId == null ||
        amount == null ||
        status == null ||
        createdAt == null ||
        updatedAt == null) {
      throw const FormatException('Payment row is missing required data.');
    }

    final paidAt = map['paid_at'] as String?;

    return PaymentTransaction(
      id: id,
      purpose: PaymentPurpose.fromString(purpose),
      payerId: payerId,
      parentId: map['parent_id'] as String?,
      teacherId: map['teacher_id'] as String?,
      studentId: map['student_id'] as String?,
      relationshipId: map['relationship_id'] as String?,
      sessionId: map['session_id'] as String?,
      amount: amount,
      currency: (map['currency'] as String?) ?? 'XAF',
      status: PaymentStatus.fromString(status),
      providerTransId: map['provider_trans_id'] as String?,
      checkoutUrl: map['checkout_url'] as String?,
      description: map['description'] as String?,
      failureReason: map['failure_reason'] as String?,
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
      paidAt: paidAt == null ? null : DateTime.parse(paidAt),
      studentName: map['student_name'] as String?,
      teacherName: map['teacher_name'] as String?,
    );
  }
}
