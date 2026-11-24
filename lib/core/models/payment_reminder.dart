/// What a reminder is about.
enum ReminderKind {
  paymentReceived('payment_received'),
  paymentFailed('payment_failed'),
  serviceFeeDue('service_fee_due'),
  serviceFeeOverdue('service_fee_overdue'),
  relationshipActivated('relationship_activated'),
  withdrawalUpdate('withdrawal_update'),
  paymentDue('payment_due'),
  agreementUpdate('agreement_update'),
  verificationUpdate('verification_update'),
  requestReceived('request_received'),
  requestAnswered('request_answered'),
  lessonScheduled('lesson_scheduled'),

  /// Anything the server sends that this build does not know about yet. A
  /// reminder is still worth showing - its title and body are already written
  /// for the reader - so an unknown kind must never lose the whole list.
  other('other');

  const ReminderKind(this.value);

  final String value;

  static ReminderKind fromString(String? value) {
    return switch (value) {
      'payment_received' => ReminderKind.paymentReceived,
      'payment_failed' => ReminderKind.paymentFailed,
      'service_fee_due' => ReminderKind.serviceFeeDue,
      'service_fee_overdue' => ReminderKind.serviceFeeOverdue,
      'relationship_activated' => ReminderKind.relationshipActivated,
      'withdrawal_update' => ReminderKind.withdrawalUpdate,
      'payment_due' => ReminderKind.paymentDue,
      'agreement_update' => ReminderKind.agreementUpdate,
      'verification_update' => ReminderKind.verificationUpdate,
      'request_received' => ReminderKind.requestReceived,
      'request_answered' => ReminderKind.requestAnswered,
      'lesson_scheduled' => ReminderKind.lessonScheduled,
      // Never throw: one unrecognised kind used to fail the whole fetch, so a
      // reader lost every reminder they had because of one new server value.
      _ => ReminderKind.other,
    };
  }
}

/// An in-app reminder that has genuinely been delivered.
///
/// A row exists only because the server created one at a real event (a payment
/// confirmed, a payout settled, a fee period opened), and creating the row IS
/// the delivery — it appears in the recipient's reminders list. Nothing here
/// claims a push notification was sent: the app has no push transport yet, so
/// [deliveredChannel] is always `in_app`.
class PaymentReminder {
  const PaymentReminder({
    required this.id,
    required this.userId,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.deliveredChannel,
    this.paymentId,
    this.relationshipId,
    this.withdrawalId,
    this.readAt,
  });

  final String id;
  final String userId;
  final ReminderKind kind;
  final String title;
  final String body;
  final String deliveredChannel;
  final String? paymentId;
  final String? relationshipId;
  final String? withdrawalId;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  factory PaymentReminder.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String?;
    final userId = map['user_id'] as String?;
    final title = map['title'] as String?;
    final body = map['body'] as String?;
    final createdAt = map['created_at'] as String?;

    if (id == null ||
        userId == null ||
        title == null ||
        body == null ||
        createdAt == null) {
      throw const FormatException('Reminder row is missing required data.');
    }

    final readAt = map['read_at'] as String?;

    return PaymentReminder(
      id: id,
      userId: userId,
      kind: ReminderKind.fromString(map['kind'] as String?),
      title: title,
      body: body,
      deliveredChannel: (map['delivered_channel'] as String?) ?? 'in_app',
      paymentId: map['payment_id'] as String?,
      relationshipId: map['relationship_id'] as String?,
      withdrawalId: map['withdrawal_id'] as String?,
      createdAt: DateTime.parse(createdAt),
      readAt: readAt == null ? null : DateTime.parse(readAt),
    );
  }
}

/// Where a teacher stands on the recurring Camiva service fee.
enum ServiceFeeStatus {
  due,
  reminded,
  paid,
  overdue;

  static ServiceFeeStatus fromString(String? value) {
    return switch (value) {
      'due' => ServiceFeeStatus.due,
      'reminded' => ServiceFeeStatus.reminded,
      'paid' => ServiceFeeStatus.paid,
      'overdue' => ServiceFeeStatus.overdue,
      _ => throw FormatException('Unsupported service fee status: $value'),
    };
  }

  bool get isOutstanding => this != ServiceFeeStatus.paid;

  String get label => switch (this) {
        ServiceFeeStatus.due => 'Due',
        ServiceFeeStatus.reminded => 'Due',
        ServiceFeeStatus.paid => 'Paid',
        ServiceFeeStatus.overdue => 'Overdue',
      };
}

/// One billing window of the recurring service fee.
///
/// This is the foundation the spec asks for — due / reminded / paid / overdue —
/// not a billing engine. Nothing charges automatically.
class ServiceFeePeriod {
  const ServiceFeePeriod({
    required this.id,
    required this.teacherId,
    required this.periodStart,
    required this.periodEnd,
    required this.amount,
    required this.currency,
    required this.status,
    this.paymentId,
    this.reminderSentAt,
    this.paidAt,
  });

  final String id;
  final String teacherId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int amount;
  final String currency;
  final ServiceFeeStatus status;
  final String? paymentId;
  final DateTime? reminderSentAt;
  final DateTime? paidAt;

  factory ServiceFeePeriod.fromMap(Map<String, dynamic> map) {
    final reminderSentAt = map['reminder_sent_at'] as String?;
    final paidAt = map['paid_at'] as String?;
    return ServiceFeePeriod(
      id: map['id'] as String,
      teacherId: map['teacher_id'] as String,
      periodStart: DateTime.parse(map['period_start'] as String),
      periodEnd: DateTime.parse(map['period_end'] as String),
      amount: map['amount'] as int,
      currency: (map['currency'] as String?) ?? 'XAF',
      status: ServiceFeeStatus.fromString(map['status'] as String?),
      paymentId: map['payment_id'] as String?,
      reminderSentAt:
          reminderSentAt == null ? null : DateTime.parse(reminderSentAt),
      paidAt: paidAt == null ? null : DateTime.parse(paidAt),
    );
  }
}
